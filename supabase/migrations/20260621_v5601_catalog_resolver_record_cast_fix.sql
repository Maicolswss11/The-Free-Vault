-- Ludograph v5.6.1
-- Fix catalog_resolve_canonical_key: do not pass widened CTE records to
-- catalog_is_master_catalog_game(public.catalog_games). PostgreSQL cannot cast
-- a record containing extra derived columns back to public.catalog_games.

begin;

create or replace function public.catalog_resolve_canonical_key(p_key text)
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
  v_seed_type text := 'unknown';
  v_title_key text;
  v_year integer;
  v_work_key text;
  v_result text;
begin
  if v_key is null then
    return null;
  end if;

  select a.canonical_key into v_result
  from public.catalog_game_aliases a
  where a.alias_key = v_key
  order by a.confidence desc, a.updated_at desc
  limit 1;
  if v_result is not null then
    return v_result;
  end if;

  v_seed := public.catalog_resolve_seed_game(v_key);
  if v_seed.match_key is null then
    return null;
  end if;

  select coalesce(g.game_type, 'unknown') into v_seed_type
  from public.games g
  where g.id = v_seed.master_game_id
  limit 1;
  v_seed_type := coalesce(v_seed_type, 'unknown');

  if public.catalog_is_separate_game_type(v_seed_type) then
    return v_seed.match_key;
  end if;

  v_title_key := public.catalog_editorial_base_title(v_seed.title);
  v_year := coalesce(v_seed.release_year, extract(year from v_seed.release_date)::integer, public.catalog_title_year_hint(v_seed.title));
  v_work_key := public.catalog_work_key_for_game(v_seed);

  with candidates as materialized (
    select
      cg.match_key,
      cg.source_kind,
      cg.release_date,
      public.catalog_is_master_catalog_game(cg) as is_master,
      public.catalog_work_key_for_game(cg) as work_key,
      public.catalog_detail_media_count(cg.master_game_id) as media_count,
      public.catalog_review_anchor_count(cg.match_key, cg.canonical_id, cg.master_game_id) as review_count,
      public.catalog_library_anchor_count(cg.match_key, cg.canonical_id, cg.master_game_id) as library_count,
      (
        case when cg.release_date is not null then 1 else 0 end
        + case when nullif(cg.description, '') is not null then 1 else 0 end
        + case when nullif(cg.developer, '') is not null then 1 else 0 end
        + case when nullif(cg.publisher, '') is not null then 1 else 0 end
        + case when nullif(cg.image_url, '') is not null then 1 else 0 end
        + case when cardinality(coalesce(cg.platforms, '{}'::text[])) > 0 then 1 else 0 end
      ) as completeness_score
    from public.catalog_games cg
    left join public.games g on g.id = cg.master_game_id
    where not public.catalog_is_separate_game_type(coalesce(g.game_type, 'unknown'))
      and (
        public.catalog_work_key_for_game(cg) = v_work_key
        or (
          v_title_key <> ''
          and public.catalog_editorial_base_title(cg.title) = v_title_key
          and (
            v_year is null
            or coalesce(cg.release_year, extract(year from cg.release_date)::integer, public.catalog_title_year_hint(cg.title)) is null
            or abs(coalesce(cg.release_year, extract(year from cg.release_date)::integer, public.catalog_title_year_hint(cg.title)) - v_year) <= 2
          )
        )
      )
  )
  select c.match_key into v_result
  from candidates c
  order by
    c.review_count desc,
    c.library_count desc,
    c.media_count desc,
    c.is_master desc,
    case c.source_kind when 'master' then 0 when 'hybrid' then 1 when 'catalog' then 2 else 3 end,
    c.completeness_score desc,
    c.release_date asc nulls last,
    c.match_key
  limit 1;

  return coalesce(v_result, v_seed.match_key);
end;
$$;

revoke all on function public.catalog_resolve_canonical_key(text) from public;
grant execute on function public.catalog_resolve_canonical_key(text) to anon, authenticated, service_role;

comment on function public.catalog_resolve_canonical_key(text) is
'Ludograph v5.6.1: risolve chiavi legacy/store verso la scheda canonica senza cast record non validi.';

commit;

notify pgrst, 'reload schema';
