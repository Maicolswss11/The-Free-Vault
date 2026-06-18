-- Ludograph v5.5.13 — pagine gioco canoniche per duplicati tecnici.
--
-- v5.5.12 stabilizza get_catalog_game. Questa migrazione aggiunge un
-- ulteriore passaggio: chiavi diverse che rappresentano la stessa opera
-- editoriale tecnica (stesso titolo normalizzato, stesso autore/publisher e
-- anno vicino) devono risolvere alla stessa scheda canonica, evitando due URL
-- e due pagine separate per casi come Red Dead Redemption 2 IGDB vs Steam/Epic.

begin;

create index if not exists catalog_games_normalized_title_idx
on public.catalog_games (public.catalog_normalized_title(title));

create index if not exists catalog_games_release_year_idx
on public.catalog_games(release_year desc);

create or replace function public.catalog_canonical_detail_match_key(p_key text)
returns text
language plpgsql
stable
security definer
set search_path = ''
set statement_timeout = '6s'
as $$
declare
  v_key text := nullif(trim(p_key), '');
  v_seed public.catalog_games%rowtype;
  v_master_game_id text;
  v_seed_game_type text := 'unknown';
  v_title_key text;
  v_maker_key text;
  v_year integer;
  v_cover_key text;
  v_result text;
begin
  if v_key is null then
    return null;
  end if;

  select * into v_seed
  from public.catalog_games cg
  where cg.match_key = v_key
  order by case cg.source_kind when 'hybrid' then 0 when 'catalog' then 1 when 'master' then 2 else 3 end,
    cg.match_key
  limit 1;

  if not found then
    select * into v_seed
    from public.catalog_games cg
    where cg.canonical_id = v_key
    order by case cg.source_kind when 'hybrid' then 0 when 'catalog' then 1 when 'master' then 2 else 3 end,
      cg.match_key
    limit 1;
  end if;

  if not found then
    v_master_game_id := public.resolve_master_game_id(v_key);
    if v_master_game_id is not null then
      select * into v_seed
      from public.catalog_games cg
      where cg.master_game_id = v_master_game_id
      order by case cg.source_kind when 'hybrid' then 0 when 'catalog' then 1 when 'master' then 2 else 3 end,
        cg.match_key
      limit 1;
    end if;
  end if;

  if not found then
    select * into v_seed
    from public.catalog_games cg
    where cg.store_listings @> jsonb_build_array(jsonb_build_object('listing_id', v_key))
    order by case cg.source_kind when 'hybrid' then 0 when 'catalog' then 1 when 'master' then 2 else 3 end,
      cg.match_key
    limit 1;
  end if;

  if not found then
    return null;
  end if;

  select coalesce(g.game_type, 'unknown') into v_seed_game_type
  from public.games g
  where g.id = v_seed.master_game_id
  limit 1;
  v_seed_game_type := coalesce(v_seed_game_type, 'unknown');

  -- Remake, remaster, bundle, DLC e collection non vanno fusi con la base.
  if public.catalog_is_separate_game_type(v_seed_game_type) then
    return v_seed.match_key;
  end if;

  v_title_key := public.catalog_normalized_title(v_seed.title);
  v_maker_key := public.catalog_normalized_title(coalesce(nullif(v_seed.developer, ''), nullif(v_seed.publisher, ''), ''));
  v_year := coalesce(v_seed.release_year, extract(year from v_seed.release_date)::integer);
  v_cover_key := public.catalog_cover_identity(v_seed.image_url);

  if v_title_key = '' then
    return v_seed.match_key;
  end if;

  with candidates as materialized (
    select
      cg.match_key,
      cg.source_kind,
      cg.release_year,
      cg.release_date,
      cg.master_game_id,
      cg.description,
      cg.image_url,
      cg.stores,
      cg.store_listings,
      coalesce(g.game_type, 'unknown') as game_type,
      public.catalog_normalized_title(coalesce(nullif(cg.developer, ''), nullif(cg.publisher, ''), '')) as maker_key,
      public.catalog_cover_identity(cg.image_url) as cover_key
    from public.catalog_games cg
    left join public.games g on g.id = cg.master_game_id
    where public.catalog_normalized_title(cg.title) = v_title_key
      and not public.catalog_is_separate_game_type(coalesce(g.game_type, 'unknown'))
  ), filtered as (
    select c.*
    from candidates c
    where (
        v_year is null
        or coalesce(c.release_year, extract(year from c.release_date)::integer) is null
        or abs(coalesce(c.release_year, extract(year from c.release_date)::integer) - v_year) <= 2
        or (v_seed.master_game_id is not null and c.master_game_id = v_seed.master_game_id)
      )
      and (
        v_maker_key = ''
        or c.maker_key = ''
        or c.maker_key = v_maker_key
        or (v_seed.master_game_id is not null and c.master_game_id = v_seed.master_game_id)
        or (v_cover_key is not null and c.cover_key = v_cover_key)
      )
  )
  select f.match_key into v_result
  from filtered f
  order by
    case f.source_kind when 'hybrid' then 0 when 'catalog' then 1 when 'master' then 2 else 3 end,
    greatest(cardinality(coalesce(f.stores, '{}'::text[])), jsonb_array_length(coalesce(f.store_listings, '[]'::jsonb))) desc,
    case when nullif(f.description, '') is not null then 0 else 1 end,
    case when nullif(f.image_url, '') is not null then 0 else 1 end,
    coalesce(f.release_year, extract(year from f.release_date)::integer) asc nulls last,
    f.match_key
  limit 1;

  return coalesce(v_result, v_seed.match_key);
end;
$$;

revoke all on function public.catalog_canonical_detail_match_key(text) from public;
grant execute on function public.catalog_canonical_detail_match_key(text) to anon, authenticated, service_role;

create or replace function public.get_catalog_game(p_key text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
set statement_timeout = '8s'
as $$
declare
  v_key text := nullif(trim(p_key), '');
  v_match_key text;
  v_master_game_id text;
  v_game public.catalog_games%rowtype;
begin
  if v_key is null then
    return null;
  end if;

  v_match_key := public.catalog_canonical_detail_match_key(v_key);
  if v_match_key is not null then
    select * into v_game
    from public.catalog_games cg
    where cg.match_key = v_match_key
    limit 1;
    if found then
      return public.catalog_game_card_json(v_game)
        || jsonb_build_object(
          'requested_key', v_key,
          'canonical_route_key', v_game.match_key
        );
    end if;
  end if;

  -- Fallback difensivo: conserva il lookup indicizzato di v5.5.12 se il
  -- risolutore canonico non trova nulla.
  select * into v_game
  from public.catalog_games cg
  where cg.match_key = v_key
  order by case cg.source_kind when 'hybrid' then 0 when 'master' then 1 else 2 end
  limit 1;
  if found then
    return public.catalog_game_card_json(v_game)
      || jsonb_build_object('requested_key', v_key, 'canonical_route_key', v_game.match_key);
  end if;

  select * into v_game
  from public.catalog_games cg
  where cg.canonical_id = v_key
  order by case cg.source_kind when 'hybrid' then 0 when 'master' then 1 else 2 end, cg.match_key
  limit 1;
  if found then
    return public.catalog_game_card_json(v_game)
      || jsonb_build_object('requested_key', v_key, 'canonical_route_key', v_game.match_key);
  end if;

  v_master_game_id := public.resolve_master_game_id(v_key);
  if v_master_game_id is not null then
    select * into v_game
    from public.catalog_games cg
    where cg.master_game_id = v_master_game_id
    order by case cg.source_kind when 'hybrid' then 0 when 'master' then 1 else 2 end, cg.match_key
    limit 1;
    if found then
      return public.catalog_game_card_json(v_game)
        || jsonb_build_object('requested_key', v_key, 'canonical_route_key', v_game.match_key);
    end if;
  end if;

  select * into v_game
  from public.catalog_games cg
  where cg.store_listings @> jsonb_build_array(jsonb_build_object('listing_id', v_key))
  order by case cg.source_kind when 'hybrid' then 0 when 'master' then 1 else 2 end, cg.match_key
  limit 1;
  if found then
    return public.catalog_game_card_json(v_game)
      || jsonb_build_object('requested_key', v_key, 'canonical_route_key', v_game.match_key);
  end if;

  return null;
end;
$$;

revoke all on function public.get_catalog_game(text) from public;
grant execute on function public.get_catalog_game(text) to anon, authenticated;

comment on function public.catalog_canonical_detail_match_key(text) is
'Ludograph v5.5.13: risolve duplicati tecnici del catalogo verso una sola scheda gioco canonica.';

comment on function public.get_catalog_game(text) is
'Ludograph v5.5.13: lookup scheda gioco stabile più canonicalizzazione dei duplicati tecnici.';

commit;

notify pgrst, 'reload schema';
