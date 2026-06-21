-- Ludograph v5.6.2 — search_catalog fast-path hotfix
--
-- Emergency fix after v5.6.0 canonical foundation: keep canonical resolution
-- in get_catalog_game/detail pages, but restore the bounded candidate-first
-- search plan for catalog browsing. The canonicalized search version resolved
-- every eligible row before pagination and timed out on large catalog pages.
begin;

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
language plpgsql
stable
security definer
set search_path = ''
set statement_timeout = '15s'
as $$
declare
  v_q text := lower(trim(coalesce(p_query, '')));
  v_limit integer := greatest(1, least(coalesce(p_limit, 36), 100));
  v_offset integer := greatest(0, coalesce(p_offset, 0));
  v_candidate_limit integer;
  v_candidate_keys text[] := '{}'::text[];
  v_candidate_limited boolean := false;
  v_total bigint := 0;
  v_result jsonb;
  v_has_filters boolean;
begin
  v_candidate_limit := least(
    5000,
    greatest(500, (v_offset + v_limit) * 20)
  );

  v_has_filters :=
    (p_stores is not null and cardinality(p_stores) > 0)
    or (p_category is not null and p_category not in ('', 'all'))
    or (p_segment is not null and p_segment not in ('', 'all'))
    or (p_price is not null and p_price not in ('', 'all'))
    or p_year is not null
    or (p_personal_filter is not null and p_personal_filter not in ('', 'all'));

  if v_q <> '' then
    -- Phase 1: indexed substring candidates. Each branch can use its own GIN
    -- trigram index; the bounded array becomes the hard boundary for all later
    -- work, independently of the generic plan chosen for the RPC.
    select coalesce(array_agg(limited.match_key order by limited.relevance_score desc, limited.sort_title, limited.release_date asc nulls last, limited.match_key), '{}'::text[])
    into v_candidate_keys
    from (
      select
        deduped.match_key,
        deduped.relevance_score,
        deduped.sort_title,
        deduped.release_date
      from (
        select
          raw.match_key,
          max(raw.relevance_score)::real as relevance_score,
          min(raw.sort_title) as sort_title,
          min(raw.release_date) as release_date
        from (
          select
            cg.match_key,
            case
              when lower(cg.title) = v_q then 100::real
              when lower(cg.title) like v_q || '%' then 90::real
              else 72::real
            end as relevance_score,
            lower(cg.title) as sort_title,
            cg.release_date
          from public.catalog_games cg
          where lower(cg.title) like '%' || v_q || '%'

          union all

          select
            cg.match_key,
            case
              when lower(cg.canonical_title) = v_q then 98::real
              when lower(cg.canonical_title) like v_q || '%' then 88::real
              else 68::real
            end as relevance_score,
            lower(cg.title) as sort_title,
            cg.release_date
          from public.catalog_games cg
          where lower(cg.canonical_title) like '%' || v_q || '%'
        ) raw
        group by raw.match_key
      ) deduped
      order by deduped.relevance_score desc, deduped.sort_title,
        deduped.release_date asc nulls last, deduped.match_key
      limit v_candidate_limit
    ) limited;

    -- Phase 2: fuzzy matching only when substring lookup found nothing.
    if cardinality(v_candidate_keys) = 0 and char_length(v_q) >= 4 then
      select coalesce(array_agg(limited.match_key order by limited.relevance_score desc, limited.sort_title, limited.release_date asc nulls last, limited.match_key), '{}'::text[])
      into v_candidate_keys
      from (
        select
          deduped.match_key,
          deduped.relevance_score,
          deduped.sort_title,
          deduped.release_date
        from (
          select
            raw.match_key,
            max(raw.relevance_score)::real as relevance_score,
            min(raw.sort_title) as sort_title,
            min(raw.release_date) as release_date
          from (
            select
              cg.match_key,
              (35 + extensions.similarity(lower(cg.title), v_q) * 25)::real as relevance_score,
              lower(cg.title) as sort_title,
              cg.release_date
            from public.catalog_games cg
            where lower(cg.title) operator(extensions.%) v_q

            union all

            select
              cg.match_key,
              (35 + extensions.similarity(lower(cg.canonical_title), v_q) * 25)::real as relevance_score,
              lower(cg.title) as sort_title,
              cg.release_date
            from public.catalog_games cg
            where lower(cg.canonical_title) operator(extensions.%) v_q
          ) raw
          group by raw.match_key
        ) deduped
        order by deduped.relevance_score desc, deduped.sort_title,
          deduped.release_date asc nulls last, deduped.match_key
        limit least(v_candidate_limit, 1000)
      ) limited;
    end if;

    v_candidate_limited := cardinality(v_candidate_keys) >= v_candidate_limit;

    with candidate_keys as materialized (
      select keys.match_key, keys.relevance_rank
      from unnest(v_candidate_keys) with ordinality as keys(match_key, relevance_rank)
    ), eligible as materialized (
      select
        cg.match_key,
        cg.title,
        cg.release_date,
        cg.sort_price,
        ck.relevance_rank
      from candidate_keys ck
      join public.catalog_games cg on cg.match_key = ck.match_key
      where
        (p_stores is null or cardinality(p_stores) = 0 or cg.stores && p_stores)
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
    ), page_keys as materialized (
      select e.*
      from eligible e
      order by
        case when p_sort = 'title' then lower(e.title) end asc nulls last,
        case when p_sort = 'date' then e.release_date end desc nulls last,
        case when p_sort = 'value' then e.sort_price end desc nulls last,
        case when p_sort = 'relevance' or p_sort is null or p_sort = '' then e.relevance_rank end asc nulls last,
        lower(e.title) asc,
        e.match_key asc
      limit v_limit
      offset v_offset
    ), page_payload as (
      select coalesce(jsonb_agg(
        public.catalog_game_card_json(cg)
        order by
          case when p_sort = 'title' then lower(pk.title) end asc nulls last,
          case when p_sort = 'date' then pk.release_date end desc nulls last,
          case when p_sort = 'value' then pk.sort_price end desc nulls last,
          case when p_sort = 'relevance' or p_sort is null or p_sort = '' then pk.relevance_rank end asc nulls last,
          lower(pk.title) asc,
          pk.match_key asc
      ), '[]'::jsonb) as items
      from page_keys pk
      join public.catalog_games cg on cg.match_key = pk.match_key
    )
    select
      (select count(*) from eligible),
      jsonb_build_object(
        'items', page_payload.items,
        'total', (select count(*) from eligible),
        'limit', v_limit,
        'offset', v_offset,
        'has_more', v_offset + v_limit < (select count(*) from eligible),
        'candidate_limited', v_candidate_limited
      )
    into v_total, v_result
    from page_payload;

    return coalesce(v_result, jsonb_build_object(
      'items', '[]'::jsonb,
      'total', 0,
      'limit', v_limit,
      'offset', v_offset,
      'has_more', false,
      'candidate_limited', false
    ));
  end if;

  -- Empty-query fast path. With no filters, use the cached catalog total and
  -- page directly from indexed sort columns. This is the normal catalog home.
  if not v_has_filters then
    select coalesce(total_games, 0)
    into v_total
    from public.catalog_stats_cache
    where singleton;

    v_total := coalesce(v_total, 0);

    if p_sort = 'date' then
      select jsonb_build_object(
        'items', coalesce(jsonb_agg(public.catalog_game_card_json(page.game)
          order by page.release_date desc nulls last, lower(page.title), page.match_key), '[]'::jsonb),
        'total', v_total,
        'limit', v_limit,
        'offset', v_offset,
        'has_more', v_offset + v_limit < v_total,
        'candidate_limited', false
      )
      into v_result
      from (
        select cg as game, cg.release_date, cg.title, cg.match_key
        from public.catalog_games cg
        order by cg.release_date desc nulls last, lower(cg.title), cg.match_key
        limit v_limit offset v_offset
      ) page;
    elsif p_sort = 'value' then
      select jsonb_build_object(
        'items', coalesce(jsonb_agg(public.catalog_game_card_json(page.game)
          order by page.sort_price desc nulls last, lower(page.title), page.match_key), '[]'::jsonb),
        'total', v_total,
        'limit', v_limit,
        'offset', v_offset,
        'has_more', v_offset + v_limit < v_total,
        'candidate_limited', false
      )
      into v_result
      from (
        select cg as game, cg.sort_price, cg.title, cg.match_key
        from public.catalog_games cg
        order by cg.sort_price desc nulls last, lower(cg.title), cg.match_key
        limit v_limit offset v_offset
      ) page;
    else
      select jsonb_build_object(
        'items', coalesce(jsonb_agg(public.catalog_game_card_json(page.game)
          order by lower(page.title), page.match_key), '[]'::jsonb),
        'total', v_total,
        'limit', v_limit,
        'offset', v_offset,
        'has_more', v_offset + v_limit < v_total,
        'candidate_limited', false
      )
      into v_result
      from (
        select cg as game, cg.title, cg.match_key
        from public.catalog_games cg
        order by lower(cg.title), cg.match_key
        limit v_limit offset v_offset
      ) page;
    end if;

    return v_result;
  end if;

  -- Filtered browsing without a text query. It may inspect the catalog, but it
  -- is isolated from the normal text-search path and keeps the previous API.
  with eligible as materialized (
    select
      cg.match_key,
      cg.title,
      cg.release_date,
      cg.sort_price
    from public.catalog_games cg
    where
      (p_stores is null or cardinality(p_stores) = 0 or cg.stores && p_stores)
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
  ), page_keys as materialized (
    select e.*
    from eligible e
    order by
      case when p_sort = 'date' then e.release_date end desc nulls last,
      case when p_sort = 'value' then e.sort_price end desc nulls last,
      lower(e.title) asc,
      e.match_key asc
    limit v_limit offset v_offset
  ), page_payload as (
    select coalesce(jsonb_agg(
      public.catalog_game_card_json(cg)
      order by
        case when p_sort = 'date' then pk.release_date end desc nulls last,
        case when p_sort = 'value' then pk.sort_price end desc nulls last,
        lower(pk.title), pk.match_key
    ), '[]'::jsonb) as items
    from page_keys pk
    join public.catalog_games cg on cg.match_key = pk.match_key
  )
  select
    (select count(*) from eligible),
    jsonb_build_object(
      'items', page_payload.items,
      'total', (select count(*) from eligible),
      'limit', v_limit,
      'offset', v_offset,
      'has_more', v_offset + v_limit < (select count(*) from eligible),
      'candidate_limited', false
    )
  into v_total, v_result
  from page_payload;

  return coalesce(v_result, jsonb_build_object(
    'items', '[]'::jsonb,
    'total', 0,
    'limit', v_limit,
    'offset', v_offset,
    'has_more', false,
    'candidate_limited', false
  ));
end;
$$;

revoke all on function public.search_catalog(text, text[], text, text, text, integer, text[], text[], text, text, integer, integer) from public;
grant execute on function public.search_catalog(text, text[], text, text, text, integer, text[], text[], text, text, integer, integer) to anon, authenticated;

comment on function public.search_catalog(text, text[], text, text, text, integer, text[], text[], text, text, integer, integer) is
'Ludograph v5.6.2 hotfix: restore candidate-first bounded search after canonical resolver timeout; canonical detail resolution remains handled by get_catalog_game.';

commit;

notify pgrst, 'reload schema';
