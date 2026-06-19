-- Ludograph v5.5.14 — qualità della scheda canonica.
--
-- La v5.5.13 faceva convergere i duplicati tecnici verso una sola pagina,
-- ma poteva scegliere la variante store/hybrid sbagliata quando questa aveva
-- più listing commerciali, anche se la scheda enciclopedica aveva media e
-- recensioni. Questa migrazione ricalibra la scelta canonica: vince la scheda
-- con più contenuto reale (recensioni, media, dati utente), e i listing store
-- dei duplicati vengono comunque aggregati nella pagina canonica.

begin;

create or replace function public.catalog_detail_media_count(p_master_game_id text)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    case when jsonb_typeof(coalesce(g.metadata, '{}'::jsonb) -> 'screenshots') = 'array'
      then jsonb_array_length(coalesce(g.metadata, '{}'::jsonb) -> 'screenshots') else 0 end,
    0
  )
  + coalesce(
    case when jsonb_typeof(coalesce(g.metadata, '{}'::jsonb) -> 'artworks') = 'array'
      then jsonb_array_length(coalesce(g.metadata, '{}'::jsonb) -> 'artworks') else 0 end,
    0
  )
  + coalesce(
    case when jsonb_typeof(coalesce(g.metadata, '{}'::jsonb) -> 'videos') = 'array'
      then jsonb_array_length(coalesce(g.metadata, '{}'::jsonb) -> 'videos') else 0 end,
    0
  )
  from public.games g
  where g.id = nullif(p_master_game_id, '')
  limit 1;
$$;

create or replace function public.catalog_review_anchor_count(p_match_key text, p_canonical_id text, p_master_game_id text)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select count(*)::integer
  from public.game_reviews gr
  where gr.game_key in (nullif(p_match_key, ''), nullif(p_canonical_id, ''))
     or (nullif(p_master_game_id, '') is not null and gr.game_id = p_master_game_id);
$$;

create or replace function public.catalog_library_anchor_count(p_match_key text, p_canonical_id text, p_master_game_id text)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select count(*)::integer
  from public.user_library ul
  where ul.game_key in (nullif(p_match_key, ''), nullif(p_canonical_id, ''))
     or (nullif(p_master_game_id, '') is not null and ul.game_id = p_master_game_id);
$$;

create or replace function public.catalog_game_card_json(p_game public.catalog_games)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
with base as (
  select
    public.catalog_normalized_title((p_game).title) as title_key,
    public.catalog_normalized_title(coalesce(nullif((p_game).developer, ''), nullif((p_game).publisher, ''), '')) as maker_key,
    coalesce((p_game).release_year, extract(year from (p_game).release_date)::integer) as release_year,
    public.catalog_cover_identity((p_game).image_url) as cover_key,
    coalesce(g.game_type, 'unknown') as game_type
  from public.catalog_games seed
  left join public.games g on g.id = (p_game).master_game_id
  where seed.match_key = (p_game).match_key
  limit 1
), siblings as materialized (
  select cg.*
  from public.catalog_games cg
  left join public.games g on g.id = cg.master_game_id
  cross join base b
  where b.title_key <> ''
    and public.catalog_normalized_title(cg.title) = b.title_key
    and not public.catalog_is_separate_game_type(coalesce(g.game_type, 'unknown'))
    and (
      b.release_year is null
      or coalesce(cg.release_year, extract(year from cg.release_date)::integer) is null
      or abs(coalesce(cg.release_year, extract(year from cg.release_date)::integer) - b.release_year) <= 2
      or ((p_game).master_game_id is not null and cg.master_game_id = (p_game).master_game_id)
    )
    and (
      b.maker_key = ''
      or public.catalog_normalized_title(coalesce(nullif(cg.developer, ''), nullif(cg.publisher, ''), '')) = ''
      or public.catalog_normalized_title(coalesce(nullif(cg.developer, ''), nullif(cg.publisher, ''), '')) = b.maker_key
      or ((p_game).master_game_id is not null and cg.master_game_id = (p_game).master_game_id)
      or (b.cover_key is not null and public.catalog_cover_identity(cg.image_url) = b.cover_key)
    )
), listing_rows as materialized (
  select distinct on (coalesce(item.value ->> 'listing_id', item.value ->> 'store_url', item.value ->> 'store'), item.value ->> 'store')
    item.value as listing
  from siblings s
  cross join lateral jsonb_array_elements(coalesce(s.store_listings, '[]'::jsonb)) as item(value)
  where jsonb_typeof(item.value) = 'object'
  order by coalesce(item.value ->> 'listing_id', item.value ->> 'store_url', item.value ->> 'store'), item.value ->> 'store',
    case item.value ->> 'store'
      when 'epic' then 0
      when 'steam' then 1
      when 'gog' then 2
      else 9
    end
), merged_listings as (
  select coalesce(jsonb_agg(listing order by
    case listing ->> 'store'
      when 'epic' then 0
      when 'steam' then 1
      when 'gog' then 2
      else 9
    end,
    listing ->> 'store',
    listing ->> 'listing_id'
  ), coalesce((p_game).store_listings, '[]'::jsonb)) as store_listings
  from listing_rows
), merged_stores as (
  select coalesce(array_agg(distinct store_name order by store_name), coalesce((p_game).stores, '{}'::text[])) as stores
  from (
    select unnest(coalesce(s.stores, '{}'::text[])) as store_name from siblings s
    union all
    select listing ->> 'store' from listing_rows where nullif(listing ->> 'store', '') is not null
  ) stores
), aliases as (
  select coalesce(jsonb_agg(distinct alias_value) filter (where alias_value is not null and alias_value <> ''), '[]'::jsonb) as canonical_aliases
  from (
    select s.match_key as alias_value from siblings s
    union all select s.canonical_id from siblings s
    union all select s.master_game_id from siblings s
    union all
    select listing ->> 'listing_id' from listing_rows
  ) a
), master as (
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
), primary_listing as (
  select coalesce((select store_listings from merged_listings) -> 0, '{}'::jsonb) as listing
)
select jsonb_build_object(
  'canonical_id', (p_game).canonical_id,
  'match_key', (p_game).match_key,
  'master_game_id', (p_game).master_game_id,
  'canonical_aliases', (select canonical_aliases from aliases),
  'internal_id', (p_game).canonical_id,
  'listing_id', primary_listing.listing ->> 'listing_id',
  'source_kind', (p_game).source_kind,
  'store', primary_listing.listing ->> 'store',
  'stores', to_jsonb((select stores from merged_stores)),
  'store_listings', (select store_listings from merged_listings),
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
  'store_url', coalesce(primary_listing.listing ->> 'store_url', (p_game).store_url),
  'release_date', (p_game).release_date,
  'release_year', (p_game).release_year,
  'market_segment', (p_game).market_segment,
  'category_group', (p_game).category_group,
  'offer_type', (p_game).offer_type,
  'platforms', to_jsonb((p_game).platforms),
  'genres', to_jsonb((p_game).genres),
  'categories', to_jsonb((p_game).categories),
  'original_price', primary_listing.listing -> 'original_price',
  'discount_price', primary_listing.listing -> 'discount_price',
  'currency_code', primary_listing.listing ->> 'currency_code',
  'fmt_original_price', primary_listing.listing ->> 'fmt_original_price',
  'fmt_discount_price', primary_listing.listing ->> 'fmt_discount_price'
)
from media, primary_listing;
$$;

revoke all on function public.catalog_game_card_json(public.catalog_games) from public;

grant execute on function public.catalog_detail_media_count(text) to anon, authenticated, service_role;
grant execute on function public.catalog_review_anchor_count(text, text, text) to anon, authenticated, service_role;
grant execute on function public.catalog_library_anchor_count(text, text, text) to anon, authenticated, service_role;

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
  order by case cg.source_kind when 'master' then 0 when 'hybrid' then 1 when 'catalog' then 2 else 3 end,
    cg.match_key
  limit 1;

  if not found then
    select * into v_seed
    from public.catalog_games cg
    where cg.canonical_id = v_key
    order by case cg.source_kind when 'master' then 0 when 'hybrid' then 1 when 'catalog' then 2 else 3 end,
      cg.match_key
    limit 1;
  end if;

  if not found then
    v_master_game_id := public.resolve_master_game_id(v_key);
    if v_master_game_id is not null then
      select * into v_seed
      from public.catalog_games cg
      where cg.master_game_id = v_master_game_id
      order by case cg.source_kind when 'master' then 0 when 'hybrid' then 1 when 'catalog' then 2 else 3 end,
        cg.match_key
      limit 1;
    end if;
  end if;

  if not found then
    select * into v_seed
    from public.catalog_games cg
    where cg.store_listings @> jsonb_build_array(jsonb_build_object('listing_id', v_key))
    order by case cg.source_kind when 'master' then 0 when 'hybrid' then 1 when 'catalog' then 2 else 3 end,
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
      cg.canonical_id,
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
      public.catalog_cover_identity(cg.image_url) as cover_key,
      coalesce(public.catalog_detail_media_count(cg.master_game_id), 0) as media_count,
      public.catalog_review_anchor_count(cg.match_key, cg.canonical_id, cg.master_game_id) as review_count,
      public.catalog_library_anchor_count(cg.match_key, cg.canonical_id, cg.master_game_id) as library_count
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
    -- Le interazioni già esistenti sono il segnale più forte: non bisogna
    -- spostare recensioni e libreria su una variante vuota solo perché ha store.
    f.review_count desc,
    f.library_count desc,
    -- Poi vengono i media enciclopedici: screenshot, artwork e trailer.
    f.media_count desc,
    -- Se i contenuti sono equivalenti, preferisci la scheda enciclopedica.
    case f.source_kind when 'master' then 0 when 'hybrid' then 1 when 'catalog' then 2 else 3 end,
    case when nullif(f.description, '') is not null then 0 else 1 end,
    case when nullif(f.image_url, '') is not null then 0 else 1 end,
    greatest(cardinality(coalesce(f.stores, '{}'::text[])), jsonb_array_length(coalesce(f.store_listings, '[]'::jsonb))) desc,
    coalesce(f.release_year, extract(year from f.release_date)::integer) asc nulls last,
    f.match_key
  limit 1;

  return coalesce(v_result, v_seed.match_key);
end;
$$;

revoke all on function public.catalog_canonical_detail_match_key(text) from public;
grant execute on function public.catalog_canonical_detail_match_key(text) to anon, authenticated, service_role;

comment on function public.catalog_canonical_detail_match_key(text) is
'Ludograph v5.5.14: sceglie la scheda canonica più ricca, non la variante store vuota.';

comment on function public.catalog_game_card_json(public.catalog_games) is
'Ludograph v5.5.14: payload scheda gioco con media canonici e listing store aggregati dai duplicati tecnici.';

commit;

notify pgrst, 'reload schema';
