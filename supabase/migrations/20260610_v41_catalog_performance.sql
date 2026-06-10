-- The Free Vault v4.1 — catalogo server-side, ricerca indicizzata e paginazione.
-- Eseguire dopo la migrazione v4.0.

create extension if not exists pg_trgm with schema extensions;

create table if not exists public.catalog_items (
  listing_id text primary key,
  canonical_id text not null,
  match_key text not null,
  store text not null
    check (store in ('epic', 'steam', 'playstation', 'xbox', 'nintendo', 'other')),
  external_id text not null,
  namespace text,
  title text not null,
  canonical_title text not null,
  description text,
  developer text,
  publisher text,
  image_url text,
  store_url text,
  product_slug text,
  offer_type text,
  category_group text not null default 'other'
    check (category_group in ('base_game', 'dlc', 'bundle', 'edition', 'other')),
  edition_name text,
  market_segment text not null default 'unclassified'
    check (market_segment in ('aaa', 'indie', 'unclassified')),
  release_date date,
  release_year integer,
  original_price integer,
  discount_price integer,
  currency_code text,
  currency_decimals integer not null default 2,
  fmt_original_price text,
  fmt_discount_price text,
  platforms text[] not null default '{}',
  genres text[] not null default '{}',
  tags text[] not null default '{}',
  categories text[] not null default '{}',
  available boolean not null default true,
  sync_run_id uuid not null,
  last_synced_at timestamptz not null default now(),
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
  ) stored,
  unique (store, external_id)
);

create table if not exists public.catalog_sync_state (
  store text primary key
    check (store in ('epic', 'steam', 'playstation', 'xbox', 'nintendo', 'other')),
  run_id uuid,
  status text not null default 'idle'
    check (status in ('idle', 'running', 'completed', 'failed')),
  listing_count bigint not null default 0,
  canonical_count bigint not null default 0,
  started_at timestamptz,
  completed_at timestamptz,
  error_message text,
  metadata jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

create index if not exists catalog_items_canonical_id_idx
on public.catalog_items(canonical_id);

create index if not exists catalog_items_match_key_idx
on public.catalog_items(match_key);

create index if not exists catalog_items_store_idx
on public.catalog_items(store);

create index if not exists catalog_items_category_idx
on public.catalog_items(category_group);

create index if not exists catalog_items_segment_idx
on public.catalog_items(market_segment);

create index if not exists catalog_items_release_year_idx
on public.catalog_items(release_year desc);

create index if not exists catalog_items_price_idx
on public.catalog_items(discount_price, original_price);

create index if not exists catalog_items_search_document_idx
on public.catalog_items using gin(search_document);

create index if not exists catalog_items_title_trgm_idx
on public.catalog_items using gin(lower(title) extensions.gin_trgm_ops);

create index if not exists catalog_items_search_text_trgm_idx
on public.catalog_items using gin(lower(search_text) extensions.gin_trgm_ops);

alter table public.catalog_items enable row level security;
alter table public.catalog_sync_state enable row level security;

drop policy if exists "Catalog items are publicly readable" on public.catalog_items;
drop policy if exists "Catalog sync state is publicly readable" on public.catalog_sync_state;

-- Il catalogo completo non è interrogabile direttamente dal browser: il client
-- usa esclusivamente le RPC paginate definite sotto.
revoke all on public.catalog_items from anon, authenticated;
revoke all on public.catalog_sync_state from anon, authenticated;
grant select, insert, update, delete on public.catalog_items to service_role;
grant select, insert, update, delete on public.catalog_sync_state to service_role;

create or replace function public.begin_catalog_sync(
  p_store text,
  p_run_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.catalog_sync_state (
    store, run_id, status, listing_count, canonical_count,
    started_at, completed_at, error_message, updated_at
  )
  values (
    p_store, p_run_id, 'running', 0, 0,
    now(), null, null, now()
  )
  on conflict (store) do update set
    run_id = excluded.run_id,
    status = 'running',
    started_at = now(),
    completed_at = null,
    error_message = null,
    updated_at = now();
end;
$$;

create or replace function public.finalize_catalog_sync(
  p_store text,
  p_run_id uuid,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_listing_count bigint;
  v_canonical_count bigint;
begin
  delete from public.catalog_items
  where store = p_store
    and sync_run_id <> p_run_id;

  select count(*), count(distinct match_key)
  into v_listing_count, v_canonical_count
  from public.catalog_items
  where store = p_store
    and sync_run_id = p_run_id;

  insert into public.catalog_sync_state (
    store, run_id, status, listing_count, canonical_count,
    started_at, completed_at, error_message, metadata, updated_at
  )
  values (
    p_store, p_run_id, 'completed', v_listing_count, v_canonical_count,
    now(), now(), null, coalesce(p_metadata, '{}'::jsonb), now()
  )
  on conflict (store) do update set
    run_id = excluded.run_id,
    status = 'completed',
    listing_count = v_listing_count,
    canonical_count = v_canonical_count,
    completed_at = now(),
    error_message = null,
    metadata = coalesce(p_metadata, '{}'::jsonb),
    updated_at = now();

  return jsonb_build_object(
    'store', p_store,
    'listing_count', v_listing_count,
    'canonical_count', v_canonical_count,
    'completed_at', now()
  );
end;
$$;

create or replace function public.fail_catalog_sync(
  p_store text,
  p_run_id uuid,
  p_error_message text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.catalog_sync_state (
    store, run_id, status, error_message, started_at, updated_at
  )
  values (
    p_store, p_run_id, 'failed', left(p_error_message, 4000), now(), now()
  )
  on conflict (store) do update set
    run_id = excluded.run_id,
    status = 'failed',
    error_message = left(p_error_message, 4000),
    completed_at = now(),
    updated_at = now();
end;
$$;

revoke all on function public.begin_catalog_sync(text, uuid) from public;
revoke all on function public.finalize_catalog_sync(text, uuid, jsonb) from public;
revoke all on function public.fail_catalog_sync(text, uuid, text) from public;
grant execute on function public.begin_catalog_sync(text, uuid) to service_role;
grant execute on function public.finalize_catalog_sync(text, uuid, jsonb) to service_role;
grant execute on function public.fail_catalog_sync(text, uuid, text) to service_role;

create or replace function public.catalog_stats()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'total_listings', (select count(*) from public.catalog_items where available),
    'total_games', (select count(distinct match_key) from public.catalog_items where available),
    'stores', coalesce((
      select jsonb_object_agg(store, listing_count)
      from (
        select store, count(*) as listing_count
        from public.catalog_items
        where available
        group by store
      ) s
    ), '{}'::jsonb),
    'years', coalesce((
      select jsonb_agg(release_year order by release_year desc)
      from (
        select distinct release_year
        from public.catalog_items
        where available and release_year is not null
      ) y
    ), '[]'::jsonb),
    'sync', coalesce((
      select jsonb_agg(to_jsonb(css) order by css.store)
      from public.catalog_sync_state css
    ), '[]'::jsonb)
  );
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
as $$
with params as (
  select
    lower(trim(coalesce(p_query, ''))) as q,
    greatest(1, least(coalesce(p_limit, 36), 100)) as page_limit,
    greatest(0, coalesce(p_offset, 0)) as page_offset
),
filtered as (
  select
    ci.*,
    case
      when p.q = '' then 0::real
      when lower(ci.title) = p.q then 100::real
      when lower(ci.canonical_title) = p.q then 95::real
      when lower(ci.title) like p.q || '%' then 70::real
      when lower(ci.canonical_title) like p.q || '%' then 65::real
      else (
        ts_rank_cd(ci.search_document, websearch_to_tsquery('simple', p.q)) * 20
        + extensions.similarity(lower(ci.title), p.q) * 10
        + extensions.similarity(lower(ci.search_text), p.q) * 3
      )::real
    end as relevance_score,
    (
      (case when ci.store = 'epic' then 3 else 0 end)
      + (case when nullif(ci.description, '') is not null then 2 else 0 end)
      + (case when ci.image_url is not null then 2 else 0 end)
      + (case when ci.developer is not null then 1 else 0 end)
      + (case when ci.publisher is not null then 1 else 0 end)
      + (case when ci.release_date is not null then 1 else 0 end)
    ) as richness_score
  from public.catalog_items ci
  cross join params p
  where ci.available
    and (p_stores is null or cardinality(p_stores) = 0 or ci.store = any(p_stores))
    and (p_category is null or p_category = '' or p_category = 'all' or ci.category_group = p_category)
    and (p_segment is null or p_segment = '' or p_segment = 'all' or ci.market_segment = p_segment)
    and (p_year is null or ci.release_year = p_year)
    and (
      p_price is null or p_price = '' or p_price = 'all'
      or (p_price = 'free' and coalesce(ci.discount_price, ci.original_price, 1) = 0)
      or (p_price = 'discounted' and ci.original_price is not null and ci.discount_price is not null and ci.discount_price < ci.original_price)
      or (p_price = 'paid' and coalesce(ci.discount_price, ci.original_price, 0) > 0)
    )
    and (
      p_personal_filter is null or p_personal_filter = '' or p_personal_filter = 'all'
      or (p_personal_filter = 'saved' and (ci.match_key = any(coalesce(p_library_keys, '{}'::text[])) or ci.canonical_id = any(coalesce(p_library_keys, '{}'::text[]))))
      or (p_personal_filter = 'favorite' and (ci.match_key = any(coalesce(p_favorite_keys, '{}'::text[])) or ci.canonical_id = any(coalesce(p_favorite_keys, '{}'::text[]))))
    )
    and (
      p.q = ''
      or lower(ci.search_text) like '%' || p.q || '%'
      or ci.search_document @@ websearch_to_tsquery('simple', p.q)
      or extensions.similarity(lower(ci.title), p.q) >= 0.22
    )
),
representatives as (
  select *
  from (
    select
      f.*,
      row_number() over (
        partition by f.match_key
        order by f.richness_score desc, f.store asc, f.listing_id asc
      ) as representative_rank
    from filtered f
  ) ranked
  where representative_rank = 1
),
grouped as (
  select
    max(r.canonical_id) as canonical_id,
    r.match_key,
    max(r.canonical_title) as canonical_title,
    max(r.title) as title,
    max(r.description) as description,
    max(r.developer) as developer,
    max(r.publisher) as publisher,
    max(r.image_url) as image_url,
    max(r.release_date) as release_date,
    max(r.release_year) as release_year,
    max(r.market_segment) as market_segment,
    max(r.category_group) as category_group,
    max(r.relevance_score) as relevance_score,
    array_agg(distinct f.store order by f.store) as stores,
    jsonb_agg(
      jsonb_build_object(
        'listing_id', f.listing_id,
        'store', f.store,
        'external_id', f.external_id,
        'namespace', f.namespace,
        'title', f.title,
        'store_url', f.store_url,
        'image_url', f.image_url,
        'offer_type', f.offer_type,
        'category_group', f.category_group,
        'edition_name', f.edition_name,
        'original_price', f.original_price,
        'discount_price', f.discount_price,
        'currency_code', f.currency_code,
        'currency_decimals', f.currency_decimals,
        'fmt_original_price', f.fmt_original_price,
        'fmt_discount_price', f.fmt_discount_price
      ) order by f.store, f.listing_id
    ) as store_listings,
    max(coalesce(f.discount_price, f.original_price, 0)) as sort_price
  from representatives r
  join filtered f on f.match_key = r.match_key
  group by r.match_key
),
ordered as (
  select
    g.*,
    count(*) over () as total_count,
    row_number() over (
      order by
        case when p_sort = 'title' then lower(g.title) end asc nulls last,
        case when p_sort = 'date' then g.release_date end desc nulls last,
        case when p_sort = 'value' then g.sort_price end desc nulls last,
        case when p_sort not in ('title', 'date', 'value') then g.relevance_score end desc nulls last,
        lower(g.title) asc
    ) as sort_position
  from grouped g
),
paged as (
  select o.*
  from ordered o
  cross join params p
  where o.sort_position > p.page_offset
    and o.sort_position <= p.page_offset + p.page_limit
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
      'store_url', (store_listings -> 0 ->> 'store_url'),
      'release_date', release_date,
      'release_year', release_year,
      'market_segment', market_segment,
      'category_group', category_group,
      'original_price', (store_listings -> 0 -> 'original_price'),
      'discount_price', (store_listings -> 0 -> 'discount_price'),
      'currency_code', (store_listings -> 0 ->> 'currency_code'),
      'fmt_original_price', (store_listings -> 0 ->> 'fmt_original_price'),
      'fmt_discount_price', (store_listings -> 0 ->> 'fmt_discount_price')
    ) order by sort_position
  ), '[]'::jsonb),
  'total', coalesce(max(total_count), 0),
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
as $$
with target as (
  select ci.match_key
  from public.catalog_items ci
  where ci.available
    and (
      ci.canonical_id = p_key
      or ci.match_key = p_key
      or ci.listing_id = p_key
    )
  order by case when ci.match_key = p_key then 0 when ci.canonical_id = p_key then 1 when ci.listing_id = p_key then 2 else 3 end
  limit 1
),
ranked as (
  select
    ci.*,
    row_number() over (
      order by
        (case when ci.store = 'epic' then 3 else 0 end)
        + (case when nullif(ci.description, '') is not null then 2 else 0 end)
        + (case when ci.image_url is not null then 2 else 0 end) desc,
        ci.store,
        ci.listing_id
    ) as rn
  from public.catalog_items ci
  join target t on t.match_key = ci.match_key
  where ci.available
),
representative as (
  select * from ranked where rn = 1
)
select case when not exists(select 1 from representative) then null else jsonb_build_object(
  'canonical_id', r.canonical_id,
  'match_key', r.match_key,
  'internal_id', r.canonical_id,
  'listing_id', r.listing_id,
  'source_kind', 'catalog',
  'store', r.store,
  'stores', (select jsonb_agg(distinct x.store) from ranked x),
  'store_listings', (select jsonb_agg(
    jsonb_build_object(
      'listing_id', x.listing_id,
      'store', x.store,
      'external_id', x.external_id,
      'namespace', x.namespace,
      'title', x.title,
      'store_url', x.store_url,
      'image_url', x.image_url,
      'offer_type', x.offer_type,
      'category_group', x.category_group,
      'edition_name', x.edition_name,
      'original_price', x.original_price,
      'discount_price', x.discount_price,
      'currency_code', x.currency_code,
      'currency_decimals', x.currency_decimals,
      'fmt_original_price', x.fmt_original_price,
      'fmt_discount_price', x.fmt_discount_price
    ) order by x.store, x.listing_id
  ) from ranked x),
  'title', r.title,
  'canonical_title', r.canonical_title,
  'description', r.description,
  'developer', r.developer,
  'publisher', r.publisher,
  'image_url', r.image_url,
  'store_url', r.store_url,
  'release_date', r.release_date,
  'release_year', r.release_year,
  'market_segment', r.market_segment,
  'category_group', r.category_group,
  'offer_type', r.offer_type,
  'original_price', r.original_price,
  'discount_price', r.discount_price,
  'currency_code', r.currency_code,
  'currency_decimals', r.currency_decimals,
  'fmt_original_price', r.fmt_original_price,
  'fmt_discount_price', r.fmt_discount_price,
  'platforms', to_jsonb(r.platforms),
  'genres', to_jsonb(r.genres),
  'categories', to_jsonb(r.categories)
) end
from representative r;
$$;

revoke all on function public.get_catalog_game(text) from public;
grant execute on function public.get_catalog_game(text) to anon, authenticated;

comment on table public.catalog_items is
'Denormalized, indexed projection of all store listings used by the public catalog UI.';

comment on function public.search_catalog is
'Paginated server-side catalog search with filters, fuzzy matching and canonical grouping.';

create or replace function public.get_catalog_games(p_keys text[])
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
with requested as (
  select distinct unnest(coalesce(p_keys, '{}'::text[])) as requested_key
),
targets as (
  select distinct ci.match_key
  from public.catalog_items ci
  join requested r
    on ci.canonical_id = r.requested_key
    or ci.match_key = r.requested_key
    or ci.listing_id = r.requested_key
  where ci.available
),
ranked as (
  select
    ci.*,
    row_number() over (
      partition by ci.match_key
      order by
        (
          (case when ci.store = 'epic' then 3 else 0 end)
          + (case when nullif(ci.description, '') is not null then 2 else 0 end)
          + (case when ci.image_url is not null then 2 else 0 end)
        ) desc,
        ci.store,
        ci.listing_id
    ) as rn
  from public.catalog_items ci
  join targets t on t.match_key = ci.match_key
  where ci.available
),
grouped as (
  select
    max(r.canonical_id) as canonical_id,
    r.match_key,
    max(r.title) filter (where r.rn = 1) as title,
    max(r.canonical_title) filter (where r.rn = 1) as canonical_title,
    max(r.description) filter (where r.rn = 1) as description,
    max(r.developer) filter (where r.rn = 1) as developer,
    max(r.publisher) filter (where r.rn = 1) as publisher,
    max(r.image_url) filter (where r.rn = 1) as image_url,
    max(r.store_url) filter (where r.rn = 1) as store_url,
    max(r.store) filter (where r.rn = 1) as store,
    max(r.release_date) filter (where r.rn = 1) as release_date,
    max(r.release_year) filter (where r.rn = 1) as release_year,
    max(r.market_segment) filter (where r.rn = 1) as market_segment,
    max(r.category_group) filter (where r.rn = 1) as category_group,
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
    ) as store_listings
  from ranked r
  group by r.match_key
)
select coalesce(jsonb_agg(jsonb_build_object(
  'canonical_id', canonical_id,
  'match_key', match_key,
  'internal_id', canonical_id,
  'source_kind', 'catalog',
  'store', store,
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
  'category_group', category_group
)), '[]'::jsonb)
from grouped;
$$;

revoke all on function public.get_catalog_games(text[]) from public;
grant execute on function public.get_catalog_games(text[]) to anon, authenticated;
