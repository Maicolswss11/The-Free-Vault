-- Ludograph v5.3.7 — fast set-based franchise writes
--
-- The previous batch RPC performed three expensive operations synchronously:
--   1. one PL/pgSQL loop iteration per game;
--   2. a full canonical-work consolidation after every save;
--   3. construction of the complete franchise payload, including variant graphs.
--
-- With a large IGDB master catalog this made batches above roughly ten games hit
-- the PostgREST statement timeout. Writes are now set-based and return a compact
-- acknowledgement. The admin read model is intentionally lightweight; public
-- franchise pages continue to expose subordinate variants through franchise_detail.

begin;

create or replace function public.admin_get_franchise(p_id uuid)
returns jsonb
language plpgsql
stable
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
      'id', f.id,
      'slug', f.slug,
      'name', f.name,
      'description', f.description,
      'hero_image_url', f.hero_image_url,
      'status', f.status,
      'created_at', f.created_at,
      'updated_at', f.updated_at
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
            where fgt.franchise_id = fg.franchise_id
              and fgt.game_key = fg.game_key
          ), '[]'::jsonb)
        )
        order by fg.release_order, lower(cg.title), cg.match_key
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

revoke all on function public.admin_get_franchise(uuid) from public;
grant execute on function public.admin_get_franchise(uuid) to authenticated;

create or replace function public.admin_save_franchise_games_batch(
  p_franchise_id uuid,
  p_games jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
set statement_timeout = '20s'
as $$
declare
  v_user uuid := (select auth.uid());
  v_requested integer;
  v_saved integer := 0;
  v_invalid text;
  v_missing text;
begin
  if not public.is_admin() then
    raise exception 'Accesso amministratore richiesto' using errcode = '42501';
  end if;

  if not exists (select 1 from public.franchises where id = p_franchise_id) then
    raise exception 'Franchise non trovato';
  end if;

  if p_games is null or jsonb_typeof(p_games) <> 'array' then
    raise exception 'p_games deve essere un array JSON';
  end if;

  v_requested := jsonb_array_length(p_games);
  if v_requested = 0 then
    raise exception 'Seleziona almeno un gioco';
  end if;
  if v_requested > 250 then
    raise exception 'Puoi salvare al massimo 250 giochi per batch';
  end if;

  with parsed as materialized (
    select
      nullif(trim(game_key), '') as game_key,
      coalesce(nullif(trim(relation_type), ''), 'main') as relation_type,
      release_order,
      narrative_order,
      nullif(trim(note), '') as note
    from jsonb_to_recordset(p_games) as row_data(
      game_key text,
      relation_type text,
      release_order integer,
      narrative_order integer,
      note text
    )
  )
  select string_agg(coalesce(game_key, '<vuoto>'), ', ' order by coalesce(game_key, ''))
  into v_invalid
  from parsed
  where game_key is null
     or relation_type not in ('main', 'spin_off', 'remake', 'remaster', 'dlc', 'expansion', 'other')
     or coalesce(release_order, 0) <= 0
     or (narrative_order is not null and narrative_order <= 0);

  if v_invalid is not null then
    raise exception 'Dati editoriali non validi per: %', v_invalid;
  end if;

  with parsed as materialized (
    select distinct on (nullif(trim(game_key), ''))
      nullif(trim(game_key), '') as game_key
    from jsonb_to_recordset(p_games) as row_data(game_key text)
    order by nullif(trim(game_key), '')
  )
  select string_agg(parsed.game_key, ', ' order by parsed.game_key)
  into v_missing
  from parsed
  left join public.catalog_games cg on cg.match_key = parsed.game_key
  where cg.match_key is null;

  if v_missing is not null then
    raise exception 'Giochi non trovati nel catalogo: %', v_missing;
  end if;

  insert into public.franchise_games(
    franchise_id,
    game_key,
    relation_type,
    release_order,
    narrative_order,
    note
  )
  select
    p_franchise_id,
    parsed.game_key,
    parsed.relation_type,
    parsed.release_order,
    parsed.narrative_order,
    parsed.note
  from (
    select distinct on (nullif(trim(game_key), ''))
      nullif(trim(game_key), '') as game_key,
      coalesce(nullif(trim(relation_type), ''), 'main') as relation_type,
      release_order,
      narrative_order,
      nullif(trim(note), '') as note
    from jsonb_to_recordset(p_games) as row_data(
      game_key text,
      relation_type text,
      release_order integer,
      narrative_order integer,
      note text
    )
    order by nullif(trim(game_key), '')
  ) parsed
  on conflict (franchise_id, game_key) do update set
    relation_type = excluded.relation_type,
    release_order = excluded.release_order,
    narrative_order = excluded.narrative_order,
    note = excluded.note,
    updated_at = now();

  get diagnostics v_saved = row_count;

  insert into public.admin_audit_log(actor_id, action, target_type, target_id, metadata)
  values (
    v_user,
    'franchise_games_batch_saved',
    'franchise',
    p_franchise_id::text,
    jsonb_build_object(
      'requested_count', v_requested,
      'saved_count', v_saved,
      'write_strategy', 'set_based',
      'canonical_consolidation', 'deferred'
    )
  );

  return jsonb_build_object(
    'status', 'ok',
    'franchise_id', p_franchise_id,
    'requested_count', v_requested,
    'saved_count', v_saved
  );
end;
$$;

revoke all on function public.admin_save_franchise_games_batch(uuid, jsonb) from public;
grant execute on function public.admin_save_franchise_games_batch(uuid, jsonb) to authenticated;

create or replace function public.admin_save_franchise_game(
  p_franchise_id uuid,
  p_game_key text,
  p_relation_type text,
  p_release_order integer,
  p_narrative_order integer,
  p_note text
)
returns jsonb
language sql
security definer
set search_path = ''
set statement_timeout = '20s'
as $$
  select public.admin_save_franchise_games_batch(
    p_franchise_id,
    jsonb_build_array(jsonb_build_object(
      'game_key', p_game_key,
      'relation_type', p_relation_type,
      'release_order', p_release_order,
      'narrative_order', p_narrative_order,
      'note', p_note
    ))
  );
$$;

revoke all on function public.admin_save_franchise_game(uuid, text, text, integer, integer, text) from public;
grant execute on function public.admin_save_franchise_game(uuid, text, text, integer, integer, text) to authenticated;

comment on function public.admin_save_franchise_games_batch(uuid, jsonb) is
'Ludograph v5.3.7: set-based franchise UPSERT. Returns a compact acknowledgement and defers expensive canonical consolidation.';
comment on function public.admin_get_franchise(uuid) is
'Ludograph v5.3.7: lightweight admin franchise read model without per-game canonical variant graph expansion.';

commit;

notify pgrst, 'reload schema';
