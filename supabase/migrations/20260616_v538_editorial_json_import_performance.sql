-- Ludograph v5.3.8 — set-based editorial JSON import.
-- Replaces the row-by-row franchise importer and avoids the expensive
-- canonical consolidation request after every JSON application.

begin;

create or replace function public.admin_import_franchise_editorial(
  p_franchise_id uuid,
  p_payload jsonb,
  p_dry_run boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = ''
set statement_timeout = '30s'
as $$
declare
  v_user uuid := (select auth.uid());
  v_schema text := coalesce(p_payload ->> 'schema_version', '');
  v_payload_franchise uuid;
  v_games integer := 0;
  v_tracks integer := 0;
  v_memberships integer := 0;
  v_relations integer := 0;
  v_invalid text;
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

  v_games := jsonb_array_length(coalesce(p_payload -> 'games', '[]'::jsonb));
  v_tracks := jsonb_array_length(coalesce(p_payload -> 'tracks', '[]'::jsonb));
  v_relations := jsonb_array_length(coalesce(p_payload -> 'relations', '[]'::jsonb));

  select coalesce(sum(jsonb_array_length(coalesce(game.value -> 'track_memberships', '[]'::jsonb))), 0)::integer
  into v_memberships
  from jsonb_array_elements(coalesce(p_payload -> 'games', '[]'::jsonb)) game(value);

  -- Validate game keys, duplicates, membership in the franchise and entry types.
  with parsed as materialized (
    select
      trim(coalesce(game.value ->> 'game_key', game.value ->> 'match_key', '')) as game_key,
      coalesce(
        nullif(game.value #>> '{editorial,entry_type}', ''),
        nullif(game.value ->> 'relation_type', '')
      ) as entry_type
    from jsonb_array_elements(coalesce(p_payload -> 'games', '[]'::jsonb)) game(value)
  )
  select string_agg(coalesce(parsed.game_key, '<vuoto>'), ', ' order by coalesce(parsed.game_key, ''))
  into v_invalid
  from parsed
  left join public.franchise_games fg
    on fg.franchise_id = p_franchise_id
   and fg.game_key = parsed.game_key
  where parsed.game_key = ''
     or fg.game_key is null
     or (parsed.entry_type is not null and parsed.entry_type not in (
       'main', 'spin_off', 'remake', 'remaster', 'dlc', 'expansion', 'other'
     ));

  if v_invalid is not null then
    raise exception 'Giochi non validi o esterni al franchise: %', v_invalid;
  end if;

  with parsed as materialized (
    select trim(coalesce(game.value ->> 'game_key', game.value ->> 'match_key', '')) as game_key
    from jsonb_array_elements(coalesce(p_payload -> 'games', '[]'::jsonb)) game(value)
  )
  select string_agg(game_key, ', ' order by game_key)
  into v_invalid
  from parsed
  group by game_key
  having count(*) > 1
  limit 1;

  if v_invalid is not null then
    raise exception 'game_key duplicato nel JSON: %', v_invalid;
  end if;

  -- Validate tracks and parent references without row-by-row lookups.
  with parsed as materialized (
    select
      trim(coalesce(track.value ->> 'track_key', '')) as track_key,
      trim(coalesce(track.value ->> 'parent_track_key', '')) as parent_track_key,
      coalesce(nullif(track.value ->> 'track_type', ''), 'continuity') as track_type
    from jsonb_array_elements(coalesce(p_payload -> 'tracks', '[]'::jsonb)) track(value)
  )
  select string_agg(coalesce(track_key, '<vuoto>'), ', ' order by coalesce(track_key, ''))
  into v_invalid
  from parsed
  where track_key = ''
     or track_key !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'
     or track_type not in (
       'continuity', 'timeline', 'subseries', 'story_arc',
       'anthology', 'remake_line', 'collection', 'other'
     );

  if v_invalid is not null then
    raise exception 'Percorsi editoriali non validi: %', v_invalid;
  end if;

  with parsed as materialized (
    select
      trim(coalesce(track.value ->> 'track_key', '')) as track_key,
      trim(coalesce(track.value ->> 'parent_track_key', '')) as parent_track_key
    from jsonb_array_elements(coalesce(p_payload -> 'tracks', '[]'::jsonb)) track(value)
  )
  select string_agg(child.parent_track_key, ', ' order by child.parent_track_key)
  into v_invalid
  from parsed child
  left join parsed parent on parent.track_key = child.parent_track_key
  where child.parent_track_key <> ''
    and (parent.track_key is null or child.parent_track_key = child.track_key);

  if v_invalid is not null then
    raise exception 'parent_track_key non trovato o circolare: %', v_invalid;
  end if;

  with parsed as materialized (
    select trim(coalesce(track.value ->> 'track_key', '')) as track_key
    from jsonb_array_elements(coalesce(p_payload -> 'tracks', '[]'::jsonb)) track(value)
  )
  select string_agg(track_key, ', ' order by track_key)
  into v_invalid
  from parsed
  group by track_key
  having count(*) > 1
  limit 1;

  if v_invalid is not null then
    raise exception 'track_key duplicato nel JSON: %', v_invalid;
  end if;

  -- Validate memberships. The global editorial canon_status is the fallback
  -- when ChatGPT omits canon_status from a specific track membership.
  with track_keys as materialized (
    select trim(coalesce(track.value ->> 'track_key', '')) as track_key
    from jsonb_array_elements(coalesce(p_payload -> 'tracks', '[]'::jsonb)) track(value)
  ), memberships as materialized (
    select
      trim(coalesce(game.value ->> 'game_key', game.value ->> 'match_key', '')) as game_key,
      trim(coalesce(membership.value ->> 'track_key', '')) as track_key,
      coalesce(
        nullif(membership.value ->> 'canon_status', ''),
        nullif(game.value #>> '{editorial,canon_status}', ''),
        'unknown'
      ) as canon_status
    from jsonb_array_elements(coalesce(p_payload -> 'games', '[]'::jsonb)) game(value)
    cross join lateral jsonb_array_elements(coalesce(game.value -> 'track_memberships', '[]'::jsonb)) membership(value)
  )
  select string_agg(memberships.game_key || ':' || coalesce(memberships.track_key, '<vuoto>'), ', ' order by memberships.game_key, memberships.track_key)
  into v_invalid
  from memberships
  left join track_keys on track_keys.track_key = memberships.track_key
  where memberships.track_key = ''
     or track_keys.track_key is null
     or memberships.canon_status not in (
       'canon', 'alternate_canon', 'reimagining',
       'non_canon', 'unknown', 'editorial_only'
     );

  if v_invalid is not null then
    raise exception 'Membership editoriali non valide: %', v_invalid;
  end if;

  with memberships as materialized (
    select
      trim(coalesce(game.value ->> 'game_key', game.value ->> 'match_key', '')) as game_key,
      trim(coalesce(membership.value ->> 'track_key', '')) as track_key
    from jsonb_array_elements(coalesce(p_payload -> 'games', '[]'::jsonb)) game(value)
    cross join lateral jsonb_array_elements(coalesce(game.value -> 'track_memberships', '[]'::jsonb)) membership(value)
  )
  select string_agg(game_key || ':' || track_key, ', ' order by game_key, track_key)
  into v_invalid
  from memberships
  group by game_key, track_key
  having count(*) > 1
  limit 1;

  if v_invalid is not null then
    raise exception 'Membership duplicata nel JSON: %', v_invalid;
  end if;

  -- Validate relations in one indexed pass.
  with relations as materialized (
    select
      trim(coalesce(relation.value ->> 'source_game_key', '')) as source_game_key,
      trim(coalesce(relation.value ->> 'target_game_key', '')) as target_game_key,
      trim(coalesce(relation.value ->> 'relation_type', '')) as relation_type
    from jsonb_array_elements(coalesce(p_payload -> 'relations', '[]'::jsonb)) relation(value)
  )
  select string_agg(
    coalesce(source_game_key, '<vuoto>') || '→' || coalesce(target_game_key, '<vuoto>'),
    ', ' order by source_game_key, target_game_key
  )
  into v_invalid
  from relations
  left join public.franchise_games source_game
    on source_game.franchise_id = p_franchise_id
   and source_game.game_key = relations.source_game_key
  left join public.franchise_games target_game
    on target_game.franchise_id = p_franchise_id
   and target_game.game_key = relations.target_game_key
  where relations.source_game_key = ''
     or relations.target_game_key = ''
     or relations.source_game_key = relations.target_game_key
     or source_game.game_key is null
     or target_game.game_key is null
     or relations.relation_type not in (
       'sequel_to', 'prequel_to', 'remake_of', 'remaster_of',
       'reimagines', 'alternate_version_of', 'parallel_to',
       'expansion_of', 'collection_of', 'contains',
       'spiritual_successor_to', 'related_to'
     );

  if v_invalid is not null then
    raise exception 'Relazioni editoriali non valide: %', v_invalid;
  end if;

  if not p_dry_run then
    -- Replacing tracks cascades the previous memberships. All writes below are
    -- set-based and remain part of the same transaction.
    delete from public.franchise_game_relations
    where franchise_id = p_franchise_id;

    delete from public.franchise_tracks
    where franchise_id = p_franchise_id;

    insert into public.franchise_tracks(
      franchise_id, track_key, name, track_type,
      description, sort_order, is_primary
    )
    select
      p_franchise_id,
      trim(track.value ->> 'track_key'),
      left(trim(coalesce(track.value ->> 'name', track.value ->> 'track_key')), 160),
      coalesce(nullif(track.value ->> 'track_type', ''), 'continuity'),
      nullif(track.value ->> 'description', ''),
      greatest(1, coalesce(nullif(track.value ->> 'sort_order', '')::integer, 1)),
      coalesce(nullif(track.value ->> 'is_primary', '')::boolean, false)
    from jsonb_array_elements(coalesce(p_payload -> 'tracks', '[]'::jsonb)) track(value);

    with parsed as materialized (
      select
        trim(track.value ->> 'track_key') as track_key,
        trim(coalesce(track.value ->> 'parent_track_key', '')) as parent_track_key
      from jsonb_array_elements(coalesce(p_payload -> 'tracks', '[]'::jsonb)) track(value)
    )
    update public.franchise_tracks child
    set parent_id = parent.id,
        updated_at = now()
    from parsed
    join public.franchise_tracks parent
      on parent.franchise_id = p_franchise_id
     and parent.track_key = parsed.parent_track_key
    where child.franchise_id = p_franchise_id
      and child.track_key = parsed.track_key
      and parsed.parent_track_key <> '';

    with parsed as materialized (
      select
        trim(coalesce(game.value ->> 'game_key', game.value ->> 'match_key', '')) as game_key,
        coalesce(
          nullif(game.value #>> '{editorial,entry_type}', ''),
          nullif(game.value ->> 'relation_type', '')
        ) as entry_type,
        nullif(coalesce(
          game.value #>> '{editorial,release_order}',
          game.value ->> 'release_order',
          ''
        ), '')::integer as release_order,
        nullif(coalesce(
          game.value #>> '{editorial,narrative_order}',
          game.value ->> 'narrative_order',
          ''
        ), '')::integer as narrative_order,
        coalesce(
          nullif(game.value #>> '{editorial,notes}', ''),
          nullif(game.value #>> '{editorial,note}', ''),
          nullif(game.value ->> 'note', '')
        ) as note
      from jsonb_array_elements(coalesce(p_payload -> 'games', '[]'::jsonb)) game(value)
    )
    update public.franchise_games fg
    set relation_type = coalesce(parsed.entry_type, fg.relation_type),
        release_order = coalesce(parsed.release_order, fg.release_order),
        narrative_order = parsed.narrative_order,
        note = coalesce(parsed.note, fg.note),
        updated_at = now()
    from parsed
    where fg.franchise_id = p_franchise_id
      and fg.game_key = parsed.game_key;

    with memberships as materialized (
      select
        trim(coalesce(game.value ->> 'game_key', game.value ->> 'match_key', '')) as game_key,
        trim(membership.value ->> 'track_key') as track_key,
        nullif(membership.value ->> 'narrative_order', '')::integer as narrative_order,
        nullif(membership.value ->> 'release_order', '')::integer as release_order,
        coalesce(
          nullif(membership.value ->> 'canon_status', ''),
          nullif(game.value #>> '{editorial,canon_status}', ''),
          'unknown'
        ) as canon_status,
        nullif(membership.value ->> 'note', '') as note
      from jsonb_array_elements(coalesce(p_payload -> 'games', '[]'::jsonb)) game(value)
      cross join lateral jsonb_array_elements(coalesce(game.value -> 'track_memberships', '[]'::jsonb)) membership(value)
    )
    insert into public.franchise_game_tracks(
      track_id, franchise_id, game_key, game_id,
      narrative_order, release_order, canon_status, note
    )
    select
      track.id,
      p_franchise_id,
      memberships.game_key,
      fg.game_id,
      memberships.narrative_order,
      memberships.release_order,
      memberships.canon_status,
      memberships.note
    from memberships
    join public.franchise_tracks track
      on track.franchise_id = p_franchise_id
     and track.track_key = memberships.track_key
    join public.franchise_games fg
      on fg.franchise_id = p_franchise_id
     and fg.game_key = memberships.game_key
    on conflict (track_id, game_key) do update set
      game_id = excluded.game_id,
      narrative_order = excluded.narrative_order,
      release_order = excluded.release_order,
      canon_status = excluded.canon_status,
      note = excluded.note,
      updated_at = now();

    with relations as materialized (
      select
        trim(relation.value ->> 'source_game_key') as source_game_key,
        trim(relation.value ->> 'target_game_key') as target_game_key,
        trim(relation.value ->> 'relation_type') as relation_type,
        nullif(relation.value ->> 'note', '') as note
      from jsonb_array_elements(coalesce(p_payload -> 'relations', '[]'::jsonb)) relation(value)
    )
    insert into public.franchise_game_relations(
      franchise_id,
      source_game_key,
      target_game_key,
      source_game_id,
      target_game_id,
      relation_type,
      note
    )
    select
      p_franchise_id,
      relations.source_game_key,
      relations.target_game_key,
      source_game.game_id,
      target_game.game_id,
      relations.relation_type,
      relations.note
    from relations
    join public.franchise_games source_game
      on source_game.franchise_id = p_franchise_id
     and source_game.game_key = relations.source_game_key
    join public.franchise_games target_game
      on target_game.franchise_id = p_franchise_id
     and target_game.game_key = relations.target_game_key
    on conflict (franchise_id, source_game_key, target_game_key, relation_type) do update set
      source_game_id = excluded.source_game_id,
      target_game_id = excluded.target_game_id,
      note = excluded.note,
      updated_at = now();

    insert into public.admin_audit_log(actor_id, action, target_type, target_id, metadata)
    values (
      v_user,
      'franchise_editorial_json_imported',
      'franchise',
      p_franchise_id::text,
      jsonb_build_object(
        'games', v_games,
        'tracks', v_tracks,
        'track_memberships', v_memberships,
        'relations', v_relations,
        'write_strategy', 'set_based',
        'canonical_consolidation', 'not_required'
      )
    );
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
    'write_strategy', 'set_based',
    'franchise', (
      select jsonb_build_object('id', id, 'slug', slug, 'name', name)
      from public.franchises
      where id = p_franchise_id
    )
  );
end;
$$;

revoke all on function public.admin_import_franchise_editorial(uuid, jsonb, boolean) from public;
grant execute on function public.admin_import_franchise_editorial(uuid, jsonb, boolean) to authenticated;

comment on function public.admin_import_franchise_editorial(uuid, jsonb, boolean) is
'Ludograph v5.3.8: set-based transactional franchise editorial JSON validation/import with compact acknowledgement.';

commit;

notify pgrst, 'reload schema';
