-- The Free Vault v4.7.4 — catalog search performance hotfix.
--
-- The previous RPC materialized complete catalog_games rows before pagination
-- and mixed an indexable trigram predicate with a non-indexable similarity()
-- comparison. On a large catalog this could force broad scans and large
-- temporary results. This replacement searches lightweight keys first, pages
-- them, and only then loads the complete JSON payload for the visible rows.
-- No new table or index is created.

analyze public.catalog_games;

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
set statement_timeout = '12s'
as $$
with params as (
  select
    lower(trim(coalesce(p_query, ''))) as q,
    greatest(1, least(coalesce(p_limit, 36), 100)) as page_limit,
    greatest(0, coalesce(p_offset, 0)) as page_offset
),
search_matches as materialized (
  select
    raw.match_key,
    max(raw.relevance_score)::real as relevance_score
  from (
    -- Substring/exact/prefix lookup: backed by catalog_games_title_trgm_idx.
    select
      cg.match_key,
      case
        when lower(cg.title) = p.q then 100::real
        when lower(cg.canonical_title) = p.q then 95::real
        when lower(cg.title) like p.q || '%' then 80::real
        when lower(cg.canonical_title) like p.q || '%' then 75::real
        else (55 + extensions.similarity(lower(cg.title), p.q) * 20)::real
      end as relevance_score
    from public.catalog_games cg
    cross join params p
    where p.q <> ''
      and lower(cg.title) like '%' || p.q || '%'

    union all

    -- Fuzzy title lookup: the pg_trgm % operator is indexable, unlike
    -- similarity(column, query) >= threshold used as a filter.
    select
      cg.match_key,
      (35 + extensions.similarity(lower(cg.title), p.q) * 25)::real as relevance_score
    from public.catalog_games cg
    cross join params p
    where p.q <> ''
      and char_length(p.q) >= 3
      and lower(cg.title) operator(extensions.%) p.q
  ) raw
  group by raw.match_key
),
eligible as not materialized (
  select
    cg.match_key,
    cg.title,
    cg.release_date,
    cg.sort_price,
    coalesce(sm.relevance_score, 0::real) as relevance_score
  from public.catalog_games cg
  cross join params p
  left join search_matches sm on sm.match_key = cg.match_key
  where
    (p.q = '' or sm.match_key is not null)
    and (p_stores is null or cardinality(p_stores) = 0 or cg.stores && p_stores)
    and (p_category is null or p_category = '' or p_category = 'all' or cg.category_group = p_category)
    and (p_segment is null or p_segment = '' or p_segment = 'all' or cg.market_segment = p_segment)
    and (p_year is null or cg.release_year = p_year)
    and (
      p_price is null or p_price = '' or p_price = 'all'
      or (p_price = 'free' and exists (
        select 1
        from jsonb_array_elements(cg.store_listings) listing
        where coalesce(
          (listing ->> 'discount_price')::bigint,
          (listing ->> 'original_price')::bigint,
          1
        ) = 0
      ))
      or (p_price = 'discounted' and exists (
        select 1
        from jsonb_array_elements(cg.store_listings) listing
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
    else (select count(*) from eligible)
  end as total_count
),
paged_keys as (
  select e.*
  from eligible e
  cross join params p
  order by
    case when p_sort = 'title' or (p_sort = 'relevance' and p.q = '') then lower(e.title) end asc nulls last,
    case when p_sort = 'date' then e.release_date end desc nulls last,
    case when p_sort = 'value' then e.sort_price end desc nulls last,
    case when p_sort = 'relevance' and p.q <> '' then e.relevance_score end desc nulls last,
    lower(e.title) asc,
    e.match_key asc
  limit (select page_limit from params)
  offset (select page_offset from params)
),
page_rows as (
  select
    cg,
    pk.relevance_score,
    pk.title as sort_title,
    pk.release_date as sort_release_date,
    pk.sort_price as sort_value,
    pk.match_key as sort_match_key
  from paged_keys pk
  join public.catalog_games cg on cg.match_key = pk.match_key
)
select jsonb_build_object(
  'items', coalesce(jsonb_agg(
    public.catalog_game_card_json(cg)
    order by
      case when p_sort = 'title' or (p_sort = 'relevance' and (select q from params) = '') then lower(sort_title) end asc nulls last,
      case when p_sort = 'date' then sort_release_date end desc nulls last,
      case when p_sort = 'value' then sort_value end desc nulls last,
      case when p_sort = 'relevance' and (select q from params) <> '' then relevance_score end desc nulls last,
      lower(sort_title) asc,
      sort_match_key asc
  ), '[]'::jsonb),
  'total', (select total_count from counted),
  'limit', (select page_limit from params),
  'offset', (select page_offset from params)
)
from page_rows;
$$;

revoke all on function public.search_catalog(text, text[], text, text, text, integer, text[], text[], text, text, integer, integer) from public;
grant execute on function public.search_catalog(text, text[], text, text, text, integer, text[], text[], text, text, integer, integer) to anon, authenticated;

comment on function public.search_catalog(text, text[], text, text, text, integer, text[], text[], text, text, integer, integer) is
'Catalog search v4.7.4: indexed title matching, lightweight key pagination, full rows loaded only after LIMIT.';
