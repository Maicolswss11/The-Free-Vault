-- The Free Vault v4.1.2 — catalog read model/cache.
-- Eseguire dopo 20260610_v411_catalog_finalize_timeout.sql.
--
-- catalog_items resta la tabella di ingestione completa. catalog_games è una
-- proiezione canonica preaggregata usata dalle RPC pubbliche, così il browser
-- non deve raggruppare/scansionare 170k listing a ogni richiesta.

create table if not exists public.catalog_games (
  match_key text primary key,
  canonical_id text not null,
  title text not null,
  canonical_title text not null,
  description text,
  developer text,
  publisher text,
  image_url text,
  store_url text,
  release_date date,
  release_year integer,
  market_segment text not null default 'unclassified',
  category_group text not null default 'other',
  offer_type text,
  platforms text[] not null default '{}',
  genres text[] not null default '{}',
  categories text[] not null default '{}',
  stores text[] not null default '{}',
  store_listings jsonb not null default '[]'::jsonb,
  sort_price bigint not null default 0,
  index_run_id uuid not null,
  updated_at timestamptz not null default now(),
  search_text text generated always as (
    trim(
      coalesce(title, '') || ' ' ||
      coalesce(canonical_title, '') || ' ' ||
      coalesce(developer, '') || ' ' ||
      coalesce(publisher, '')
    )
  ) stored,
  search_document tsvector generated always as (
    setweight(to_tsvector('simple', coalesce(title, '')), 'A') ||
    setweight(to_tsvector('simple', coalesce(canonical_title, '')), 'A') ||
    setweight(to_tsvector('simple', coalesce(developer, '')), 'B') ||
    setweight(to_tsvector('simple', coalesce(publisher, '')), 'B') ||
    setweight(to_tsvector('simple', coalesce(description, '')), 'C')
  ) stored
);

create table if not exists public.catalog_stats_cache (
  singleton boolean primary key default true check (singleton),
  run_id uuid,
  status text not null default 'idle'
    check (status in ('idle', 'running', 'completed', 'failed')),
  total_listings bigint not null default 0,
  total_games bigint not null default 0,
  stores jsonb not null default '{}'::jsonb,
  years jsonb not null default '[]'::jsonb,
  started_at timestamptz,
  completed_at timestamptz,
  error_message text,
  updated_at timestamptz not null default now()
);

create index if not exists catalog_games_canonical_id_idx
on public.catalog_games(canonical_id);

create index if not exists catalog_games_lower_title_idx
on public.catalog_games(lower(title), match_key);

create index if not exists catalog_games_release_date_idx
on public.catalog_games(release_date desc nulls last, match_key);

create index if not exists catalog_games_sort_price_idx
on public.catalog_games(sort_price desc, match_key);

create index if not exists catalog_games_release_year_idx
on public.catalog_games(release_year desc);

create index if not exists catalog_games_category_idx
on public.catalog_games(category_group);

create index if not exists catalog_games_segment_idx
on public.catalog_games(market_segment);

create index if not exists catalog_games_stores_idx
on public.catalog_games using gin(stores);

create index if not exists catalog_games_search_document_idx
on public.catalog_games using gin(search_document);

create index if not exists catalog_games_title_trgm_idx
on public.catalog_games using gin(lower(title) extensions.gin_trgm_ops);

create index if not exists catalog_games_search_text_trgm_idx
on public.catalog_games using gin(lower(search_text) extensions.gin_trgm_ops);

create index if not exists catalog_games_index_run_idx
on public.catalog_games(index_run_id, match_key);

alter table public.catalog_games enable row level security;
alter table public.catalog_stats_cache enable row level security;

revoke all on public.catalog_games from anon, authenticated;
revoke all on public.catalog_stats_cache from anon, authenticated;
grant select, insert, update, delete on public.catalog_games to service_role;
grant select, insert, update, delete on public.catalog_stats_cache to service_role;

create or replace function public.begin_catalog_index_rebuild(p_run_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.catalog_stats_cache (
    singleton, run_id, status, started_at, completed_at,
    error_message, updated_at
  ) values (
    true, p_run_id, 'running', now(), null, null, now()
  )
  on conflict (singleton) do update set
    run_id = excluded.run_id,
    status = 'running',
    started_at = now(),
    completed_at = null,
    error_message = null,
    updated_at = now();
end;
$$;

create or replace function public.rebuild_catalog_index_batch(
  p_run_id uuid,
  p_after_match_key text default null,
  p_limit integer default 1000
)
returns jsonb
language plpgsql
security definer
set search_path = ''
set statement_timeout = '60s'
as $$
declare
  v_limit integer := greatest(100, least(coalesce(p_limit, 1000), 2500));
  v_processed integer := 0;
  v_next_key text;
begin
  select count(*), max(k.match_key)
  into v_processed, v_next_key
  from (
    select distinct ci.match_key
    from public.catalog_items ci
    where ci.available
      and (p_after_match_key is null or ci.match_key > p_after_match_key)
    order by ci.match_key
    limit v_limit
  ) k;

  if v_processed = 0 then
    return jsonb_build_object(
      'processed', 0,
      'next_key', p_after_match_key,
      'done', true
    );
  end if;

  with selected_keys as materialized (
    select distinct ci.match_key
    from public.catalog_items ci
    where ci.available
      and (p_after_match_key is null or ci.match_key > p_after_match_key)
    order by ci.match_key
    limit v_limit
  ),
  ranked as materialized (
    select
      ci.*,
      row_number() over (
        partition by ci.match_key
        order by
          (
            (case when ci.store = 'epic' then 3 else 0 end)
            + (case when nullif(ci.description, '') is not null then 2 else 0 end)
            + (case when ci.image_url is not null then 2 else 0 end)
            + (case when ci.developer is not null then 1 else 0 end)
            + (case when ci.publisher is not null then 1 else 0 end)
            + (case when ci.release_date is not null then 1 else 0 end)
          ) desc,
          ci.store,
          ci.listing_id
      ) as rn
    from public.catalog_items ci
    join selected_keys sk on sk.match_key = ci.match_key
    where ci.available
  ),
  grouped as (
    select
      r.match_key,
      max(r.canonical_id) filter (where r.rn = 1) as canonical_id,
      max(r.title) filter (where r.rn = 1) as title,
      max(r.canonical_title) filter (where r.rn = 1) as canonical_title,
      max(r.description) filter (where r.rn = 1) as description,
      max(r.developer) filter (where r.rn = 1) as developer,
      max(r.publisher) filter (where r.rn = 1) as publisher,
      max(r.image_url) filter (where r.rn = 1) as image_url,
      max(r.store_url) filter (where r.rn = 1) as store_url,
      max(r.release_date) filter (where r.rn = 1) as release_date,
      max(r.release_year) filter (where r.rn = 1) as release_year,
      max(r.market_segment) filter (where r.rn = 1) as market_segment,
      max(r.category_group) filter (where r.rn = 1) as category_group,
      max(r.offer_type) filter (where r.rn = 1) as offer_type,
      (select rr.platforms from ranked rr where rr.match_key = r.match_key and rr.rn = 1 limit 1) as platforms,
      (select rr.genres from ranked rr where rr.match_key = r.match_key and rr.rn = 1 limit 1) as genres,
      (select rr.categories from ranked rr where rr.match_key = r.match_key and rr.rn = 1 limit 1) as categories,
      array_agg(distinct r.store order by r.store) as stores,
      jsonb_agg(
        jsonb_build_object(
          'listing_id', r.listing_id,
          'store', r.store,
          'external_id', r.external_id,
          'namespace', r.namespace,
          'title', r.title,
          'store_url', r.store_url,
          'image_url', r.image_url,
          'offer_type', r.offer_type,
          'category_group', r.category_group,
          'edition_name', r.edition_name,
          'original_price', r.original_price,
          'discount_price', r.discount_price,
          'currency_code', r.currency_code,
          'currency_decimals', r.currency_decimals,
          'fmt_original_price', r.fmt_original_price,
          'fmt_discount_price', r.fmt_discount_price
        ) order by r.store, r.listing_id
      ) as store_listings,
      max(coalesce(r.discount_price, r.original_price, 0)) as sort_price
    from ranked r
    group by r.match_key
  )
  insert into public.catalog_games (
    match_key, canonical_id, title, canonical_title, description,
    developer, publisher, image_url, store_url, release_date,
    release_year, market_segment, category_group, offer_type,
    platforms, genres, categories, stores, store_listings,
    sort_price, index_run_id, updated_at
  )
  select
    g.match_key, g.canonical_id, g.title, g.canonical_title, g.description,
    g.developer, g.publisher, g.image_url, g.store_url, g.release_date,
    g.release_year, coalesce(g.market_segment, 'unclassified'),
    coalesce(g.category_group, 'other'), g.offer_type,
    coalesce(g.platforms, '{}'::text[]), coalesce(g.genres, '{}'::text[]),
    coalesce(g.categories, '{}'::text[]), coalesce(g.stores, '{}'::text[]),
    coalesce(g.store_listings, '[]'::jsonb), coalesce(g.sort_price, 0),
    p_run_id, now()
  from grouped g
  on conflict (match_key) do update set
    canonical_id = excluded.canonical_id,
    title = excluded.title,
    canonical_title = excluded.canonical_title,
    description = excluded.description,
    developer = excluded.developer,
    publisher = excluded.publisher,
    image_url = excluded.image_url,
    store_url = excluded.store_url,
    release_date = excluded.release_date,
    release_year = excluded.release_year,
    market_segment = excluded.market_segment,
    category_group = excluded.category_group,
    offer_type = excluded.offer_type,
    platforms = excluded.platforms,
    genres = excluded.genres,
    categories = excluded.categories,
    stores = excluded.stores,
    store_listings = excluded.store_listings,
    sort_price = excluded.sort_price,
    index_run_id = excluded.index_run_id,
    updated_at = now();

  return jsonb_build_object(
    'processed', v_processed,
    'next_key', v_next_key,
    'done', v_processed < v_limit
  );
end;
$$;

create or replace function public.finalize_catalog_index_rebuild(p_run_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
set statement_timeout = '120s'
as $$
declare
  v_total_games bigint := 0;
  v_total_listings bigint := 0;
  v_stores jsonb := '{}'::jsonb;
  v_years jsonb := '[]'::jsonb;
begin
  delete from public.catalog_games where index_run_id <> p_run_id;

  select count(*) into v_total_games
  from public.catalog_games
  where index_run_id = p_run_id;

  select
    coalesce(sum(css.listing_count), 0),
    coalesce(jsonb_object_agg(css.store, css.listing_count), '{}'::jsonb)
  into v_total_listings, v_stores
  from public.catalog_sync_state css
  where css.status = 'completed';

  select coalesce(jsonb_agg(y.release_year order by y.release_year desc), '[]'::jsonb)
  into v_years
  from (
    select distinct cg.release_year
    from public.catalog_games cg
    where cg.release_year is not null
  ) y;

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
    'total_listings', v_total_listings,
    'total_games', v_total_games,
    'stores', v_stores,
    'completed_at', now()
  );
end;
$$;

create or replace function public.fail_catalog_index_rebuild(
  p_run_id uuid,
  p_error_message text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.catalog_stats_cache
  set status = 'failed',
      run_id = p_run_id,
      error_message = left(p_error_message, 4000),
      updated_at = now()
  where singleton;
end;
$$;

revoke all on function public.begin_catalog_index_rebuild(uuid) from public;
revoke all on function public.rebuild_catalog_index_batch(uuid, text, integer) from public;
revoke all on function public.finalize_catalog_index_rebuild(uuid) from public;
revoke all on function public.fail_catalog_index_rebuild(uuid, text) from public;
grant execute on function public.begin_catalog_index_rebuild(uuid) to service_role;
grant execute on function public.rebuild_catalog_index_batch(uuid, text, integer) to service_role;
grant execute on function public.finalize_catalog_index_rebuild(uuid) to service_role;
grant execute on function public.fail_catalog_index_rebuild(uuid, text) to service_role;

create or replace function public.catalog_stats()
returns jsonb
language sql
stable
security definer
set search_path = ''
set statement_timeout = '10s'
as $$
  select jsonb_build_object(
    'total_listings', coalesce(csc.total_listings, 0),
    'total_games', coalesce(csc.total_games, 0),
    'stores', coalesce(csc.stores, '{}'::jsonb),
    'years', coalesce(csc.years, '[]'::jsonb),
    'index_status', coalesce(csc.status, 'idle'),
    'index_updated_at', csc.updated_at,
    'sync', coalesce((
      select jsonb_agg(to_jsonb(css) order by css.store)
      from public.catalog_sync_state css
    ), '[]'::jsonb)
  )
  from (select 1) seed
  left join public.catalog_stats_cache csc on csc.singleton;
$$;

revoke all on function public.catalog_stats() from public;
grant execute on function public.catalog_stats() to anon, authenticated;

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
        + extensions.similarity(lower(cg.search_text), p.q) * 3
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
      or lower(cg.search_text) like '%' || p.q || '%'
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

create or replace function public.get_catalog_game(p_key text)
returns jsonb
language sql
stable
security definer
set search_path = ''
set statement_timeout = '10s'
as $$
  select case when cg.match_key is null then null else jsonb_build_object(
    'canonical_id', cg.canonical_id,
    'match_key', cg.match_key,
    'internal_id', cg.canonical_id,
    'listing_id', (cg.store_listings -> 0 ->> 'listing_id'),
    'source_kind', 'catalog',
    'store', (cg.store_listings -> 0 ->> 'store'),
    'stores', to_jsonb(cg.stores),
    'store_listings', cg.store_listings,
    'title', cg.title,
    'canonical_title', cg.canonical_title,
    'description', cg.description,
    'developer', cg.developer,
    'publisher', cg.publisher,
    'image_url', cg.image_url,
    'store_url', cg.store_url,
    'release_date', cg.release_date,
    'release_year', cg.release_year,
    'market_segment', cg.market_segment,
    'category_group', cg.category_group,
    'offer_type', cg.offer_type,
    'platforms', to_jsonb(cg.platforms),
    'genres', to_jsonb(cg.genres),
    'categories', to_jsonb(cg.categories)
  ) end
  from public.catalog_games cg
  where cg.match_key = p_key
     or cg.canonical_id = p_key
     or exists (
       select 1 from jsonb_array_elements(cg.store_listings) listing
       where listing ->> 'listing_id' = p_key
     )
  order by case when cg.match_key = p_key then 0 when cg.canonical_id = p_key then 1 else 2 end
  limit 1;
$$;

revoke all on function public.get_catalog_game(text) from public;
grant execute on function public.get_catalog_game(text) to anon, authenticated;

create or replace function public.get_catalog_games(p_keys text[])
returns jsonb
language sql
stable
security definer
set search_path = ''
set statement_timeout = '10s'
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'canonical_id', cg.canonical_id,
    'match_key', cg.match_key,
    'internal_id', cg.canonical_id,
    'listing_id', (cg.store_listings -> 0 ->> 'listing_id'),
    'source_kind', 'catalog',
    'store', (cg.store_listings -> 0 ->> 'store'),
    'stores', to_jsonb(cg.stores),
    'store_listings', cg.store_listings,
    'title', cg.title,
    'canonical_title', cg.canonical_title,
    'description', cg.description,
    'developer', cg.developer,
    'publisher', cg.publisher,
    'image_url', cg.image_url,
    'store_url', cg.store_url,
    'release_date', cg.release_date,
    'release_year', cg.release_year,
    'market_segment', cg.market_segment,
    'category_group', cg.category_group
  )), '[]'::jsonb)
  from public.catalog_games cg
  where cg.match_key = any(coalesce(p_keys, '{}'::text[]))
     or cg.canonical_id = any(coalesce(p_keys, '{}'::text[]))
     or exists (
       select 1 from jsonb_array_elements(cg.store_listings) listing
       where listing ->> 'listing_id' = any(coalesce(p_keys, '{}'::text[]))
     );
$$;

revoke all on function public.get_catalog_games(text[]) from public;
grant execute on function public.get_catalog_games(text[]) to anon, authenticated;

comment on table public.catalog_games is
'Canonical, preaggregated read model used by the public catalog RPCs.';
