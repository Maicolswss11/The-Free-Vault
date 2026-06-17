-- Ludograph v5.5.8 — Screenshot e video nelle schede gioco.
-- I media restano nel metadata Master IGDB e vengono esposti dal read model
-- senza duplicare file o introdurre una seconda copia del catalogo.

begin;

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
), media as (
  select
    case when jsonb_typeof(metadata -> 'screenshots') = 'array'
      then metadata -> 'screenshots' else '[]'::jsonb end as screenshots,
    case when jsonb_typeof(metadata -> 'artworks') = 'array'
      then metadata -> 'artworks' else '[]'::jsonb end as artworks,
    case when jsonb_typeof(metadata -> 'videos') = 'array'
      then metadata -> 'videos' else '[]'::jsonb end as videos
  from master
), normalized_media as (
  select
    coalesce((select screenshots from media), '[]'::jsonb) as screenshots,
    coalesce((select artworks from media), '[]'::jsonb) as artworks,
    coalesce((select videos from media), '[]'::jsonb) as videos
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
    normalized_media.artworks -> 0 ->> 'url',
    normalized_media.screenshots -> 0 ->> 'url'
  ),
  'screenshots', normalized_media.screenshots,
  'artworks', normalized_media.artworks,
  'videos', normalized_media.videos,
  'media_count', jsonb_array_length(normalized_media.screenshots)
    + jsonb_array_length(normalized_media.artworks)
    + jsonb_array_length(normalized_media.videos),
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
from normalized_media;
$$;

revoke all on function public.catalog_game_card_json(public.catalog_games) from public;

comment on function public.catalog_game_card_json(public.catalog_games) is
'Read model pubblico del gioco, inclusi screenshot, artwork e video importati da IGDB.';

commit;

notify pgrst, 'reload schema';
