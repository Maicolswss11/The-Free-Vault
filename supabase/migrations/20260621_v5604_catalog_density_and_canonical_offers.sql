-- Ludograph v5.6.4 — catalog density and canonical offer grouping
--
-- v5.6.0 canonicalized the full search result set and timed out on large
-- catalog queries. v5.6.3 restored fast canonical search. This migration adds stronger
-- public catalog grouping for port/bundle/store-offer records and keeps
-- the candidate-first search plan.

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
    greatest(650, (v_offset + v_limit) * 24)
  );

  v_has_filters :=
    (p_stores is not null and cardinality(p_stores) > 0)
    or (p_category is not null and p_category not in ('', 'all'))
    or (p_segment is not null and p_segment not in ('', 'all'))
    or (p_price is not null and p_price not in ('', 'all'))
    or p_year is not null
    or (p_personal_filter is not null and p_personal_filter not in ('', 'all'));

  if v_q <> '' then
    -- Phase 1: indexed substring candidates. Later canonicalization is bounded
    -- to this array, so search never resolves the whole catalog.
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
        cg.canonical_title,
        cg.release_date,
        cg.release_year,
        cg.sort_price,
        cg.source_kind,
        cg.master_game_id,
        cg.canonical_id,
        cg.developer,
        cg.publisher,
        cg.description,
        cg.image_url,
        cg.store_listings,
        cg.stores,
        cg.category_group,
        cg.market_segment,
        ck.relevance_rank,
        lower(coalesce(g.game_type, 'unknown')) as game_type,
        public.catalog_editorial_base_title(cg.title) as title_key,
        coalesce(cg.release_year, extract(year from cg.release_date)::integer, public.catalog_title_year_hint(cg.title)) as year_value,
        public.catalog_is_master_catalog_game(cg) as is_master,
        public.catalog_is_subordinate_game_type(coalesce(g.game_type, 'unknown')) as is_subordinate,
        public.catalog_is_separate_game_type(coalesce(g.game_type, 'unknown')) as is_separate,
        (
          lower(coalesce(cg.description, '') || ' ' || coalesce(cg.title, '') || ' ' || coalesce(cg.category_group, '')) ~
          '(port|ports|ported|version|versions|bundle containing|containing ports|contains ports|collection of ports|includes? .*(expansion|dlc|undead nightmare)|undead nightmare expansion|riedizion|conversion|release for|released for|store listing|store version)'
        ) as has_porting_signal,
        (
          lower(coalesce(g.game_type, 'unknown')) in ('bundle', 'pack')
          or lower(coalesce(cg.category_group, '')) in ('bundle', 'edition')
          or lower(coalesce(cg.title, '') || ' ' || coalesce(cg.description, '')) ~
            '(\[?bundle\]?|bundle containing|collection of ports|pack)'
        ) as is_store_offer,
        (
          case when cg.release_date is not null then 1 else 0 end
          + case when nullif(cg.description, '') is not null then 1 else 0 end
          + case when nullif(cg.developer, '') is not null then 1 else 0 end
          + case when nullif(cg.publisher, '') is not null then 1 else 0 end
          + case when nullif(cg.image_url, '') is not null then 1 else 0 end
          + case when cardinality(coalesce(cg.platforms, '{}'::text[])) > 0 then 1 else 0 end
        ) as completeness_score
      from candidate_keys ck
      join public.catalog_games cg on cg.match_key = ck.match_key
      left join public.games g on g.id = cg.master_game_id
      where
        (p_stores is null or cardinality(p_stores) = 0 or cg.stores && p_stores)
        and (p_category is null or p_category = '' or p_category = 'all' or cg.category_group = p_category)
        and (p_segment is null or p_segment = '' or p_segment = 'all' or cg.market_segment = p_segment)
        and (p_year is null or cg.release_year = p_year)
        and (
          p_price is null or p_price = '' or p_price = 'all'
          or (p_price = 'free' and exists (
            select 1
            from jsonb_array_elements(coalesce(cg.store_listings, '[]'::jsonb)) listing
            where coalesce(
              nullif(listing ->> 'discount_price', '')::bigint,
              nullif(listing ->> 'original_price', '')::bigint,
              1
            ) = 0
          ))
          or (p_price = 'discounted' and exists (
            select 1
            from jsonb_array_elements(coalesce(cg.store_listings, '[]'::jsonb)) listing
            where nullif(listing ->> 'original_price', '') is not null
              and nullif(listing ->> 'discount_price', '') is not null
              and nullif(listing ->> 'discount_price', '')::bigint < nullif(listing ->> 'original_price', '')::bigint
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
    ), featured as materialized (
      select
        e.*,
        (
          e.source_kind <> 'master'
          or e.is_subordinate
          or e.has_porting_signal
          or e.is_store_offer
        ) as is_variant_candidate
      from eligible e
    ), grouped as materialized (
      select
        f.*,
        case
          when f.is_separate and not (f.has_porting_signal or f.is_store_offer) or f.title_key = '' then 'separate:' || f.match_key
          when f.is_variant_candidate then 'title:' || f.title_key || ':' || coalesce(
            case when f.has_porting_signal or f.is_store_offer then (
              select min(peer.year_value)::text
              from featured peer
              where peer.title_key = f.title_key
                and not peer.is_separate
                and not peer.is_store_offer
                and peer.year_value is not null
            ) else null end,
            (
              select min(peer.year_value)::text
              from featured peer
              where peer.title_key = f.title_key
                and not peer.is_separate
                and not peer.is_variant_candidate
                and peer.year_value is not null
                and f.year_value is not null
                and abs(peer.year_value - f.year_value) <= 2
            ),
            f.year_value::text,
            (
              select min(peer.year_value)::text
              from featured peer
              where peer.title_key = f.title_key
                and not peer.is_separate
                and peer.year_value is not null
            ),
            'unknown'
          )
          else 'title:' || f.title_key || ':' || coalesce(f.year_value::text, 'unknown')
        end as search_group_key
      from featured f
    ), ranked_groups as materialized (
      select
        g.*,
        count(*) over (partition by g.search_group_key) as variant_count,
        row_number() over (
          partition by g.search_group_key
          order by
            g.is_master desc,
            g.is_store_offer asc,
            g.has_porting_signal asc,
            case g.source_kind when 'master' then 0 when 'hybrid' then 1 when 'catalog' then 2 else 3 end,
            g.completeness_score desc,
            g.relevance_rank asc,
            g.release_date asc nulls last,
            g.match_key asc
        ) as representative_rank,
        min(g.relevance_rank) over (partition by g.search_group_key) as group_relevance_rank,
        min(g.title) over (partition by g.search_group_key) as group_title,
        min(g.release_date) over (partition by g.search_group_key) as group_release_date,
        max(g.sort_price) over (partition by g.search_group_key) as group_sort_price
      from grouped g
    ), representatives as materialized (
      select *
      from ranked_groups rg
      where rg.representative_rank = 1
    ), page_keys as materialized (
      select r.*
      from representatives r
      order by
        case when p_sort = 'title' then lower(r.group_title) end asc nulls last,
        case when p_sort = 'date' then r.group_release_date end desc nulls last,
        case when p_sort = 'value' then r.group_sort_price end desc nulls last,
        case when p_sort = 'relevance' or p_sort is null or p_sort = '' then r.group_relevance_rank end asc nulls last,
        lower(r.group_title) asc,
        r.search_group_key asc
      limit v_limit
      offset v_offset
    ), page_payload as (
      select coalesce(jsonb_agg(
        public.catalog_game_card_json(cg)
        || jsonb_build_object(
          'canonical_route_key', cg.match_key,
          'canonical_work_key', pk.search_group_key,
          'search_group_key', pk.search_group_key,
          'search_variant_count', pk.variant_count,
          'canonical_source', 'search_candidate_group',
          'is_canonical', true,
          'canonicalized', true
        )
        order by
          case when p_sort = 'title' then lower(pk.group_title) end asc nulls last,
          case when p_sort = 'date' then pk.group_release_date end desc nulls last,
          case when p_sort = 'value' then pk.group_sort_price end desc nulls last,
          case when p_sort = 'relevance' or p_sort is null or p_sort = '' then pk.group_relevance_rank end asc nulls last,
          lower(pk.group_title) asc,
          pk.search_group_key asc
      ), '[]'::jsonb) as items
      from page_keys pk
      join public.catalog_games cg on cg.match_key = pk.match_key
    )
    select
      (select count(*) from representatives),
      jsonb_build_object(
        'items', page_payload.items,
        'total', (select count(*) from representatives),
        'canonical_total', (select count(*) from representatives),
        'limit', v_limit,
        'offset', v_offset,
        'has_more', v_offset + v_limit < (select count(*) from representatives),
        'candidate_limited', v_candidate_limited,
        'canonicalized', true,
        'canonical_strategy', 'candidate_first_grouping'
      )
    into v_total, v_result
    from page_payload;

    return coalesce(v_result, jsonb_build_object(
      'items', '[]'::jsonb,
      'total', 0,
      'canonical_total', 0,
      'limit', v_limit,
      'offset', v_offset,
      'has_more', false,
      'candidate_limited', false,
      'canonicalized', true,
      'canonical_strategy', 'candidate_first_grouping'
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
        'candidate_limited', false,
        'canonicalized', false
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
        'candidate_limited', false,
        'canonicalized', false
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
        'candidate_limited', false,
        'canonicalized', false
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
          from jsonb_array_elements(coalesce(cg.store_listings, '[]'::jsonb)) listing
          where coalesce(
            nullif(listing ->> 'discount_price', '')::bigint,
            nullif(listing ->> 'original_price', '')::bigint,
            1
          ) = 0
        ))
        or (p_price = 'discounted' and exists (
          select 1
          from jsonb_array_elements(coalesce(cg.store_listings, '[]'::jsonb)) listing
          where nullif(listing ->> 'original_price', '') is not null
            and nullif(listing ->> 'discount_price', '') is not null
            and nullif(listing ->> 'discount_price', '')::bigint < nullif(listing ->> 'original_price', '')::bigint
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
      'candidate_limited', false,
      'canonicalized', false
    )
  into v_total, v_result
  from page_payload;

  return coalesce(v_result, jsonb_build_object(
    'items', '[]'::jsonb,
    'total', 0,
    'limit', v_limit,
    'offset', v_offset,
    'has_more', false,
    'candidate_limited', false,
    'canonicalized', false
  ));
end;
$$;

revoke all on function public.search_catalog(text, text[], text, text, text, integer, text[], text[], text, text, integer, integer) from public;
grant execute on function public.search_catalog(text, text[], text, text, text, integer, text[], text[], text, text, integer, integer) to anon, authenticated;

comment on function public.search_catalog(text, text[], text, text, text, integer, text[], text[], text, text, integer, integer) is
'Ludograph v5.6.3: ricerca veloce candidate-first con canonicalizzazione solo sul set candidato già limitato; evita timeout e nasconde duplicati visibili store/enciclopedia.';

commit;

notify pgrst, 'reload schema';
