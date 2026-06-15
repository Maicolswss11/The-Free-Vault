-- The Free Vault v5.2 — Franchise Graph & Editorial Import
-- Percorsi narrativi, sottosaghe, relazioni e import/export JSON controllato.

begin;

create table if not exists public.franchise_tracks (
  id uuid primary key default gen_random_uuid(),
  franchise_id uuid not null references public.franchises(id) on delete cascade,
  parent_id uuid references public.franchise_tracks(id) on delete cascade,
  track_key text not null check (track_key ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' and char_length(track_key) between 2 and 100),
  name text not null check (char_length(name) between 2 and 160),
  track_type text not null default 'continuity'
    check (track_type in ('continuity', 'timeline', 'subseries', 'story_arc', 'anthology', 'remake_line', 'collection', 'other')),
  description text check (description is null or char_length(description) <= 3000),
  sort_order integer not null default 1 check (sort_order > 0),
  is_primary boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(franchise_id, track_key)
);

create table if not exists public.franchise_game_tracks (
  track_id uuid not null references public.franchise_tracks(id) on delete cascade,
  franchise_id uuid not null references public.franchises(id) on delete cascade,
  game_key text not null references public.catalog_games(match_key) on delete cascade,
  game_id text references public.games(id) on delete set null,
  narrative_order integer check (narrative_order is null or narrative_order > 0),
  release_order integer check (release_order is null or release_order > 0),
  canon_status text not null default 'unknown'
    check (canon_status in ('canon', 'alternate_canon', 'reimagining', 'non_canon', 'unknown', 'editorial_only')),
  note text check (note is null or char_length(note) <= 1500),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (track_id, game_key)
);

create table if not exists public.franchise_game_relations (
  franchise_id uuid not null references public.franchises(id) on delete cascade,
  source_game_key text not null references public.catalog_games(match_key) on delete cascade,
  target_game_key text not null references public.catalog_games(match_key) on delete cascade,
  source_game_id text references public.games(id) on delete set null,
  target_game_id text references public.games(id) on delete set null,
  relation_type text not null
    check (relation_type in ('sequel_to', 'prequel_to', 'remake_of', 'remaster_of', 'reimagines', 'alternate_version_of', 'parallel_to', 'expansion_of', 'collection_of', 'contains', 'spiritual_successor_to', 'related_to')),
  note text check (note is null or char_length(note) <= 1500),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (franchise_id, source_game_key, target_game_key, relation_type),
  check (source_game_key <> target_game_key)
);

create index if not exists franchise_tracks_franchise_sort_idx
on public.franchise_tracks(franchise_id, sort_order, track_key);

create index if not exists franchise_tracks_parent_idx
on public.franchise_tracks(parent_id);

create index if not exists franchise_game_tracks_franchise_idx
on public.franchise_game_tracks(franchise_id, track_id, narrative_order, game_key);

create index if not exists franchise_game_tracks_game_key_idx
on public.franchise_game_tracks(game_key);

create index if not exists franchise_game_relations_source_idx
on public.franchise_game_relations(franchise_id, source_game_key);

create index if not exists franchise_game_relations_target_idx
on public.franchise_game_relations(franchise_id, target_game_key);

alter table public.franchise_tracks enable row level security;
alter table public.franchise_game_tracks enable row level security;
alter table public.franchise_game_relations enable row level security;

revoke all on public.franchise_tracks from anon, authenticated;
revoke all on public.franchise_game_tracks from anon, authenticated;
revoke all on public.franchise_game_relations from anon, authenticated;

grant select, insert, update, delete on public.franchise_tracks to service_role;
grant select, insert, update, delete on public.franchise_game_tracks to service_role;
grant select, insert, update, delete on public.franchise_game_relations to service_role;

drop trigger if exists franchise_tracks_touch_updated_at on public.franchise_tracks;
create trigger franchise_tracks_touch_updated_at
before update on public.franchise_tracks
for each row execute function public.touch_editorial_updated_at();

drop trigger if exists franchise_game_tracks_touch_updated_at on public.franchise_game_tracks;
create trigger franchise_game_tracks_touch_updated_at
before update on public.franchise_game_tracks
for each row execute function public.touch_editorial_updated_at();

drop trigger if exists franchise_game_relations_touch_updated_at on public.franchise_game_relations;
create trigger franchise_game_relations_touch_updated_at
before update on public.franchise_game_relations
for each row execute function public.touch_editorial_updated_at();

create or replace function public.attach_franchise_game_track_master_game_id()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.game_id is null and nullif(trim(new.game_key), '') is not null then
    new.game_id := public.resolve_master_game_id(new.game_key);
  end if;
  return new;
end;
$$;

create or replace function public.attach_franchise_game_relation_master_ids()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.source_game_id is null and nullif(trim(new.source_game_key), '') is not null then
    new.source_game_id := public.resolve_master_game_id(new.source_game_key);
  end if;
  if new.target_game_id is null and nullif(trim(new.target_game_key), '') is not null then
    new.target_game_id := public.resolve_master_game_id(new.target_game_key);
  end if;
  return new;
end;
$$;

revoke all on function public.attach_franchise_game_track_master_game_id() from public;
revoke all on function public.attach_franchise_game_relation_master_ids() from public;

drop trigger if exists franchise_game_tracks_attach_master_game on public.franchise_game_tracks;
create trigger franchise_game_tracks_attach_master_game
before insert or update of game_key on public.franchise_game_tracks
for each row execute function public.attach_franchise_game_track_master_game_id();

drop trigger if exists franchise_game_relations_attach_master_games on public.franchise_game_relations;
create trigger franchise_game_relations_attach_master_games
before insert or update of source_game_key, target_game_key on public.franchise_game_relations
for each row execute function public.attach_franchise_game_relation_master_ids();

create or replace function public.franchise_tracks_json(p_franchise_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', t.id,
      'track_key', t.track_key,
      'name', t.name,
      'track_type', t.track_type,
      'description', t.description,
      'sort_order', t.sort_order,
      'is_primary', t.is_primary,
      'parent_track_key', parent.track_key
    ) order by t.sort_order, lower(t.name), t.track_key
  ), '[]'::jsonb)
  from public.franchise_tracks t
  left join public.franchise_tracks parent on parent.id = t.parent_id
  where t.franchise_id = p_franchise_id;
$$;

create or replace function public.franchise_game_relations_json(p_franchise_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'source_game_key', r.source_game_key,
      'target_game_key', r.target_game_key,
      'source_game_id', r.source_game_id,
      'target_game_id', r.target_game_id,
      'relation_type', r.relation_type,
      'note', r.note
    ) order by r.source_game_key, r.relation_type, r.target_game_key
  ), '[]'::jsonb)
  from public.franchise_game_relations r
  where r.franchise_id = p_franchise_id;
$$;

revoke all on function public.franchise_tracks_json(uuid) from public;
revoke all on function public.franchise_game_relations_json(uuid) from public;
grant execute on function public.franchise_tracks_json(uuid) to anon, authenticated, service_role;
grant execute on function public.franchise_game_relations_json(uuid) to anon, authenticated, service_role;

create or replace function public.franchise_detail(p_slug text)
returns jsonb
language sql
stable
security definer
set search_path = ''
set statement_timeout = '10s'
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

create or replace function public.admin_export_franchise_editorial(p_franchise_id uuid)
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
  if not exists (select 1 from public.franchises where id = p_franchise_id) then
    raise exception 'Franchise non trovato';
  end if;

  select jsonb_build_object(
    'schema_version', 'tfv-franchise-editorial-v2',
    'franchise', jsonb_build_object(
      'id', f.id,
      'slug', f.slug,
      'name', f.name,
      'status', f.status,
      'description', f.description
    ),
    'instructions', jsonb_build_object(
      'edit_only', jsonb_build_array('tracks', 'games.editorial', 'games.track_memberships', 'relations'),
      'do_not_change', jsonb_build_array('franchise.id', 'games.game_key', 'games.game_id', 'games.title'),
      'return_valid_json_only', true
    ),
    'allowed_values', jsonb_build_object(
      'entry_type', jsonb_build_array('main', 'spin_off', 'remake', 'remaster', 'dlc', 'expansion', 'other'),
      'track_type', jsonb_build_array('continuity', 'timeline', 'subseries', 'story_arc', 'anthology', 'remake_line', 'collection', 'other'),
      'canon_status', jsonb_build_array('canon', 'alternate_canon', 'reimagining', 'non_canon', 'unknown', 'editorial_only'),
      'relation_type', jsonb_build_array('sequel_to', 'prequel_to', 'remake_of', 'remaster_of', 'reimagines', 'alternate_version_of', 'parallel_to', 'expansion_of', 'collection_of', 'contains', 'spiritual_successor_to', 'related_to')
    ),
    'tracks', public.franchise_tracks_json(f.id),
    'relations', public.franchise_game_relations_json(f.id),
    'games', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'game_key', fg.game_key,
          'game_id', fg.game_id,
          'title', cg.title,
          'release_date', cg.release_date,
          'release_year', cg.release_year,
          'developer', cg.developer,
          'publisher', cg.publisher,
          'platforms', cg.platforms,
          'stores', cg.stores,
          'category_group', cg.category_group,
          'current', jsonb_build_object(
            'entry_type', fg.relation_type,
            'release_order', fg.release_order,
            'narrative_order', fg.narrative_order,
            'note', fg.note
          ),
          'editorial', jsonb_build_object(
            'entry_type', fg.relation_type,
            'release_order', fg.release_order,
            'narrative_order', fg.narrative_order,
            'canon_status', coalesce((
              select fgt.canon_status
              from public.franchise_game_tracks fgt
              where fgt.franchise_id = fg.franchise_id and fgt.game_key = fg.game_key
              order by case fgt.canon_status when 'canon' then 0 when 'alternate_canon' then 1 when 'reimagining' then 2 else 3 end
              limit 1
            ), 'unknown'),
            'notes', fg.note
          ),
          'track_memberships', coalesce((
            select jsonb_agg(jsonb_build_object(
              'track_key', ft.track_key,
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
  where f.id = p_franchise_id;

  return result;
end;
$$;

create or replace function public.admin_import_franchise_editorial(
  p_franchise_id uuid,
  p_payload jsonb,
  p_dry_run boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_schema text := coalesce(p_payload ->> 'schema_version', '');
  v_payload_franchise uuid;
  v_game jsonb;
  v_track jsonb;
  v_membership jsonb;
  v_relation jsonb;
  v_game_key text;
  v_track_key text;
  v_parent_key text;
  v_track_id uuid;
  v_source_key text;
  v_target_key text;
  v_games integer := 0;
  v_tracks integer := 0;
  v_memberships integer := 0;
  v_relations integer := 0;
  v_release_order integer;
  v_narrative_order integer;
  v_relation_type text;
  v_note text;
begin
  if not public.is_admin() then
    raise exception 'Accesso amministratore richiesto' using errcode = '42501';
  end if;
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'JSON editoriale non valido';
  end if;
  if v_schema <> 'tfv-franchise-editorial-v2' then
    raise exception 'schema_version non supportata: %', v_schema;
  end if;
  if not exists (select 1 from public.franchises where id = p_franchise_id) then
    raise exception 'Franchise non trovato';
  end if;
  if nullif(p_payload #>> '{franchise,id}', '') is not null then
    v_payload_franchise := (p_payload #>> '{franchise,id}')::uuid;
    if v_payload_franchise <> p_franchise_id then
      raise exception 'Il JSON appartiene a un altro franchise';
    end if;
  end if;
  if jsonb_typeof(coalesce(p_payload -> 'games', '[]'::jsonb)) <> 'array' then
    raise exception 'games deve essere un array';
  end if;
  if jsonb_typeof(coalesce(p_payload -> 'tracks', '[]'::jsonb)) <> 'array' then
    raise exception 'tracks deve essere un array';
  end if;
  if jsonb_typeof(coalesce(p_payload -> 'relations', '[]'::jsonb)) <> 'array' then
    raise exception 'relations deve essere un array';
  end if;

  for v_game in select value from jsonb_array_elements(coalesce(p_payload -> 'games', '[]'::jsonb)) loop
    v_game_key := trim(coalesce(v_game ->> 'game_key', v_game ->> 'match_key', ''));
    if v_game_key = '' then
      raise exception 'Un gioco del JSON non contiene game_key';
    end if;
    if not exists (select 1 from public.franchise_games fg where fg.franchise_id = p_franchise_id and fg.game_key = v_game_key) then
      raise exception 'Il gioco % non appartiene a questo franchise', v_game_key;
    end if;
    v_games := v_games + 1;
  end loop;

  for v_track in select value from jsonb_array_elements(coalesce(p_payload -> 'tracks', '[]'::jsonb)) loop
    v_track_key := trim(coalesce(v_track ->> 'track_key', ''));
    if v_track_key = '' or v_track_key !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' then
      raise exception 'track_key non valido: %', v_track_key;
    end if;
    if coalesce(v_track ->> 'track_type', 'continuity') not in ('continuity', 'timeline', 'subseries', 'story_arc', 'anthology', 'remake_line', 'collection', 'other') then
      raise exception 'track_type non valido per %', v_track_key;
    end if;
    v_tracks := v_tracks + 1;
  end loop;

  for v_relation in select value from jsonb_array_elements(coalesce(p_payload -> 'relations', '[]'::jsonb)) loop
    v_source_key := trim(coalesce(v_relation ->> 'source_game_key', ''));
    v_target_key := trim(coalesce(v_relation ->> 'target_game_key', ''));
    if v_source_key = '' or v_target_key = '' then
      raise exception 'Relazione con game_key mancante';
    end if;
    if v_source_key = v_target_key then
      raise exception 'Una relazione non può collegare un gioco a se stesso';
    end if;
    if coalesce(v_relation ->> 'relation_type', '') not in ('sequel_to', 'prequel_to', 'remake_of', 'remaster_of', 'reimagines', 'alternate_version_of', 'parallel_to', 'expansion_of', 'collection_of', 'contains', 'spiritual_successor_to', 'related_to') then
      raise exception 'relation_type non valido';
    end if;
    if not exists (select 1 from public.franchise_games where franchise_id = p_franchise_id and game_key = v_source_key) then
      raise exception 'Relazione con gioco sorgente esterno al franchise: %', v_source_key;
    end if;
    if not exists (select 1 from public.franchise_games where franchise_id = p_franchise_id and game_key = v_target_key) then
      raise exception 'Relazione con gioco target esterno al franchise: %', v_target_key;
    end if;
    v_relations := v_relations + 1;
  end loop;

  if not p_dry_run then
    delete from public.franchise_game_relations where franchise_id = p_franchise_id;
    delete from public.franchise_tracks where franchise_id = p_franchise_id;

    for v_track in select value from jsonb_array_elements(coalesce(p_payload -> 'tracks', '[]'::jsonb)) loop
      insert into public.franchise_tracks(
        franchise_id, track_key, name, track_type, description, sort_order, is_primary
      ) values (
        p_franchise_id,
        trim(v_track ->> 'track_key'),
        left(trim(coalesce(v_track ->> 'name', v_track ->> 'track_key')), 160),
        coalesce(nullif(v_track ->> 'track_type', ''), 'continuity'),
        nullif(v_track ->> 'description', ''),
        greatest(1, coalesce(nullif(v_track ->> 'sort_order', '')::integer, 1)),
        coalesce((v_track ->> 'is_primary')::boolean, false)
      );
    end loop;

    for v_track in select value from jsonb_array_elements(coalesce(p_payload -> 'tracks', '[]'::jsonb)) loop
      v_track_key := trim(v_track ->> 'track_key');
      v_parent_key := trim(coalesce(v_track ->> 'parent_track_key', ''));
      if v_parent_key <> '' then
        update public.franchise_tracks child
        set parent_id = parent.id
        from public.franchise_tracks parent
        where child.franchise_id = p_franchise_id
          and parent.franchise_id = p_franchise_id
          and child.track_key = v_track_key
          and parent.track_key = v_parent_key;
        if not found then
          raise exception 'parent_track_key non trovato: %', v_parent_key;
        end if;
      end if;
    end loop;

    for v_game in select value from jsonb_array_elements(coalesce(p_payload -> 'games', '[]'::jsonb)) loop
      v_game_key := trim(coalesce(v_game ->> 'game_key', v_game ->> 'match_key', ''));
      v_relation_type := coalesce(nullif(v_game #>> '{editorial,entry_type}', ''), nullif(v_game ->> 'relation_type', ''));
      if v_relation_type is not null and v_relation_type not in ('main', 'spin_off', 'remake', 'remaster', 'dlc', 'expansion', 'other') then
        raise exception 'entry_type non valido per %', v_game_key;
      end if;
      v_release_order := nullif(coalesce(v_game #>> '{editorial,release_order}', v_game ->> 'release_order', ''), '')::integer;
      v_narrative_order := nullif(coalesce(v_game #>> '{editorial,narrative_order}', v_game ->> 'narrative_order', ''), '')::integer;
      v_note := coalesce(nullif(v_game #>> '{editorial,notes}', ''), nullif(v_game #>> '{editorial,note}', ''), nullif(v_game ->> 'note', ''));

      update public.franchise_games fg
      set relation_type = coalesce(v_relation_type, fg.relation_type),
          release_order = coalesce(v_release_order, fg.release_order),
          narrative_order = v_narrative_order,
          note = coalesce(v_note, fg.note),
          updated_at = now()
      where fg.franchise_id = p_franchise_id and fg.game_key = v_game_key;

      for v_membership in select value from jsonb_array_elements(coalesce(v_game -> 'track_memberships', '[]'::jsonb)) loop
        v_track_key := trim(coalesce(v_membership ->> 'track_key', ''));
        if v_track_key = '' then
          raise exception 'Membership senza track_key per %', v_game_key;
        end if;
        select id into v_track_id
        from public.franchise_tracks
        where franchise_id = p_franchise_id and track_key = v_track_key;
        if v_track_id is null then
          raise exception 'track_key non trovato per membership: %', v_track_key;
        end if;
        if coalesce(v_membership ->> 'canon_status', 'unknown') not in ('canon', 'alternate_canon', 'reimagining', 'non_canon', 'unknown', 'editorial_only') then
          raise exception 'canon_status non valido per %', v_game_key;
        end if;
        insert into public.franchise_game_tracks(
          track_id, franchise_id, game_key, narrative_order, release_order, canon_status, note
        ) values (
          v_track_id,
          p_franchise_id,
          v_game_key,
          nullif(v_membership ->> 'narrative_order', '')::integer,
          nullif(v_membership ->> 'release_order', '')::integer,
          coalesce(nullif(v_membership ->> 'canon_status', ''), 'unknown'),
          nullif(v_membership ->> 'note', '')
        )
        on conflict (track_id, game_key) do update set
          narrative_order = excluded.narrative_order,
          release_order = excluded.release_order,
          canon_status = excluded.canon_status,
          note = excluded.note,
          updated_at = now();
        v_memberships := v_memberships + 1;
      end loop;
    end loop;

    for v_relation in select value from jsonb_array_elements(coalesce(p_payload -> 'relations', '[]'::jsonb)) loop
      insert into public.franchise_game_relations(
        franchise_id, source_game_key, target_game_key, relation_type, note
      ) values (
        p_franchise_id,
        trim(v_relation ->> 'source_game_key'),
        trim(v_relation ->> 'target_game_key'),
        v_relation ->> 'relation_type',
        nullif(v_relation ->> 'note', '')
      )
      on conflict (franchise_id, source_game_key, target_game_key, relation_type) do update set
        note = excluded.note,
        updated_at = now();
    end loop;

    insert into public.admin_audit_log(actor_id, action, target_type, target_id, metadata)
    values (
      v_user,
      'franchise_editorial_json_imported',
      'franchise',
      p_franchise_id::text,
      jsonb_build_object('games', v_games, 'tracks', v_tracks, 'track_memberships', v_memberships, 'relations', v_relations)
    );
  else
    for v_game in select value from jsonb_array_elements(coalesce(p_payload -> 'games', '[]'::jsonb)) loop
      v_memberships := v_memberships + jsonb_array_length(coalesce(v_game -> 'track_memberships', '[]'::jsonb));
    end loop;
  end if;

  return jsonb_build_object(
    'status', case when p_dry_run then 'validated' else 'applied' end,
    'schema_version', v_schema,
    'counts', jsonb_build_object(
      'games', v_games,
      'tracks', v_tracks,
      'track_memberships', v_memberships,
      'relations', v_relations
    ),
    'franchise', (select jsonb_build_object('id', id, 'slug', slug, 'name', name) from public.franchises where id = p_franchise_id)
  );
end;
$$;

revoke all on function public.admin_export_franchise_editorial(uuid) from public;
revoke all on function public.admin_import_franchise_editorial(uuid, jsonb, boolean) from public;
grant execute on function public.admin_export_franchise_editorial(uuid) to authenticated;
grant execute on function public.admin_import_franchise_editorial(uuid, jsonb, boolean) to authenticated;

comment on table public.franchise_tracks is 'Percorsi editoriali di un franchise: continuità, timeline, sottosaghe e archi narrativi.';
comment on table public.franchise_game_tracks is 'Appartenenza molti-a-molti dei giochi ai percorsi editoriali, con ordine narrativo per percorso.';
comment on table public.franchise_game_relations is 'Relazioni editoriali tra giochi di uno stesso franchise: remake, reinterpretazioni, sequel, raccolte e varianti.';
comment on function public.admin_export_franchise_editorial(uuid) is 'Esporta un pacchetto JSON controllato per organizzare un franchise con strumenti esterni come ChatGPT.';
comment on function public.admin_import_franchise_editorial(uuid, jsonb, boolean) is 'Valida e importa un pacchetto JSON editoriale del franchise in modo transazionale.';

commit;

notify pgrst, 'reload schema';
