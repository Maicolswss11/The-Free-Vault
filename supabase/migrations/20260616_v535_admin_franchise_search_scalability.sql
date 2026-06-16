-- Ludograph v5.3.5 — scalable editorial/franchise candidate search
--
-- The universal catalog search was fixed in v5.3.4, but the admin franchise
-- picker still evaluated catalog_game_work_key() and catalog_game_work_json()
-- repeatedly over a catalog with hundreds of thousands of rows. This replaces
-- that path with the same hard candidate boundary used by search_catalog:
-- indexed discovery first, then grouping and JSON construction only over the
-- bounded candidate set.

begin;

create or replace function public.admin_search_franchise_candidates(
  p_query text,
  p_limit integer default 50
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
set statement_timeout = '12s'
as $$
declare
  v_q text := lower(trim(coalesce(p_query, '')));
  v_group_limit integer := greatest(1, least(coalesce(p_limit, 50), 50));
  v_candidate_limit integer;
  v_candidate_keys text[] := '{}'::text[];
  v_result jsonb;
begin
  if not public.is_admin() then
    raise exception 'Accesso amministratore richiesto' using errcode = '42501';
  end if;

  if v_q = '' then
    return '[]'::jsonb;
  end if;

  v_candidate_limit := least(1500, greatest(300, v_group_limit * 20));

  -- Phase 1: indexed substring search. The two branches remain separate so
  -- PostgreSQL can use the title and canonical-title trigram indexes directly.
  select coalesce(
    array_agg(
      limited.match_key
      order by limited.relevance_score desc,
        limited.sort_title,
        limited.release_date asc nulls last,
        limited.match_key
    ),
    '{}'::text[]
  )
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
    order by deduped.relevance_score desc,
      deduped.sort_title,
      deduped.release_date asc nulls last,
      deduped.match_key
    limit v_candidate_limit
  ) limited;

  -- Phase 2: fuzzy fallback only when substring matching returned nothing.
  if cardinality(v_candidate_keys) = 0 and char_length(v_q) >= 4 then
    select coalesce(
      array_agg(
        limited.match_key
        order by limited.relevance_score desc,
          limited.sort_title,
          limited.release_date asc nulls last,
          limited.match_key
      ),
      '{}'::text[]
    )
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
      order by deduped.relevance_score desc,
        deduped.sort_title,
        deduped.release_date asc nulls last,
        deduped.match_key
      limit least(v_candidate_limit, 750)
    ) limited;
  end if;

  if cardinality(v_candidate_keys) = 0 then
    return '[]'::jsonb;
  end if;

  with candidate_keys as materialized (
    select keys.match_key, keys.relevance_rank
    from unnest(v_candidate_keys) with ordinality
      as keys(match_key, relevance_rank)
  ), candidate_data as materialized (
    select
      cg.match_key,
      cg.master_game_id,
      cg.title,
      cg.canonical_title,
      cg.image_url,
      cg.release_date,
      cg.platforms,
      cg.stores,
      ck.relevance_rank,
      public.catalog_normalized_title(cg.title) as normalized_title,
      public.catalog_editorial_identity(cg.title, cg.image_url) as cover_identity,
      coalesce(g.game_type, 'unknown') as game_type,
      public.catalog_game_type_priority(g.game_type) as type_priority,
      case
        when nullif(g.metadata ->> 'parent_game', '') is not null then
          case
            when position(':' in (g.metadata ->> 'parent_game')) = 0
              then 'igdb:' || (g.metadata ->> 'parent_game')
            else g.metadata ->> 'parent_game'
          end
        when nullif(g.metadata ->> 'version_parent', '') is not null then
          case
            when position(':' in (g.metadata ->> 'version_parent')) = 0
              then 'igdb:' || (g.metadata ->> 'version_parent')
            else g.metadata ->> 'version_parent'
          end
        else null
      end as explicit_parent_id,
      (
        case when cg.release_date is not null then 1 else 0 end
        + case when nullif(cg.developer, '') is not null then 1 else 0 end
        + case when cardinality(cg.platforms) > 0 then 1 else 0 end
        + case when nullif(cg.description, '') is not null then 1 else 0 end
      ) as completeness_score
    from candidate_keys ck
    join public.catalog_games cg on cg.match_key = ck.match_key
    left join public.games g on g.id = cg.master_game_id
  ), title_stats as materialized (
    select
      cd.normalized_title,
      count(*) filter (
        where not public.catalog_is_subordinate_game_type(cd.game_type)
          and not public.catalog_is_separate_game_type(cd.game_type)
      )::integer as primary_count,
      min(cd.master_game_id) filter (
        where cd.master_game_id is not null
          and not public.catalog_is_subordinate_game_type(cd.game_type)
          and not public.catalog_is_separate_game_type(cd.game_type)
      ) as primary_master_id,
      bool_or(public.catalog_is_subordinate_game_type(cd.game_type)) as has_subordinates
    from candidate_data cd
    where cd.normalized_title <> ''
    group by cd.normalized_title
  ), keyed as materialized (
    select
      cd.*,
      case
        -- Explicit IGDB parent/version relationships always win.
        when cd.explicit_parent_id is not null
          then 'work:' || cd.explicit_parent_id

        -- The original record resolves to the same work as candidates that
        -- explicitly point to it through parent_game/version_parent.
        when cd.master_game_id is not null
          and exists (
            select 1
            from candidate_data child
            where child.explicit_parent_id = cd.master_game_id
          )
          then 'work:' || cd.master_game_id

        -- Remakes, remasters, DLC, bundles and expansions stay distinct works.
        when public.catalog_is_separate_game_type(cd.game_type)
          then coalesce(
            case when cd.cover_identity is not null then 'cover:' || cd.cover_identity end,
            'game:' || cd.match_key
          )

        -- Ports/forks/expanded games become subordinate versions of the sole
        -- primary work with the same normalized title, even if publisher or
        -- cover differs.
        when public.catalog_is_subordinate_game_type(cd.game_type)
          and ts.primary_count = 1
          and ts.primary_master_id is not null
          then 'work:' || ts.primary_master_id

        -- Make that sole primary resolve to the same work as its subordinate
        -- versions inside this bounded candidate set.
        when not public.catalog_is_subordinate_game_type(cd.game_type)
          and not public.catalog_is_separate_game_type(cd.game_type)
          and ts.primary_count = 1
          and ts.has_subordinates
          and cd.master_game_id = ts.primary_master_id
          then 'work:' || ts.primary_master_id

        -- Same normalized title and same normalized cover are one editorial
        -- work, independently of publisher/developer metadata.
        when cd.cover_identity is not null
          then 'cover:' || cd.cover_identity

        else 'game:' || cd.match_key
      end as group_key
    from candidate_data cd
    left join title_stats ts on ts.normalized_title = cd.normalized_title
  ), ranked as materialized (
    select
      k.*,
      row_number() over (
        partition by k.group_key
        order by
          k.type_priority,
          k.completeness_score desc,
          k.release_date asc nulls last,
          k.relevance_rank,
          k.match_key
      ) as variant_rank
    from keyed k
  ), group_summary as materialized (
    select
      r.group_key,
      min(r.relevance_rank) as relevance_rank,
      max(r.match_key) filter (where r.variant_rank = 1) as representative_key,
      count(*)::integer as variant_count
    from ranked r
    group by r.group_key
    order by min(r.relevance_rank), r.group_key
    limit v_group_limit
  ), selected_variants as materialized (
    select r.*
    from ranked r
    join group_summary gs on gs.group_key = r.group_key
  )
  select coalesce(
    jsonb_agg(
      public.catalog_game_card_json(representative)
      || jsonb_build_object(
        'editorial_identity', gs.group_key,
        'editorial_work_key', gs.group_key,
        'variant_count', gs.variant_count,
        'variant_keys', coalesce((
          select jsonb_agg(sv.match_key order by sv.variant_rank)
          from selected_variants sv
          where sv.group_key = gs.group_key
        ), '[]'::jsonb),
        'variants', coalesce((
          select jsonb_agg(
            public.catalog_game_card_json(variant_game)
            || jsonb_build_object(
              'variant_role', case
                when public.catalog_is_subordinate_game_type(sv.game_type)
                  then 'subordinate'
                else 'primary'
              end
            )
            order by sv.variant_rank
          )
          from selected_variants sv
          join public.catalog_games variant_game
            on variant_game.match_key = sv.match_key
          where sv.group_key = gs.group_key
        ), '[]'::jsonb),
        'platforms', to_jsonb(array(
          select distinct platform_name
          from selected_variants sv
          cross join lateral unnest(sv.platforms) as platform_name
          where sv.group_key = gs.group_key
          order by platform_name
        )),
        'stores', to_jsonb(array(
          select distinct store_name
          from selected_variants sv
          cross join lateral unnest(sv.stores) as store_name
          where sv.group_key = gs.group_key
          order by store_name
        ))
      )
      order by gs.relevance_rank, lower(representative.title), representative.match_key
    ),
    '[]'::jsonb
  )
  into v_result
  from group_summary gs
  join public.catalog_games representative
    on representative.match_key = gs.representative_key;

  return coalesce(v_result, '[]'::jsonb);
end;
$$;

revoke all on function public.admin_search_franchise_candidates(text, integer) from public;
grant execute on function public.admin_search_franchise_candidates(text, integer) to authenticated;

comment on function public.admin_search_franchise_candidates(text, integer) is
  'Ludograph v5.3.5: bounded candidate-first franchise/editorial search; groups ports and duplicate covers without catalog-wide work resolution.';

commit;

notify pgrst, 'reload schema';
