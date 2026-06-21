-- Ludograph v5.5.17 — varianti canoniche editoriali nell'editor franchise.
--
-- L'editor amministrativo dei franchise non deve selezionare record catalogo
-- grezzi: PC, Saturn, Steam/Epic e varianti tecniche della stessa opera devono
-- essere mostrati come una sola opera canonica, con le varianti espandibili.
-- La v5.5.17 gestisce i casi sporchi ancora separati: titoli con anno
-- tra parentesi, record senza data ma con lo stesso titolo base e porting
-- enciclopedici che devono restare varianti dell'opera principale.

begin;

create or replace function public.catalog_title_year_hint(p_title text)
returns integer
language sql
immutable
set search_path = ''
as $$
  select case
    when substring(coalesce(p_title, '') from '(^|[^0-9])((19|20)[0-9]{2})([^0-9]|$)') is null
      then null
    else nullif(regexp_replace(
      substring(coalesce(p_title, '') from '(^|[^0-9])((19|20)[0-9]{2})([^0-9]|$)'),
      '[^0-9]',
      '',
      'g'
    ), '')::integer
  end;
$$;

create or replace function public.catalog_editorial_base_title(p_title text)
returns text
language sql
immutable
set search_path = ''
as $$
  select public.catalog_normalized_title(
    regexp_replace(
      regexp_replace(
        regexp_replace(coalesce(trim(p_title), ''), '\s*[\[(](19|20)[0-9]{2}[\])]\s*$', '', 'i'),
        '\s+((19|20)[0-9]{2})\s*$', '', 'i'
      ),
      '\s+', ' ', 'g'
    )
  );
$$;

revoke all on function public.catalog_title_year_hint(text) from public;
revoke all on function public.catalog_editorial_base_title(text) from public;
grant execute on function public.catalog_title_year_hint(text) to anon, authenticated, service_role;
grant execute on function public.catalog_editorial_base_title(text) to anon, authenticated, service_role;

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

  v_candidate_limit := least(1500, greatest(300, v_group_limit * 24));

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
      cg.canonical_id,
      cg.master_game_id,
      cg.title,
      cg.canonical_title,
      cg.image_url,
      cg.release_date,
      coalesce(cg.release_year, extract(year from cg.release_date)::integer, public.catalog_title_year_hint(cg.title)) as release_year_value,
      cg.platforms,
      cg.stores,
      cg.source_kind,
      cg.developer,
      cg.publisher,
      ck.relevance_rank,
      public.catalog_editorial_base_title(cg.title) as normalized_title,
      public.catalog_editorial_identity(cg.title, cg.image_url) as cover_identity,
      public.catalog_cover_identity(cg.image_url) as cover_key,
      public.catalog_normalized_title(coalesce(nullif(cg.developer, ''), nullif(cg.publisher, ''), '')) as maker_key,
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
      ) as completeness_score,
      coalesce(public.catalog_detail_media_count(cg.master_game_id), 0) as media_count,
      public.catalog_review_anchor_count(cg.match_key, cg.canonical_id, cg.master_game_id) as review_count,
      public.catalog_library_anchor_count(cg.match_key, cg.canonical_id, cg.master_game_id) as library_count
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
  ), title_year_stats as materialized (
    select
      cd.normalized_title,
      min(cd.release_year_value)::integer as min_year,
      max(cd.release_year_value)::integer as max_year,
      count(*) filter (where cd.release_year_value is not null)::integer as known_year_count
    from candidate_data cd
    where cd.normalized_title <> ''
    group by cd.normalized_title
  ), clustered as materialized (
    select
      cd.*,
      coalesce(
        (
          select min(peer.release_year_value)::integer
          from candidate_data peer
          where peer.normalized_title = cd.normalized_title
            and peer.normalized_title <> ''
            and peer.release_year_value is not null
            and cd.release_year_value is not null
            and abs(peer.release_year_value - cd.release_year_value) <= 2
        ),
        case
          when tys.known_year_count > 0
            and tys.min_year is not null
            and tys.max_year is not null
            and abs(tys.max_year - tys.min_year) <= 2
            then tys.min_year
          else null
        end
      ) as canonical_year_anchor
    from candidate_data cd
    left join title_year_stats tys
      on tys.normalized_title = cd.normalized_title
  ), keyed as materialized (
    select
      cd.*,
      case
        when cd.explicit_parent_id is not null
          then 'work:' || cd.explicit_parent_id
        when cd.master_game_id is not null
          and exists (
            select 1
            from clustered child
            where child.explicit_parent_id = cd.master_game_id
          )
          then 'work:' || cd.master_game_id
        -- v5.5.17: stesso titolo editoriale base + anno compatibile = stessa
        -- opera canonica. Il titolo base rimuove suffissi come "(1998)"
        -- e i record senza anno seguono l'ancora annuale del gruppo.
        when cd.normalized_title <> ''
          and cd.canonical_year_anchor is not null
          then 'canonical:' || cd.normalized_title || ':' || cd.canonical_year_anchor::text
        when public.catalog_is_separate_game_type(cd.game_type)
          then coalesce(
            case when cd.cover_identity is not null then 'cover:' || cd.cover_identity end,
            'game:' || cd.match_key
          )
        when public.catalog_is_subordinate_game_type(cd.game_type)
          and ts.primary_count = 1
          and ts.primary_master_id is not null
          then 'work:' || ts.primary_master_id
        when not public.catalog_is_subordinate_game_type(cd.game_type)
          and not public.catalog_is_separate_game_type(cd.game_type)
          and ts.primary_count = 1
          and ts.has_subordinates
          and cd.master_game_id = ts.primary_master_id
          then 'work:' || ts.primary_master_id
        when cd.cover_identity is not null
          then 'cover:' || cd.cover_identity
        else 'game:' || cd.match_key
      end as group_key
    from clustered cd
    left join title_stats ts on ts.normalized_title = cd.normalized_title
  ), ranked as materialized (
    select
      k.*,
      row_number() over (
        partition by k.group_key
        order by
          k.review_count desc,
          k.library_count desc,
          k.media_count desc,
          k.type_priority,
          case k.source_kind when 'master' then 0 when 'hybrid' then 1 when 'catalog' then 2 else 3 end,
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
        'canonical_route_key', representative.match_key,
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
              'editorial_identity', gs.group_key,
              'editorial_work_key', gs.group_key,
              'canonical_route_key', representative.match_key,
              'variant_role', case
                when public.catalog_is_subordinate_game_type(sv.game_type)
                  then 'subordinate'
                when public.catalog_is_separate_game_type(sv.game_type)
                  then 'separate'
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
  'Ludograph v5.5.17: ricerca admin franchise su opere canoniche; collassa titoli con anno tra parentesi e varianti senza data sotto l’opera principale.';

commit;

notify pgrst, 'reload schema';
