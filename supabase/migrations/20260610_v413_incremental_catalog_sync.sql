-- The Free Vault v4.1.3 — sincronizzazione incrementale a basso consumo.
-- Eseguire dopo 20260610_v412_catalog_read_model.sql.
--
-- catalog_games diventa la fonte catalogo persistente. I workflow non riempiono
-- più catalog_items e non ricostruiscono l'intero read model a ogni esecuzione.
-- Le righe già identiche vengono confrontate come JSONB e non riscritte.

-- Due indici non più necessari occupavano molto spazio sul piano Free.
drop index if exists public.catalog_games_search_text_trgm_idx;
drop index if exists public.catalog_games_index_run_idx;

comment on table public.catalog_items is
'Legacy staging table. Kept empty for rollback compatibility; v4.1.3 writes directly to catalog_games.';

create or replace function public.catalog_storage_status(
  p_max_bytes bigint default 492830720 -- 470 MiB
)
returns jsonb
language sql
stable
security definer
set search_path = ''
set statement_timeout = '10s'
as $$
  select jsonb_build_object(
    'database_bytes', pg_database_size(current_database()),
    'catalog_bytes', pg_total_relation_size('public.catalog_games'::regclass),
    'max_bytes', p_max_bytes,
    'allowed', pg_database_size(current_database()) < p_max_bytes,
    'checked_at', now()
  );
$$;

revoke all on function public.catalog_storage_status(bigint) from public;
grant execute on function public.catalog_storage_status(bigint) to service_role;

create or replace function public.upsert_catalog_games_incremental(
  p_store text,
  p_run_id uuid,
  p_rows jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
set statement_timeout = '120s'
as $$
declare
  v_row jsonb;
  v_listing jsonb;
  v_existing public.catalog_games%rowtype;
  v_existing_listing jsonb;
  v_merged_listings jsonb;
  v_stores text[];
  v_platforms text[];
  v_genres text[];
  v_categories text[];
  v_sort_price bigint;
  v_exists boolean;
  v_prefer_incoming boolean;
  v_changed boolean;
  v_processed integer := 0;
  v_inserted integer := 0;
  v_updated integer := 0;
  v_unchanged integer := 0;
begin
  if p_store not in ('epic', 'steam', 'playstation', 'xbox', 'nintendo', 'other') then
    raise exception 'Store non valido: %', p_store;
  end if;
  if jsonb_typeof(p_rows) <> 'array' then
    raise exception 'p_rows deve essere un array JSON';
  end if;

  for v_row in select value from jsonb_array_elements(p_rows)
  loop
    v_processed := v_processed + 1;
    v_listing := coalesce(v_row -> 'listing', '{}'::jsonb);
    v_platforms := array(
      select jsonb_array_elements_text(coalesce(v_row -> 'platforms', '[]'::jsonb))
    );
    v_genres := array(
      select jsonb_array_elements_text(coalesce(v_row -> 'genres', '[]'::jsonb))
    );
    v_categories := array(
      select jsonb_array_elements_text(coalesce(v_row -> 'categories', '[]'::jsonb))
    );

    select * into v_existing
    from public.catalog_games
    where match_key = v_row ->> 'match_key';
    v_exists := found;

    if not v_exists then
      insert into public.catalog_games (
        match_key, canonical_id, title, canonical_title, description,
        developer, publisher, image_url, store_url, release_date,
        release_year, market_segment, category_group, offer_type,
        platforms, genres, categories, stores, store_listings,
        sort_price, index_run_id, updated_at
      ) values (
        v_row ->> 'match_key',
        v_row ->> 'canonical_id',
        v_row ->> 'title',
        v_row ->> 'canonical_title',
        nullif(v_row ->> 'description', ''),
        nullif(v_row ->> 'developer', ''),
        nullif(v_row ->> 'publisher', ''),
        nullif(v_row ->> 'image_url', ''),
        nullif(v_row ->> 'store_url', ''),
        nullif(v_row ->> 'release_date', '')::date,
        nullif(v_row ->> 'release_year', '')::integer,
        coalesce(nullif(v_row ->> 'market_segment', ''), 'unclassified'),
        coalesce(nullif(v_row ->> 'category_group', ''), 'other'),
        nullif(v_row ->> 'offer_type', ''),
        coalesce(v_platforms, '{}'::text[]),
        coalesce(v_genres, '{}'::text[]),
        coalesce(v_categories, '{}'::text[]),
        array[p_store],
        jsonb_build_array(v_listing),
        greatest(
          coalesce(nullif(v_listing ->> 'discount_price', '')::bigint, 0),
          coalesce(nullif(v_listing ->> 'original_price', '')::bigint, 0)
        ),
        p_run_id,
        now()
      );
      v_inserted := v_inserted + 1;
      continue;
    end if;

    select item into v_existing_listing
    from jsonb_array_elements(v_existing.store_listings) item
    where item ->> 'listing_id' = v_listing ->> 'listing_id'
    limit 1;

    -- Epic remains the preferred metadata source. Steam can populate metadata
    -- only for games that do not have an Epic listing.
    v_prefer_incoming := p_store = 'epic' or not ('epic' = any(v_existing.stores));
    v_changed := v_existing_listing is distinct from v_listing;

    if v_prefer_incoming then
      v_changed := v_changed
        or v_existing.title is distinct from (v_row ->> 'title')
        or v_existing.canonical_title is distinct from (v_row ->> 'canonical_title')
        or v_existing.description is distinct from nullif(v_row ->> 'description', '')
        or v_existing.developer is distinct from nullif(v_row ->> 'developer', '')
        or v_existing.publisher is distinct from nullif(v_row ->> 'publisher', '')
        or v_existing.image_url is distinct from nullif(v_row ->> 'image_url', '')
        or v_existing.store_url is distinct from nullif(v_row ->> 'store_url', '')
        or v_existing.release_date is distinct from nullif(v_row ->> 'release_date', '')::date
        or v_existing.release_year is distinct from nullif(v_row ->> 'release_year', '')::integer
        or v_existing.market_segment is distinct from coalesce(nullif(v_row ->> 'market_segment', ''), 'unclassified')
        or v_existing.category_group is distinct from coalesce(nullif(v_row ->> 'category_group', ''), 'other')
        or v_existing.offer_type is distinct from nullif(v_row ->> 'offer_type', '')
        or v_existing.platforms is distinct from coalesce(v_platforms, '{}'::text[])
        or v_existing.genres is distinct from coalesce(v_genres, '{}'::text[])
        or v_existing.categories is distinct from coalesce(v_categories, '{}'::text[]);
    end if;

    if not v_changed then
      v_unchanged := v_unchanged + 1;
      continue;
    end if;

    select coalesce(jsonb_agg(x.item order by x.item ->> 'store', x.item ->> 'listing_id'), '[]'::jsonb)
    into v_merged_listings
    from (
      select item
      from jsonb_array_elements(v_existing.store_listings) item
      where item ->> 'listing_id' <> v_listing ->> 'listing_id'
      union all
      select v_listing as item
    ) x;

    select coalesce(array_agg(distinct value order by value), '{}'::text[])
    into v_stores
    from unnest(v_existing.stores || array[p_store]) value;

    select coalesce(max(greatest(
      coalesce(nullif(item ->> 'discount_price', '')::bigint, 0),
      coalesce(nullif(item ->> 'original_price', '')::bigint, 0)
    )), 0)
    into v_sort_price
    from jsonb_array_elements(v_merged_listings) item;

    update public.catalog_games
    set
      title = case when v_prefer_incoming then v_row ->> 'title' else title end,
      canonical_title = case when v_prefer_incoming then v_row ->> 'canonical_title' else canonical_title end,
      description = case when v_prefer_incoming then nullif(v_row ->> 'description', '') else description end,
      developer = case when v_prefer_incoming then nullif(v_row ->> 'developer', '') else developer end,
      publisher = case when v_prefer_incoming then nullif(v_row ->> 'publisher', '') else publisher end,
      image_url = case when v_prefer_incoming then nullif(v_row ->> 'image_url', '') else image_url end,
      store_url = case when v_prefer_incoming then nullif(v_row ->> 'store_url', '') else store_url end,
      release_date = case when v_prefer_incoming then nullif(v_row ->> 'release_date', '')::date else release_date end,
      release_year = case when v_prefer_incoming then nullif(v_row ->> 'release_year', '')::integer else release_year end,
      market_segment = case when v_prefer_incoming then coalesce(nullif(v_row ->> 'market_segment', ''), 'unclassified') else market_segment end,
      category_group = case when v_prefer_incoming then coalesce(nullif(v_row ->> 'category_group', ''), 'other') else category_group end,
      offer_type = case when v_prefer_incoming then nullif(v_row ->> 'offer_type', '') else offer_type end,
      platforms = case when v_prefer_incoming then coalesce(v_platforms, '{}'::text[]) else platforms end,
      genres = case when v_prefer_incoming then coalesce(v_genres, '{}'::text[]) else genres end,
      categories = case when v_prefer_incoming then coalesce(v_categories, '{}'::text[]) else categories end,
      stores = v_stores,
      store_listings = v_merged_listings,
      sort_price = v_sort_price,
      index_run_id = p_run_id,
      updated_at = now()
    where match_key = v_existing.match_key;

    v_updated := v_updated + 1;
  end loop;

  return jsonb_build_object(
    'processed', v_processed,
    'inserted_games', v_inserted,
    'updated_games', v_updated,
    'unchanged_games', v_unchanged
  );
end;
$$;

revoke all on function public.upsert_catalog_games_incremental(text, uuid, jsonb) from public;
grant execute on function public.upsert_catalog_games_incremental(text, uuid, jsonb) to service_role;

create or replace function public.finalize_incremental_catalog_sync(
  p_store text,
  p_run_id uuid,
  p_listing_count bigint,
  p_canonical_count bigint,
  p_inserted_games bigint,
  p_updated_games bigint,
  p_unchanged_games bigint,
  p_years jsonb default '[]'::jsonb,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
set statement_timeout = '30s'
as $$
declare
  v_stores jsonb := '{}'::jsonb;
  v_years jsonb := '[]'::jsonb;
  v_total_listings bigint := 0;
  v_total_games bigint := 0;
begin
  insert into public.catalog_sync_state (
    store, run_id, status, listing_count, canonical_count,
    started_at, completed_at, error_message, metadata, updated_at
  ) values (
    p_store, p_run_id, 'completed', p_listing_count, p_canonical_count,
    now(), now(), null,
    coalesce(p_metadata, '{}'::jsonb) || jsonb_build_object(
      'inserted_games', p_inserted_games,
      'updated_games', p_updated_games,
      'unchanged_games', p_unchanged_games,
      'incremental', true
    ),
    now()
  )
  on conflict (store) do update set
    run_id = excluded.run_id,
    status = 'completed',
    listing_count = excluded.listing_count,
    canonical_count = excluded.canonical_count,
    completed_at = now(),
    error_message = null,
    metadata = excluded.metadata,
    updated_at = now();

  select coalesce(stores, '{}'::jsonb), coalesce(years, '[]'::jsonb), total_games
  into v_stores, v_years, v_total_games
  from public.catalog_stats_cache
  where singleton;

  if not found or v_total_games = 0 then
    select count(*) into v_total_games from public.catalog_games;
  else
    v_total_games := v_total_games + greatest(coalesce(p_inserted_games, 0), 0);
  end if;

  v_stores := jsonb_set(
    coalesce(v_stores, '{}'::jsonb),
    array[p_store],
    to_jsonb(coalesce(p_listing_count, 0)),
    true
  );

  select coalesce(sum((value #>> '{}')::bigint), 0)
  into v_total_listings
  from jsonb_each(v_stores);

  select coalesce(jsonb_agg(year_value order by year_value desc), '[]'::jsonb)
  into v_years
  from (
    select distinct value::integer as year_value
    from jsonb_array_elements_text(
      coalesce(v_years, '[]'::jsonb) || coalesce(p_years, '[]'::jsonb)
    )
    where value ~ '^[0-9]{4}$'
  ) years_union;

  insert into public.catalog_stats_cache (
    singleton, run_id, status, total_listings, total_games,
    stores, years, completed_at, error_message, updated_at
  ) values (
    true, p_run_id, 'completed', v_total_listings, v_total_games,
    v_stores, v_years, now(), null, now()
  )
  on conflict (singleton) do update set
    run_id = excluded.run_id,
    status = 'completed',
    total_listings = excluded.total_listings,
    total_games = excluded.total_games,
    stores = excluded.stores,
    years = excluded.years,
    completed_at = now(),
    error_message = null,
    updated_at = now();

  return jsonb_build_object(
    'store', p_store,
    'listing_count', p_listing_count,
    'canonical_count', p_canonical_count,
    'inserted_games', p_inserted_games,
    'updated_games', p_updated_games,
    'unchanged_games', p_unchanged_games,
    'total_listings', v_total_listings,
    'total_games', v_total_games,
    'completed_at', now()
  );
end;
$$;

revoke all on function public.finalize_incremental_catalog_sync(text, uuid, bigint, bigint, bigint, bigint, bigint, jsonb, jsonb) from public;
grant execute on function public.finalize_incremental_catalog_sync(text, uuid, bigint, bigint, bigint, bigint, bigint, jsonb, jsonb) to service_role;

-- Re-seed the cache once from the existing canonical table. This scans about
-- 170k compact rows, not the discarded staging table or JSON aggregations.
insert into public.catalog_stats_cache (
  singleton, status, total_listings, total_games, stores, years,
  completed_at, error_message, updated_at
)
select
  true,
  'completed',
  coalesce((select sum(listing_count) from public.catalog_sync_state where status = 'completed'), 0),
  count(*),
  coalesce((
    select jsonb_object_agg(store, listing_count)
    from public.catalog_sync_state
    where status = 'completed'
  ), '{}'::jsonb),
  coalesce(jsonb_agg(distinct release_year order by release_year desc)
    filter (where release_year is not null), '[]'::jsonb),
  now(),
  null,
  now()
from public.catalog_games
on conflict (singleton) do update set
  status = 'completed',
  total_listings = excluded.total_listings,
  total_games = excluded.total_games,
  stores = excluded.stores,
  years = excluded.years,
  completed_at = now(),
  error_message = null,
  updated_at = now();

-- Search no longer depends on the large search_text trigram index. Developer
-- and publisher remain searchable through search_document.
create or replace function public.search_catalog(
  p_query text default '',
  p_stores text[] default null,
  p_category text default null,
  p_segment text default null,
  p_price text default null,
  p_year integer default null,
  p_library_keys text[] default null,
  p_favorite_keys text[] default null,
  p_personal_filter text default null,
  p_sort text default 'relevance',
  p_limit integer default 36,
  p_offset integer default 0
)
returns jsonb
language sql
stable
security definer
set search_path = ''
set statement_timeout = '20s'
as $$
with params as (
  select
    lower(trim(coalesce(p_query, ''))) as q,
    greatest(1, least(coalesce(p_limit, 36), 100)) as page_limit,
    greatest(0, coalesce(p_offset, 0)) as page_offset
),
filtered as materialized (
  select
    cg.*,
    case
      when p.q = '' then 0::real
      when lower(cg.title) = p.q then 100::real
      when lower(cg.canonical_title) = p.q then 95::real
      when lower(cg.title) like p.q || '%' then 70::real
      when lower(cg.canonical_title) like p.q || '%' then 65::real
      else (
        ts_rank_cd(cg.search_document, websearch_to_tsquery('simple', p.q)) * 20
        + extensions.similarity(lower(cg.title), p.q) * 10
      )::real
    end as relevance_score
  from public.catalog_games cg
  cross join params p
  where
    (p_stores is null or cardinality(p_stores) = 0 or cg.stores && p_stores)
    and (p_category is null or p_category = '' or p_category = 'all' or cg.category_group = p_category)
    and (p_segment is null or p_segment = '' or p_segment = 'all' or cg.market_segment = p_segment)
    and (p_year is null or cg.release_year = p_year)
    and (
      p_price is null or p_price = '' or p_price = 'all'
      or (p_price = 'free' and exists (
        select 1 from jsonb_array_elements(cg.store_listings) listing
        where coalesce((listing ->> 'discount_price')::bigint, (listing ->> 'original_price')::bigint, 1) = 0
      ))
      or (p_price = 'discounted' and exists (
        select 1 from jsonb_array_elements(cg.store_listings) listing
        where (listing ->> 'original_price') is not null
          and (listing ->> 'discount_price') is not null
          and (listing ->> 'discount_price')::bigint < (listing ->> 'original_price')::bigint
      ))
      or (p_price = 'paid' and cg.sort_price > 0)
    )
    and (
      p_personal_filter is null or p_personal_filter = '' or p_personal_filter = 'all'
      or (p_personal_filter = 'saved' and (
        cg.match_key = any(coalesce(p_library_keys, '{}'::text[]))
        or cg.canonical_id = any(coalesce(p_library_keys, '{}'::text[]))
      ))
      or (p_personal_filter = 'favorite' and (
        cg.match_key = any(coalesce(p_favorite_keys, '{}'::text[]))
        or cg.canonical_id = any(coalesce(p_favorite_keys, '{}'::text[]))
      ))
    )
    and (
      p.q = ''
      or lower(cg.title) like '%' || p.q || '%'
      or cg.search_document @@ websearch_to_tsquery('simple', p.q)
      or extensions.similarity(lower(cg.title), p.q) >= 0.22
    )
),
counted as (
  select case
    when (
      (select q from params) = ''
      and (p_stores is null or cardinality(p_stores) = 0)
      and (p_category is null or p_category in ('', 'all'))
      and (p_segment is null or p_segment in ('', 'all'))
      and (p_price is null or p_price in ('', 'all'))
      and p_year is null
      and (p_personal_filter is null or p_personal_filter in ('', 'all'))
    ) then coalesce((select total_games from public.catalog_stats_cache where singleton), 0)
    else (select count(*) from filtered)
  end as total_count
),
paged as (
  select f.*
  from filtered f
  cross join params p
  order by
    case when p_sort = 'title' or (p_sort = 'relevance' and p.q = '') then lower(f.title) end asc nulls last,
    case when p_sort = 'date' then f.release_date end desc nulls last,
    case when p_sort = 'value' then f.sort_price end desc nulls last,
    case when p_sort = 'relevance' and p.q <> '' then f.relevance_score end desc nulls last,
    lower(f.title) asc,
    f.match_key asc
  limit (select page_limit from params)
  offset (select page_offset from params)
)
select jsonb_build_object(
  'items', coalesce(jsonb_agg(
    jsonb_build_object(
      'canonical_id', canonical_id,
      'match_key', match_key,
      'internal_id', canonical_id,
      'listing_id', (store_listings -> 0 ->> 'listing_id'),
      'source_kind', 'catalog',
      'store', (store_listings -> 0 ->> 'store'),
      'stores', to_jsonb(stores),
      'store_listings', store_listings,
      'title', title,
      'canonical_title', canonical_title,
      'description', description,
      'developer', developer,
      'publisher', publisher,
      'image_url', image_url,
      'store_url', store_url,
      'release_date', release_date,
      'release_year', release_year,
      'market_segment', market_segment,
      'category_group', category_group,
      'offer_type', offer_type,
      'platforms', to_jsonb(platforms),
      'genres', to_jsonb(genres),
      'categories', to_jsonb(categories),
      'original_price', (store_listings -> 0 -> 'original_price'),
      'discount_price', (store_listings -> 0 -> 'discount_price'),
      'currency_code', (store_listings -> 0 ->> 'currency_code'),
      'fmt_original_price', (store_listings -> 0 ->> 'fmt_original_price'),
      'fmt_discount_price', (store_listings -> 0 ->> 'fmt_discount_price')
    ) order by
      case when p_sort = 'title' or (p_sort = 'relevance' and (select q from params) = '') then lower(title) end asc nulls last,
      case when p_sort = 'date' then release_date end desc nulls last,
      case when p_sort = 'value' then sort_price end desc nulls last,
      case when p_sort = 'relevance' and (select q from params) <> '' then relevance_score end desc nulls last,
      lower(title) asc,
      match_key asc
  ), '[]'::jsonb),
  'total', (select total_count from counted),
  'limit', (select page_limit from params),
  'offset', (select page_offset from params)
)
from paged;
$$;

revoke all on function public.search_catalog(text, text[], text, text, text, integer, text[], text[], text, text, integer, integer) from public;
grant execute on function public.search_catalog(text, text[], text, text, text, integer, text[], text[], text, text, integer, integer) to anon, authenticated;
