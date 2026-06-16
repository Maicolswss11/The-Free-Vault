-- Ludograph v5.3.1 — Search Disambiguation & Franchise Deduplication
-- Raggruppa editorialmente i record con stesso titolo e stessa copertina,
-- senza eliminare i record Master originali dal catalogo.

begin;

create or replace function public.catalog_editorial_identity(
  p_title text,
  p_image_url text
)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_title text;
  v_cover text;
begin
  v_title := lower(regexp_replace(
    replace(replace(replace(coalesce(trim(p_title), ''), '™', ''), '®', ''), '©', ''),
    '[^[:alnum:]]+',
    '',
    'g'
  ));

  v_cover := lower(split_part(coalesce(trim(p_image_url), ''), '?', 1));
  v_cover := regexp_replace(v_cover, '^https?://', '', 'i');
  -- Le immagini IGDB possono cambiare solo per il preset t_cover_*.
  v_cover := regexp_replace(v_cover, '/t_[^/]+/', '/', 'g');

  if v_title = '' or v_cover = '' then
    return null;
  end if;

  return md5(v_title || '|' || v_cover);
end;
$$;

create or replace function public.catalog_game_type_priority(p_game_type text)
returns integer
language sql
immutable
set search_path = ''
as $$
  select case lower(coalesce(p_game_type, ''))
    when 'main_game' then 0
    when 'remake' then 1
    when 'remaster' then 2
    when 'expanded_game' then 3
    when 'standalone_expansion' then 4
    when 'expansion' then 5
    when 'port' then 6
    when 'episode' then 7
    when 'bundle' then 8
    when 'dlc_addon' then 9
    when 'pack' then 10
    when 'update' then 11
    else 20
  end;
$$;

revoke all on function public.catalog_editorial_identity(text, text) from public;
revoke all on function public.catalog_game_type_priority(text) from public;
grant execute on function public.catalog_editorial_identity(text, text) to anon, authenticated, service_role;
grant execute on function public.catalog_game_type_priority(text) to anon, authenticated, service_role;

create or replace function public.catalog_game_card_json(p_game public.catalog_games)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'canonical_id', (p_game).canonical_id,
    'match_key', (p_game).match_key,
    'master_game_id', (p_game).master_game_id,
    'internal_id', (p_game).canonical_id,
    'listing_id', ((p_game).store_listings -> 0 ->> 'listing_id'),
    'source_kind', (p_game).source_kind,
    'store', ((p_game).store_listings -> 0 ->> 'store'),
    'stores', to_jsonb((p_game).stores),
    'store_listings', (p_game).store_listings,
    'title', (p_game).title,
    'canonical_title', (p_game).canonical_title,
    'description', (p_game).description,
    'developer', (p_game).developer,
    'publisher', (p_game).publisher,
    'image_url', (p_game).image_url,
    'store_url', (p_game).store_url,
    'release_date', (p_game).release_date,
    'release_year', (p_game).release_year,
    'market_segment', (p_game).market_segment,
    'category_group', (p_game).category_group,
    'offer_type', (p_game).offer_type,
    'platforms', to_jsonb((p_game).platforms),
    'genres', to_jsonb((p_game).genres),
    'categories', to_jsonb((p_game).categories),
    'original_price', ((p_game).store_listings -> 0 -> 'original_price'),
    'discount_price', ((p_game).store_listings -> 0 -> 'discount_price'),
    'currency_code', ((p_game).store_listings -> 0 ->> 'currency_code'),
    'fmt_original_price', ((p_game).store_listings -> 0 ->> 'fmt_original_price'),
    'fmt_discount_price', ((p_game).store_listings -> 0 ->> 'fmt_discount_price'),
    'game_type', master.game_type,
    'game_status', master.game_status,
    'igdb_id', master.source_external_id,
    'variant_parent_id', case
      when nullif(master.metadata ->> 'parent_game', '') is not null
        then 'igdb:' || (master.metadata ->> 'parent_game')
      when nullif(master.metadata ->> 'version_parent', '') is not null
        then 'igdb:' || (master.metadata ->> 'version_parent')
      else null
    end,
    'editorial_identity', public.catalog_editorial_identity((p_game).title, (p_game).image_url)
  )
  from (select 1) seed
  left join public.games master on master.id = (p_game).master_game_id;
$$;

revoke all on function public.catalog_game_card_json(public.catalog_games) from public;

create or replace function public.admin_search_franchise_candidates(
  p_query text,
  p_limit integer default 50
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
set statement_timeout = '15s'
as $$
declare
  v_result jsonb;
begin
  if not public.is_admin() then
    raise exception 'Accesso amministratore richiesto' using errcode = '42501';
  end if;

  with params as (
    select
      lower(trim(coalesce(p_query, ''))) as q,
      greatest(1, least(coalesce(p_limit, 50), 50)) as group_limit
  ), candidate_keys as materialized (
    select
      cg.match_key,
      coalesce(public.catalog_editorial_identity(cg.title, cg.image_url), cg.match_key) as group_key,
      case
        when lower(cg.title) = p.q then 100
        when lower(cg.canonical_title) = p.q then 95
        when lower(cg.title) like p.q || '%' then 80
        when lower(cg.canonical_title) like p.q || '%' then 75
        else 50
      end as relevance_score,
      public.catalog_game_type_priority(g.game_type) as type_priority,
      (
        case when cg.release_date is not null then 1 else 0 end
        + case when nullif(cg.developer, '') is not null then 1 else 0 end
        + case when cardinality(cg.platforms) > 0 then 1 else 0 end
        + case when nullif(cg.description, '') is not null then 1 else 0 end
      ) as completeness_score
    from public.catalog_games cg
    cross join params p
    left join public.games g on g.id = cg.master_game_id
    where p.q <> ''
      and lower(cg.title) like '%' || p.q || '%'
    order by relevance_score desc, lower(cg.title), cg.match_key
    limit 1000
  ), ranked as (
    select
      ck.*,
      row_number() over (
        partition by ck.group_key
        order by ck.type_priority, ck.completeness_score desc,
          (select release_date from public.catalog_games where match_key = ck.match_key) asc nulls last,
          ck.match_key
      ) as group_rank
    from candidate_keys ck
  ), groups as (
    select
      group_key,
      max(relevance_score) as relevance_score,
      max(match_key) filter (where group_rank = 1) as representative_key,
      count(*)::integer as variant_count
    from ranked
    group by group_key
    order by max(relevance_score) desc, group_key
    limit (select group_limit from params)
  )
  select coalesce(jsonb_agg(
    public.catalog_game_card_json(representative)
    || jsonb_build_object(
      'editorial_identity', groups.group_key,
      'variant_count', groups.variant_count,
      'variant_keys', coalesce((
        select jsonb_agg(r.match_key order by r.group_rank, r.match_key)
        from ranked r
        where r.group_key = groups.group_key
      ), '[]'::jsonb),
      'variants', coalesce((
        select jsonb_agg(public.catalog_game_card_json(variant_game)
          order by r.group_rank, lower(variant_game.title), variant_game.match_key)
        from ranked r
        join public.catalog_games variant_game on variant_game.match_key = r.match_key
        where r.group_key = groups.group_key
      ), '[]'::jsonb),
      'platforms', coalesce((
        select to_jsonb(array(
          select distinct platform
          from ranked r
          join public.catalog_games variant_game on variant_game.match_key = r.match_key
          cross join lateral unnest(variant_game.platforms) platform
          where r.group_key = groups.group_key
          order by platform
        ))
      ), '[]'::jsonb),
      'stores', coalesce((
        select to_jsonb(array(
          select distinct store_name
          from ranked r
          join public.catalog_games variant_game on variant_game.match_key = r.match_key
          cross join lateral unnest(variant_game.stores) store_name
          where r.group_key = groups.group_key
          order by store_name
        ))
      ), '[]'::jsonb)
    ) order by groups.relevance_score desc, lower(representative.title), representative.match_key
  ), '[]'::jsonb)
  into v_result
  from groups
  join public.catalog_games representative on representative.match_key = groups.representative_key;

  return coalesce(v_result, '[]'::jsonb);
end;
$$;

revoke all on function public.admin_search_franchise_candidates(text, integer) from public;
grant execute on function public.admin_search_franchise_candidates(text, integer) to authenticated;

create or replace function public.consolidate_franchise_variants_internal(p_franchise_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_duplicate record;
  v_merged integer := 0;
begin
  if not exists (select 1 from public.franchises where id = p_franchise_id) then
    raise exception 'Franchise non trovato';
  end if;

  for v_duplicate in
    with ranked as (
      select
        fg.game_key,
        public.catalog_editorial_identity(cg.title, cg.image_url) as identity_key,
        first_value(fg.game_key) over (
          partition by public.catalog_editorial_identity(cg.title, cg.image_url)
          order by public.catalog_game_type_priority(g.game_type),
            (case when cg.release_date is not null then 1 else 0 end
             + case when nullif(cg.developer, '') is not null then 1 else 0 end
             + case when cardinality(cg.platforms) > 0 then 1 else 0 end) desc,
            cg.release_date asc nulls last,
            fg.release_order asc,
            fg.game_key
        ) as keeper_key,
        row_number() over (
          partition by public.catalog_editorial_identity(cg.title, cg.image_url)
          order by public.catalog_game_type_priority(g.game_type),
            (case when cg.release_date is not null then 1 else 0 end
             + case when nullif(cg.developer, '') is not null then 1 else 0 end
             + case when cardinality(cg.platforms) > 0 then 1 else 0 end) desc,
            cg.release_date asc nulls last,
            fg.release_order asc,
            fg.game_key
        ) as duplicate_rank
      from public.franchise_games fg
      join public.catalog_games cg on cg.match_key = fg.game_key
      left join public.games g on g.id = cg.master_game_id
      where fg.franchise_id = p_franchise_id
        and public.catalog_editorial_identity(cg.title, cg.image_url) is not null
    )
    select game_key as duplicate_key, keeper_key
    from ranked
    where duplicate_rank > 1
  loop
    update public.franchise_games keeper
    set
      release_order = least(keeper.release_order, duplicate.release_order),
      narrative_order = coalesce(keeper.narrative_order, duplicate.narrative_order),
      note = coalesce(keeper.note, duplicate.note),
      updated_at = now()
    from public.franchise_games duplicate
    where keeper.franchise_id = p_franchise_id
      and keeper.game_key = v_duplicate.keeper_key
      and duplicate.franchise_id = p_franchise_id
      and duplicate.game_key = v_duplicate.duplicate_key;

    insert into public.franchise_game_tracks(
      track_id, franchise_id, game_key, game_id,
      narrative_order, release_order, canon_status, note
    )
    select
      track_id,
      franchise_id,
      v_duplicate.keeper_key,
      public.resolve_master_game_id(v_duplicate.keeper_key),
      narrative_order,
      release_order,
      canon_status,
      note
    from public.franchise_game_tracks
    where franchise_id = p_franchise_id
      and game_key = v_duplicate.duplicate_key
    on conflict (track_id, game_key) do update set
      narrative_order = coalesce(public.franchise_game_tracks.narrative_order, excluded.narrative_order),
      release_order = coalesce(public.franchise_game_tracks.release_order, excluded.release_order),
      canon_status = case
        when public.franchise_game_tracks.canon_status = 'unknown' then excluded.canon_status
        else public.franchise_game_tracks.canon_status
      end,
      note = coalesce(public.franchise_game_tracks.note, excluded.note),
      updated_at = now();

    delete from public.franchise_game_tracks
    where franchise_id = p_franchise_id
      and game_key = v_duplicate.duplicate_key;

    insert into public.franchise_game_relations(
      franchise_id, source_game_key, target_game_key, relation_type, note
    )
    select
      franchise_id,
      case when source_game_key = v_duplicate.duplicate_key then v_duplicate.keeper_key else source_game_key end,
      case when target_game_key = v_duplicate.duplicate_key then v_duplicate.keeper_key else target_game_key end,
      relation_type,
      note
    from public.franchise_game_relations
    where franchise_id = p_franchise_id
      and (source_game_key = v_duplicate.duplicate_key or target_game_key = v_duplicate.duplicate_key)
      and (case when source_game_key = v_duplicate.duplicate_key then v_duplicate.keeper_key else source_game_key end)
        <> (case when target_game_key = v_duplicate.duplicate_key then v_duplicate.keeper_key else target_game_key end)
    on conflict (franchise_id, source_game_key, target_game_key, relation_type) do update set
      note = coalesce(public.franchise_game_relations.note, excluded.note),
      updated_at = now();

    delete from public.franchise_game_relations
    where franchise_id = p_franchise_id
      and (source_game_key = v_duplicate.duplicate_key or target_game_key = v_duplicate.duplicate_key);

    delete from public.franchise_games
    where franchise_id = p_franchise_id
      and game_key = v_duplicate.duplicate_key;

    v_merged := v_merged + 1;
  end loop;

  return jsonb_build_object('merged', v_merged, 'franchise_id', p_franchise_id);
end;
$$;

revoke all on function public.consolidate_franchise_variants_internal(uuid) from public;

create or replace function public.admin_consolidate_franchise_variants(p_franchise_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
  v_user uuid := (select auth.uid());
begin
  if not public.is_admin() then
    raise exception 'Accesso amministratore richiesto' using errcode = '42501';
  end if;

  v_result := public.consolidate_franchise_variants_internal(p_franchise_id);

  if coalesce((v_result ->> 'merged')::integer, 0) > 0 then
    insert into public.admin_audit_log(actor_id, action, target_type, target_id, metadata)
    values (
      v_user,
      'franchise_variants_consolidated',
      'franchise',
      p_franchise_id::text,
      v_result
    );
  end if;

  return v_result || jsonb_build_object('franchise', public.admin_get_franchise(p_franchise_id));
end;
$$;

revoke all on function public.admin_consolidate_franchise_variants(uuid) from public;
grant execute on function public.admin_consolidate_franchise_variants(uuid) to authenticated;

create or replace function public.admin_save_franchise_games_batch(
  p_franchise_id uuid,
  p_games jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_item jsonb;
  v_key text;
  v_relation_type text;
  v_release_order integer;
  v_narrative_order integer;
  v_note text;
  v_count integer := 0;
begin
  if not public.is_admin() then
    raise exception 'Accesso amministratore richiesto' using errcode = '42501';
  end if;

  if not exists (select 1 from public.franchises where id = p_franchise_id) then
    raise exception 'Franchise non trovato';
  end if;

  if p_games is null or jsonb_typeof(p_games) <> 'array' or jsonb_array_length(p_games) = 0 then
    raise exception 'Seleziona almeno un gioco';
  end if;

  if jsonb_array_length(p_games) > 100 then
    raise exception 'Puoi aggiungere al massimo 100 giochi per volta';
  end if;

  for v_item in select value from jsonb_array_elements(p_games)
  loop
    v_key := trim(coalesce(v_item ->> 'game_key', ''));
    v_relation_type := coalesce(nullif(trim(v_item ->> 'relation_type'), ''), 'main');
    v_release_order := nullif(v_item ->> 'release_order', '')::integer;
    v_narrative_order := nullif(v_item ->> 'narrative_order', '')::integer;
    v_note := nullif(trim(v_item ->> 'note'), '');

    if v_relation_type not in ('main', 'spin_off', 'remake', 'remaster', 'dlc', 'expansion', 'other') then
      raise exception 'Tipo relazione non valido per %', v_key;
    end if;
    if coalesce(v_release_order, 0) <= 0 then
      raise exception 'Ordine di uscita non valido per %', v_key;
    end if;
    if v_narrative_order is not null and v_narrative_order <= 0 then
      raise exception 'Ordine narrativo non valido per %', v_key;
    end if;
    if not exists (select 1 from public.catalog_games where match_key = v_key) then
      raise exception 'Gioco non trovato nel catalogo: %', v_key;
    end if;

    insert into public.franchise_games(
      franchise_id,
      game_key,
      relation_type,
      release_order,
      narrative_order,
      note
    ) values (
      p_franchise_id,
      v_key,
      v_relation_type,
      v_release_order,
      v_narrative_order,
      v_note
    )
    on conflict (franchise_id, game_key) do update set
      relation_type = excluded.relation_type,
      release_order = excluded.release_order,
      narrative_order = excluded.narrative_order,
      note = excluded.note,
      updated_at = now();

    v_count := v_count + 1;
  end loop;

  perform public.consolidate_franchise_variants_internal(p_franchise_id);

  insert into public.admin_audit_log(actor_id, action, target_type, target_id, metadata)
  values (
    v_user,
    'franchise_games_batch_saved',
    'franchise',
    p_franchise_id::text,
    jsonb_build_object('count', v_count, 'deduplication', 'title_and_cover')
  );

  return public.admin_get_franchise(p_franchise_id);
end;
$$;

revoke all on function public.admin_save_franchise_games_batch(uuid, jsonb) from public;
grant execute on function public.admin_save_franchise_games_batch(uuid, jsonb) to authenticated;


create or replace function public.admin_save_franchise_game(
  p_franchise_id uuid,
  p_game_key text,
  p_relation_type text,
  p_release_order integer,
  p_narrative_order integer,
  p_note text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_key text := trim(coalesce(p_game_key, ''));
begin
  if not public.is_admin() then
    raise exception 'Accesso amministratore richiesto' using errcode = '42501';
  end if;
  if p_relation_type not in ('main', 'spin_off', 'remake', 'remaster', 'dlc', 'expansion', 'other') then
    raise exception 'Tipo relazione non valido';
  end if;
  if coalesce(p_release_order, 0) <= 0 then raise exception 'Ordine di uscita non valido'; end if;
  if p_narrative_order is not null and p_narrative_order <= 0 then raise exception 'Ordine narrativo non valido'; end if;
  if not exists (select 1 from public.franchises where id = p_franchise_id) then raise exception 'Franchise non trovato'; end if;
  if not exists (select 1 from public.catalog_games where match_key = v_key) then raise exception 'Gioco non trovato nel catalogo'; end if;

  insert into public.franchise_games(franchise_id, game_key, relation_type, release_order, narrative_order, note)
  values (p_franchise_id, v_key, p_relation_type, p_release_order, p_narrative_order, nullif(trim(p_note), ''))
  on conflict (franchise_id, game_key) do update set
    relation_type = excluded.relation_type,
    release_order = excluded.release_order,
    narrative_order = excluded.narrative_order,
    note = excluded.note,
    updated_at = now();

  perform public.consolidate_franchise_variants_internal(p_franchise_id);

  insert into public.admin_audit_log(actor_id, action, target_type, target_id, metadata)
  values (
    v_user,
    'franchise_game_saved',
    'franchise',
    p_franchise_id::text,
    jsonb_build_object('game_key', v_key, 'deduplication', 'title_and_cover')
  );
  return public.admin_get_franchise(p_franchise_id);
end;
$$;

revoke all on function public.admin_save_franchise_game(uuid, text, text, integer, integer, text) from public;
grant execute on function public.admin_save_franchise_game(uuid, text, text, integer, integer, text) to authenticated;

-- Consolidamento una tantum delle saghe già presenti.
do $$
declare
  v_franchise record;
begin
  for v_franchise in select id from public.franchises loop
    perform public.consolidate_franchise_variants_internal(v_franchise.id);
  end loop;
end;
$$;

comment on function public.catalog_editorial_identity(text, text) is
'Identità editoriale prudente: stesso titolo normalizzato e stessa copertina normalizzata.';
comment on function public.admin_search_franchise_candidates(text, integer) is
'Ricerca amministrativa raggruppata per opera editoriale, con varianti espandibili.';
comment on function public.admin_consolidate_franchise_variants(uuid) is
'Unisce nel franchise i record con stesso titolo e stessa copertina, preservando percorsi e relazioni.';

commit;

notify pgrst, 'reload schema';
