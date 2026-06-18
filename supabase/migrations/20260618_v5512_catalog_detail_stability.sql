-- Ludograph v5.5.12 — stabilità schede gioco e RPC catalogo.
--
-- get_catalog_game non deve più usare una singola query con OR più
-- jsonb_array_elements(store_listings), perché su cataloghi grandi può
-- degenerare in una scansione ampia e andare in statement timeout.
-- La risoluzione ora procede per passi indicizzati e usa un indice GIN per
-- l'eventuale lookup sui listing_id degli store.

begin;

create index if not exists catalog_games_store_listings_gin_idx
on public.catalog_games using gin (store_listings jsonb_path_ops);

create index if not exists catalog_games_canonical_id_idx
on public.catalog_games(canonical_id);

create index if not exists catalog_games_master_game_id_idx
on public.catalog_games(master_game_id);

create or replace function public.catalog_game_card_json(p_game public.catalog_games)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
with master as (
  select coalesce(g.metadata, '{}'::jsonb) as metadata
  from public.games g
  where g.id = (p_game).master_game_id
  limit 1
), raw_media as (
  select
    case when jsonb_typeof(metadata -> 'screenshots') = 'array'
      then metadata -> 'screenshots' else '[]'::jsonb end as raw_screenshots,
    case when jsonb_typeof(metadata -> 'artworks') = 'array'
      then metadata -> 'artworks' else '[]'::jsonb end as raw_artworks,
    case when jsonb_typeof(metadata -> 'videos') = 'array'
      then metadata -> 'videos' else '[]'::jsonb end as raw_videos
  from master
), normalized_media as (
  select
    coalesce((
      select jsonb_agg(value order by ord)
      from jsonb_array_elements(coalesce(raw_screenshots, '[]'::jsonb)) with ordinality as item(value, ord)
      where ord <= 24
    ), '[]'::jsonb) as screenshots,
    coalesce((
      select jsonb_agg(value order by ord)
      from jsonb_array_elements(coalesce(raw_artworks, '[]'::jsonb)) with ordinality as item(value, ord)
      where ord <= 12
    ), '[]'::jsonb) as artworks,
    coalesce((
      select jsonb_agg(value order by ord)
      from jsonb_array_elements(coalesce(raw_videos, '[]'::jsonb)) with ordinality as item(value, ord)
      where ord <= 8
    ), '[]'::jsonb) as videos,
    jsonb_array_length(coalesce(raw_screenshots, '[]'::jsonb))
      + jsonb_array_length(coalesce(raw_artworks, '[]'::jsonb))
      + jsonb_array_length(coalesce(raw_videos, '[]'::jsonb)) as full_media_count
  from raw_media
), media as (
  select
    coalesce((select screenshots from normalized_media), '[]'::jsonb) as screenshots,
    coalesce((select artworks from normalized_media), '[]'::jsonb) as artworks,
    coalesce((select videos from normalized_media), '[]'::jsonb) as videos,
    coalesce((select full_media_count from normalized_media), 0) as full_media_count
)
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
  'hero_image_url', coalesce(
    media.artworks -> 0 ->> 'url',
    media.screenshots -> 0 ->> 'url'
  ),
  'screenshots', media.screenshots,
  'artworks', media.artworks,
  'videos', media.videos,
  'media_count', media.full_media_count,
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
  'fmt_discount_price', ((p_game).store_listings -> 0 ->> 'fmt_discount_price')
)
from media;
$$;

revoke all on function public.catalog_game_card_json(public.catalog_games) from public;

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
  v_master_game_id text;
  v_game public.catalog_games%rowtype;
begin
  if v_key is null then
    return null;
  end if;

  select * into v_game
  from public.catalog_games cg
  where cg.match_key = v_key
  order by case cg.source_kind when 'hybrid' then 0 when 'master' then 1 else 2 end
  limit 1;
  if found then
    return public.catalog_game_card_json(v_game);
  end if;

  select * into v_game
  from public.catalog_games cg
  where cg.canonical_id = v_key
  order by case cg.source_kind when 'hybrid' then 0 when 'master' then 1 else 2 end, cg.match_key
  limit 1;
  if found then
    return public.catalog_game_card_json(v_game);
  end if;

  v_master_game_id := public.resolve_master_game_id(v_key);
  if v_master_game_id is not null then
    select * into v_game
    from public.catalog_games cg
    where cg.master_game_id = v_master_game_id
    order by case cg.source_kind when 'hybrid' then 0 when 'master' then 1 else 2 end, cg.match_key
    limit 1;
    if found then
      return public.catalog_game_card_json(v_game);
    end if;
  end if;

  select * into v_game
  from public.catalog_games cg
  where cg.store_listings @> jsonb_build_array(jsonb_build_object('listing_id', v_key))
  order by case cg.source_kind when 'hybrid' then 0 when 'master' then 1 else 2 end, cg.match_key
  limit 1;
  if found then
    return public.catalog_game_card_json(v_game);
  end if;

  return null;
end;
$$;

create or replace function public.get_catalog_games(p_keys text[])
returns jsonb
language sql
stable
security definer
set search_path = ''
set statement_timeout = '10s'
as $$
with requested as (
  select min(ord) as ord, key as requested_key
  from unnest(coalesce(p_keys, '{}'::text[])) with ordinality as keys(key, ord)
  where nullif(trim(key), '') is not null
  group by key
), resolved as (
  select r.ord, public.get_catalog_game(r.requested_key) as item
  from requested r
)
select coalesce(jsonb_agg(item order by ord) filter (where item is not null), '[]'::jsonb)
from resolved;
$$;

revoke all on function public.get_catalog_game(text) from public;
revoke all on function public.get_catalog_games(text[]) from public;
grant execute on function public.get_catalog_game(text) to anon, authenticated;
grant execute on function public.get_catalog_games(text[]) to anon, authenticated;

comment on function public.get_catalog_game(text) is
'Ludograph v5.5.12: lookup scheda gioco per passi indicizzati; evita OR ampi e jsonb_array_elements su tutto catalog_games.';

commit;

notify pgrst, 'reload schema';
