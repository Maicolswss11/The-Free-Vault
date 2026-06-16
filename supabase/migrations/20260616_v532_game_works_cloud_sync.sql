-- Ludograph v5.3.2 — Canonical game works, subordinate ports and resilient cloud sync
--
-- 1. Treats ports/derived versions as subordinate records of one editorial work.
-- 2. Exposes variants inside franchise cards without deleting Master records.
-- 3. Removes the expensive per-row library resolver path that could time out.

begin;

-- ---------------------------------------------------------------------------
-- Cloud sync: fast key resolution and a bounded batch RPC
-- ---------------------------------------------------------------------------

create index if not exists catalog_games_canonical_id_idx
on public.catalog_games(canonical_id);

create index if not exists games_parent_game_metadata_idx
on public.games ((metadata ->> 'parent_game'))
where nullif(metadata ->> 'parent_game', '') is not null;

create index if not exists games_version_parent_metadata_idx
on public.games ((metadata ->> 'version_parent'))
where nullif(metadata ->> 'version_parent', '') is not null;

create or replace function public.resolve_master_game_id(p_key text)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_key text := nullif(trim(p_key), '');
  v_candidate text;
  v_result text;
begin
  if v_key is null then
    return null;
  end if;

  select a.game_id into v_result
  from public.game_key_aliases a
  where a.alias_key = v_key
  limit 1;
  if v_result is not null then return v_result; end if;

  if v_key like 'master:%' then
    v_candidate := substring(v_key from 8);
    select g.id into v_result from public.games g where g.id = v_candidate limit 1;
    if v_result is not null then return v_result; end if;
  end if;

  select g.id into v_result
  from public.games g
  where g.id = v_key
  limit 1;
  if v_result is not null then return v_result; end if;

  select cg.master_game_id into v_result
  from public.catalog_games cg
  where cg.match_key = v_key
  limit 1;
  if v_result is not null then return v_result; end if;

  select cg.master_game_id into v_result
  from public.catalog_games cg
  where cg.canonical_id = v_key
    and cg.master_game_id is not null
  order by cg.match_key
  limit 1;

  return v_result;
end;
$$;

revoke all on function public.resolve_master_game_id(text) from public;
grant execute on function public.resolve_master_game_id(text) to anon, authenticated, service_role;

create or replace function public.attach_master_game_id_from_key()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- An UPSERT may list game_key in the SET clause even when the value did not
  -- change. Do not resolve it again for every sign-in synchronization.
  if tg_op = 'UPDATE' and new.game_key is not distinct from old.game_key then
    return new;
  end if;

  if new.game_id is null and nullif(trim(new.game_key), '') is not null then
    new.game_id := public.resolve_master_game_id(new.game_key);
  end if;
  return new;
end;
$$;

revoke all on function public.attach_master_game_id_from_key() from public;

create or replace function public.sync_user_library_batch(p_rows jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
set statement_timeout = '20s'
as $$
declare
  v_user uuid := (select auth.uid());
  v_count integer := 0;
begin
  if v_user is null then
    raise exception 'Sessione richiesta' using errcode = '42501';
  end if;
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then
    raise exception 'p_rows deve essere un array JSON';
  end if;
  if jsonb_array_length(p_rows) > 250 then
    raise exception 'Massimo 250 elementi per batch';
  end if;

  insert into public.user_library(user_id, game_key, game_id, data, updated_at)
  select
    v_user,
    trim(r.game_key),
    public.resolve_master_game_id(trim(r.game_key)),
    coalesce(r.data, '{}'::jsonb),
    coalesce(r.updated_at, now())
  from jsonb_to_recordset(p_rows) as r(
    game_key text,
    data jsonb,
    updated_at timestamptz
  )
  where nullif(trim(r.game_key), '') is not null
  on conflict (user_id, game_key) do update set
    data = excluded.data,
    updated_at = excluded.updated_at,
    game_id = coalesce(public.user_library.game_id, excluded.game_id);

  get diagnostics v_count = row_count;
  return jsonb_build_object('status', 'ok', 'count', v_count);
end;
$$;

revoke all on function public.sync_user_library_batch(jsonb) from public;
grant execute on function public.sync_user_library_batch(jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- Canonical editorial works
-- ---------------------------------------------------------------------------

create or replace function public.catalog_normalized_title(p_title text)
returns text
language sql
immutable
set search_path = ''
as $$
  select lower(regexp_replace(
    replace(replace(replace(coalesce(trim(p_title), ''), '™', ''), '®', ''), '©', ''),
    '[^[:alnum:]]+',
    '',
    'g'
  ));
$$;

create or replace function public.catalog_cover_identity(p_image_url text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_cover text;
  v_filename text;
  v_token text;
begin
  v_cover := lower(split_part(coalesce(trim(p_image_url), ''), '?', 1));
  v_cover := regexp_replace(v_cover, '^https?://', '', 'i');
  v_cover := regexp_replace(v_cover, '/t_[^/]+/', '/', 'g');
  if v_cover = '' then return null; end if;

  v_filename := regexp_replace(v_cover, '^.*/', '');
  v_token := regexp_replace(v_filename, '\.(avif|gif|jpe?g|png|webp)$', '', 'i');

  -- IGDB keeps the same image_id while changing only host/preset/extension.
  if v_cover like '%images.igdb.com/%' and v_token ~ '^co[[:alnum:]_-]{3,}$' then
    return v_token;
  end if;
  if char_length(v_token) >= 12 then
    return v_token;
  end if;
  return md5(v_cover);
end;
$$;

create or replace function public.catalog_editorial_identity(
  p_title text,
  p_image_url text
)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when public.catalog_normalized_title(p_title) = ''
      or public.catalog_cover_identity(p_image_url) is null
      then null
    else md5(
      public.catalog_normalized_title(p_title)
      || '|'
      || public.catalog_cover_identity(p_image_url)
    )
  end;
$$;

create or replace function public.catalog_is_subordinate_game_type(p_game_type text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select lower(coalesce(p_game_type, 'unknown')) in ('port', 'fork', 'expanded_game');
$$;

create or replace function public.catalog_is_separate_game_type(p_game_type text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select lower(coalesce(p_game_type, 'unknown')) in (
    'remake', 'remaster', 'bundle', 'dlc_addon', 'expansion',
    'standalone_expansion', 'episode', 'pack', 'update'
  );
$$;

create index if not exists catalog_games_normalized_title_idx
on public.catalog_games (public.catalog_normalized_title(title));

create or replace function public.catalog_game_work_key(p_match_key text)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_base record;
  v_title text;
  v_parent text;
  v_master text;
  v_external text;
  v_primary_count integer := 0;
  v_primary_master text;
  v_has_subordinates boolean := false;
  v_identity text;
begin
  select
    cg.match_key,
    cg.title,
    cg.image_url,
    cg.master_game_id,
    coalesce(g.game_type, 'unknown') as game_type,
    nullif(g.metadata ->> 'parent_game', '') as parent_game,
    nullif(g.metadata ->> 'version_parent', '') as version_parent
  into v_base
  from public.catalog_games cg
  left join public.games g on g.id = cg.master_game_id
  where cg.match_key = trim(p_match_key)
  limit 1;

  if not found then return null; end if;

  v_title := public.catalog_normalized_title(v_base.title);
  v_master := nullif(v_base.master_game_id, '');
  v_parent := coalesce(v_base.parent_game, v_base.version_parent);

  if v_parent is not null then
    if position(':' in v_parent) = 0 then v_parent := 'igdb:' || v_parent; end if;
    return 'work:' || v_parent;
  end if;

  -- The original record must resolve to the same work as children that point to it.
  if v_master like 'igdb:%' then
    v_external := substring(v_master from 6);
    if exists (
      select 1
      from public.games child
      where child.metadata ->> 'parent_game' = v_external
         or child.metadata ->> 'version_parent' = v_external
    ) then
      return 'work:' || v_master;
    end if;
  end if;

  if v_title <> '' and not public.catalog_is_separate_game_type(v_base.game_type) then
    select
      count(*)::integer,
      min(cg.master_game_id)
    into v_primary_count, v_primary_master
    from public.catalog_games cg
    join public.games g on g.id = cg.master_game_id
    where cg.source_kind = 'master'
      and public.catalog_normalized_title(cg.title) = v_title
      and not public.catalog_is_subordinate_game_type(g.game_type)
      and not public.catalog_is_separate_game_type(g.game_type);

    select exists (
      select 1
      from public.catalog_games cg
      join public.games g on g.id = cg.master_game_id
      where cg.source_kind = 'master'
        and public.catalog_normalized_title(cg.title) = v_title
        and public.catalog_is_subordinate_game_type(g.game_type)
    ) into v_has_subordinates;

    if v_primary_count = 1
      and v_primary_master is not null
      and (
        public.catalog_is_subordinate_game_type(v_base.game_type)
        or v_master = v_primary_master
        or v_has_subordinates
      )
    then
      return 'work:' || v_primary_master;
    end if;
  end if;

  v_identity := public.catalog_editorial_identity(v_base.title, v_base.image_url);
  return coalesce('cover:' || v_identity, 'game:' || v_base.match_key);
end;
$$;

revoke all on function public.catalog_normalized_title(text) from public;
revoke all on function public.catalog_cover_identity(text) from public;
revoke all on function public.catalog_is_subordinate_game_type(text) from public;
revoke all on function public.catalog_is_separate_game_type(text) from public;
revoke all on function public.catalog_game_work_key(text) from public;
grant execute on function public.catalog_normalized_title(text) to anon, authenticated, service_role;
grant execute on function public.catalog_cover_identity(text) to anon, authenticated, service_role;
grant execute on function public.catalog_is_subordinate_game_type(text) to anon, authenticated, service_role;
grant execute on function public.catalog_is_separate_game_type(text) to anon, authenticated, service_role;
grant execute on function public.catalog_game_work_key(text) to anon, authenticated, service_role;

create or replace function public.catalog_game_work_members(p_match_key text)
returns table(match_key text)
language sql
stable
security definer
set search_path = ''
set statement_timeout = '8s'
as $$
  with base as materialized (
    select
      cg.match_key,
      public.catalog_normalized_title(cg.title) as normalized_title,
      public.catalog_game_work_key(cg.match_key) as work_key,
      case
        when public.catalog_game_work_key(cg.match_key) like 'work:%'
          then substring(public.catalog_game_work_key(cg.match_key) from 6)
        else null
      end as root_master_id
    from public.catalog_games cg
    where cg.match_key = trim(p_match_key)
    limit 1
  ), candidates as materialized (
    select cg.match_key
    from public.catalog_games cg
    cross join base b
    where public.catalog_normalized_title(cg.title) = b.normalized_title

    union

    select cg.match_key
    from public.catalog_games cg
    cross join base b
    where b.root_master_id is not null
      and cg.master_game_id = b.root_master_id

    union

    select cg.match_key
    from public.catalog_games cg
    join public.games g on g.id = cg.master_game_id
    cross join base b
    where b.root_master_id like 'igdb:%'
      and (
        g.metadata ->> 'parent_game' = substring(b.root_master_id from 6)
        or g.metadata ->> 'version_parent' = substring(b.root_master_id from 6)
      )
  )
  select distinct c.match_key
  from candidates c
  cross join base b
  where public.catalog_game_work_key(c.match_key) = b.work_key
  order by c.match_key;
$$;

revoke all on function public.catalog_game_work_members(text) from public;
grant execute on function public.catalog_game_work_members(text) to anon, authenticated, service_role;

create or replace function public.catalog_game_work_json(p_match_key text)
returns jsonb
language sql
stable
security definer
set search_path = ''
set statement_timeout = '8s'
as $$
  with members as materialized (
    select
      cg.match_key,
      coalesce(g.game_type, 'unknown') as resolved_game_type,
      public.catalog_game_type_priority(g.game_type) as type_priority,
      (
        case when cg.release_date is not null then 1 else 0 end
        + case when nullif(cg.developer, '') is not null then 1 else 0 end
        + case when cardinality(cg.platforms) > 0 then 1 else 0 end
        + case when nullif(cg.description, '') is not null then 1 else 0 end
      ) as completeness_score,
      cg.release_date
    from public.catalog_game_work_members(p_match_key) member
    join public.catalog_games cg on cg.match_key = member.match_key
    left join public.games g on g.id = cg.master_game_id
  ), ranked as (
    select
      members.*,
      row_number() over (
        order by type_priority, completeness_score desc,
          release_date asc nulls last, match_key
      ) as variant_rank
    from members
  )
  select jsonb_build_object(
    'editorial_work_key', public.catalog_game_work_key(p_match_key),
    'variant_count', count(*)::integer,
    'variant_keys', coalesce(jsonb_agg(ranked.match_key order by ranked.variant_rank), '[]'::jsonb),
    'variants', coalesce(jsonb_agg(
      public.catalog_game_card_json(variant_game)
      || jsonb_build_object(
        'variant_role', case
          when public.catalog_is_subordinate_game_type(ranked.resolved_game_type) then 'subordinate'
          else 'primary'
        end
      )
      order by ranked.variant_rank
    ), '[]'::jsonb),
    'platforms', to_jsonb(array(
      select distinct platform
      from ranked r
      join public.catalog_games member_game on member_game.match_key = r.match_key
      cross join lateral unnest(member_game.platforms) platform
      order by platform
    )),
    'stores', to_jsonb(array(
      select distinct store_name
      from ranked r
      join public.catalog_games member_game on member_game.match_key = r.match_key
      cross join lateral unnest(member_game.stores) store_name
      order by store_name
    ))
  )
  from ranked
  join public.catalog_games variant_game on variant_game.match_key = ranked.match_key;
$$;

revoke all on function public.catalog_game_work_json(text) from public;
grant execute on function public.catalog_game_work_json(text) to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Grouped admin search
-- ---------------------------------------------------------------------------

create or replace function public.admin_search_franchise_candidates(
  p_query text,
  p_limit integer default 50
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
set statement_timeout = '20s'
as $$
declare
  v_result jsonb;
begin
  if not public.is_admin() then
    raise exception 'Accesso amministratore richiesto' using errcode = '42501';
  end if;

  with params as (
    select
      lower(trim(coalesce(p_query, ''))) as q,
      greatest(1, least(coalesce(p_limit, 50), 50)) as group_limit
  ), candidate_keys as materialized (
    select
      cg.match_key,
      public.catalog_game_work_key(cg.match_key) as group_key,
      case
        when lower(cg.title) = p.q then 100
        when lower(cg.canonical_title) = p.q then 95
        when lower(cg.title) like p.q || '%' then 80
        when lower(cg.canonical_title) like p.q || '%' then 75
        else 50
      end as relevance_score,
      public.catalog_game_type_priority(g.game_type) as type_priority,
      (
        case when cg.release_date is not null then 1 else 0 end
        + case when nullif(cg.developer, '') is not null then 1 else 0 end
        + case when cardinality(cg.platforms) > 0 then 1 else 0 end
        + case when nullif(cg.description, '') is not null then 1 else 0 end
      ) as completeness_score
    from public.catalog_games cg
    cross join params p
    left join public.games g on g.id = cg.master_game_id
    where p.q <> ''
      and lower(cg.title) like '%' || p.q || '%'
    order by relevance_score desc, lower(cg.title), cg.match_key
    limit 1000
  ), ranked as (
    select
      ck.*,
      row_number() over (
        partition by ck.group_key
        order by ck.type_priority, ck.completeness_score desc,
          (select release_date from public.catalog_games where match_key = ck.match_key) asc nulls last,
          ck.match_key
      ) as group_rank
    from candidate_keys ck
  ), groups as (
    select
      group_key,
      max(relevance_score) as relevance_score,
      max(match_key) filter (where group_rank = 1) as representative_key,
      count(*)::integer as variant_count
    from ranked
    group by group_key
    order by max(relevance_score) desc, group_key
    limit (select group_limit from params)
  )
  select coalesce(jsonb_agg(
    public.catalog_game_card_json(representative)
    || public.catalog_game_work_json(representative.match_key)
    || jsonb_build_object(
      'editorial_identity', groups.group_key,
      'editorial_work_key', groups.group_key
    )
    order by groups.relevance_score desc, lower(representative.title), representative.match_key
  ), '[]'::jsonb)
  into v_result
  from groups
  join public.catalog_games representative on representative.match_key = groups.representative_key;

  return coalesce(v_result, '[]'::jsonb);
end;
$$;

revoke all on function public.admin_search_franchise_candidates(text, integer) from public;
grant execute on function public.admin_search_franchise_candidates(text, integer) to authenticated;

-- ---------------------------------------------------------------------------
-- Franchise payloads now expose subordinate versions under one work
-- ---------------------------------------------------------------------------

create or replace function public.franchise_detail(p_slug text)
returns jsonb
language sql
stable
security definer
set search_path = ''
set statement_timeout = '15s'
as $$
  with selected as materialized (
    select f.*
    from public.franchises f
    where f.slug = lower(trim(p_slug))
      and f.status = 'published'
    limit 1
  )
  select case when not exists (select 1 from selected) then null else jsonb_build_object(
    'franchise', (
      select jsonb_build_object(
        'id', f.id,
        'slug', f.slug,
        'name', f.name,
        'description', f.description,
        'hero_image_url', f.hero_image_url,
        'status', f.status,
        'updated_at', f.updated_at
      ) from selected f
    ),
    'tracks', coalesce((select public.franchise_tracks_json(f.id) from selected f), '[]'::jsonb),
    'relations', coalesce((select public.franchise_game_relations_json(f.id) from selected f), '[]'::jsonb),
    'games', coalesce((
      select jsonb_agg(
        public.catalog_game_card_json(cg)
        || public.catalog_game_work_json(fg.game_key)
        || jsonb_build_object(
          'game_id', fg.game_id,
          'relation_type', fg.relation_type,
          'release_order', fg.release_order,
          'narrative_order', fg.narrative_order,
          'franchise_note', fg.note,
          'track_memberships', coalesce((
            select jsonb_agg(jsonb_build_object(
              'track_key', ft.track_key,
              'track_name', ft.name,
              'track_type', ft.track_type,
              'narrative_order', fgt.narrative_order,
              'release_order', fgt.release_order,
              'canon_status', fgt.canon_status,
              'note', fgt.note
            ) order by ft.sort_order, fgt.narrative_order nulls last, ft.track_key)
            from public.franchise_game_tracks fgt
            join public.franchise_tracks ft on ft.id = fgt.track_id
            where fgt.franchise_id = fg.franchise_id and fgt.game_key = fg.game_key
          ), '[]'::jsonb)
        )
        order by fg.release_order, lower(cg.title), cg.match_key
      )
      from selected f
      join public.franchise_games fg on fg.franchise_id = f.id
      join public.catalog_games cg on cg.match_key = fg.game_key
    ), '[]'::jsonb)
  ) end;
$$;

create or replace function public.admin_get_franchise(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  result jsonb;
begin
  if not public.is_admin() then
    raise exception 'Accesso amministratore richiesto' using errcode = '42501';
  end if;
  select jsonb_build_object(
    'franchise', jsonb_build_object(
      'id', f.id, 'slug', f.slug, 'name', f.name, 'description', f.description,
      'hero_image_url', f.hero_image_url, 'status', f.status,
      'created_at', f.created_at, 'updated_at', f.updated_at
    ),
    'tracks', public.franchise_tracks_json(f.id),
    'relations', public.franchise_game_relations_json(f.id),
    'games', coalesce((
      select jsonb_agg(
        public.catalog_game_card_json(cg)
        || public.catalog_game_work_json(fg.game_key)
        || jsonb_build_object(
          'game_id', fg.game_id,
          'relation_type', fg.relation_type,
          'release_order', fg.release_order,
          'narrative_order', fg.narrative_order,
          'franchise_note', fg.note,
          'track_memberships', coalesce((
            select jsonb_agg(jsonb_build_object(
              'track_key', ft.track_key,
              'track_name', ft.name,
              'track_type', ft.track_type,
              'narrative_order', fgt.narrative_order,
              'release_order', fgt.release_order,
              'canon_status', fgt.canon_status,
              'note', fgt.note
            ) order by ft.sort_order, fgt.narrative_order nulls last, ft.track_key)
            from public.franchise_game_tracks fgt
            join public.franchise_tracks ft on ft.id = fgt.track_id
            where fgt.franchise_id = fg.franchise_id and fgt.game_key = fg.game_key
          ), '[]'::jsonb)
        ) order by fg.release_order, lower(cg.title), cg.match_key
      )
      from public.franchise_games fg
      join public.catalog_games cg on cg.match_key = fg.game_key
      where fg.franchise_id = f.id
    ), '[]'::jsonb)
  ) into result
  from public.franchises f
  where f.id = p_id;
  return result;
end;
$$;

-- ---------------------------------------------------------------------------
-- Consolidate duplicate links using the new work key
-- ---------------------------------------------------------------------------

create or replace function public.consolidate_franchise_variants_internal(p_franchise_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_duplicate record;
  v_merged integer := 0;
begin
  if not exists (select 1 from public.franchises where id = p_franchise_id) then
    raise exception 'Franchise non trovato';
  end if;

  for v_duplicate in
    with ranked as (
      select
        fg.game_key,
        public.catalog_game_work_key(fg.game_key) as work_key,
        first_value(fg.game_key) over (
          partition by public.catalog_game_work_key(fg.game_key)
          order by public.catalog_game_type_priority(g.game_type),
            (case when cg.release_date is not null then 1 else 0 end
             + case when nullif(cg.developer, '') is not null then 1 else 0 end
             + case when cardinality(cg.platforms) > 0 then 1 else 0 end) desc,
            cg.release_date asc nulls last,
            fg.release_order asc,
            fg.game_key
        ) as keeper_key,
        row_number() over (
          partition by public.catalog_game_work_key(fg.game_key)
          order by public.catalog_game_type_priority(g.game_type),
            (case when cg.release_date is not null then 1 else 0 end
             + case when nullif(cg.developer, '') is not null then 1 else 0 end
             + case when cardinality(cg.platforms) > 0 then 1 else 0 end) desc,
            cg.release_date asc nulls last,
            fg.release_order asc,
            fg.game_key
        ) as duplicate_rank
      from public.franchise_games fg
      join public.catalog_games cg on cg.match_key = fg.game_key
      left join public.games g on g.id = cg.master_game_id
      where fg.franchise_id = p_franchise_id
        and public.catalog_game_work_key(fg.game_key) is not null
    )
    select game_key as duplicate_key, keeper_key
    from ranked
    where duplicate_rank > 1
  loop
    update public.franchise_games keeper
    set
      release_order = least(keeper.release_order, duplicate.release_order),
      narrative_order = coalesce(keeper.narrative_order, duplicate.narrative_order),
      note = coalesce(keeper.note, duplicate.note),
      updated_at = now()
    from public.franchise_games duplicate
    where keeper.franchise_id = p_franchise_id
      and keeper.game_key = v_duplicate.keeper_key
      and duplicate.franchise_id = p_franchise_id
      and duplicate.game_key = v_duplicate.duplicate_key;

    insert into public.franchise_game_tracks(
      track_id, franchise_id, game_key, game_id,
      narrative_order, release_order, canon_status, note
    )
    select
      track_id,
      franchise_id,
      v_duplicate.keeper_key,
      public.resolve_master_game_id(v_duplicate.keeper_key),
      narrative_order,
      release_order,
      canon_status,
      note
    from public.franchise_game_tracks
    where franchise_id = p_franchise_id
      and game_key = v_duplicate.duplicate_key
    on conflict (track_id, game_key) do update set
      narrative_order = coalesce(public.franchise_game_tracks.narrative_order, excluded.narrative_order),
      release_order = coalesce(public.franchise_game_tracks.release_order, excluded.release_order),
      canon_status = case
        when public.franchise_game_tracks.canon_status = 'unknown' then excluded.canon_status
        else public.franchise_game_tracks.canon_status
      end,
      note = coalesce(public.franchise_game_tracks.note, excluded.note),
      updated_at = now();

    delete from public.franchise_game_tracks
    where franchise_id = p_franchise_id
      and game_key = v_duplicate.duplicate_key;

    insert into public.franchise_game_relations(
      franchise_id, source_game_key, target_game_key, relation_type, note
    )
    select
      franchise_id,
      case when source_game_key = v_duplicate.duplicate_key then v_duplicate.keeper_key else source_game_key end,
      case when target_game_key = v_duplicate.duplicate_key then v_duplicate.keeper_key else target_game_key end,
      relation_type,
      note
    from public.franchise_game_relations
    where franchise_id = p_franchise_id
      and (source_game_key = v_duplicate.duplicate_key or target_game_key = v_duplicate.duplicate_key)
      and (case when source_game_key = v_duplicate.duplicate_key then v_duplicate.keeper_key else source_game_key end)
        <> (case when target_game_key = v_duplicate.duplicate_key then v_duplicate.keeper_key else target_game_key end)
    on conflict (franchise_id, source_game_key, target_game_key, relation_type) do update set
      note = coalesce(public.franchise_game_relations.note, excluded.note),
      updated_at = now();

    delete from public.franchise_game_relations
    where franchise_id = p_franchise_id
      and (source_game_key = v_duplicate.duplicate_key or target_game_key = v_duplicate.duplicate_key);

    delete from public.franchise_games
    where franchise_id = p_franchise_id
      and game_key = v_duplicate.duplicate_key;

    v_merged := v_merged + 1;
  end loop;

  return jsonb_build_object(
    'merged', v_merged,
    'franchise_id', p_franchise_id,
    'deduplication', 'canonical_work'
  );
end;
$$;

revoke all on function public.consolidate_franchise_variants_internal(uuid) from public;

-- Consolidate existing franchise links once. Master records are never deleted.
do $$
declare
  v_franchise record;
begin
  for v_franchise in select id from public.franchises loop
    perform public.consolidate_franchise_variants_internal(v_franchise.id);
  end loop;
end;
$$;

comment on function public.catalog_game_work_key(text) is
'Canonical editorial work key. Ports/forks/expanded versions are subordinate to one primary work; remakes and remasters remain separate.';
comment on function public.catalog_game_work_json(text) is
'Returns the primary work with its subordinate variants, platforms and stores.';
comment on function public.sync_user_library_batch(jsonb) is
'Bounded authenticated user-library UPSERT that avoids repeated game-key resolution during sign-in.';

commit;

notify pgrst, 'reload schema';
