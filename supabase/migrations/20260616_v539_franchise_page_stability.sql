-- Ludograph v5.3.9 — franchise page stability and lazy variant loading
--
-- Public franchise pages previously expanded the complete canonical work graph
-- for every linked game through catalog_game_work_json(). Large franchises such
-- as Call of Duty therefore performed dozens of expensive catalog scans before
-- returning the first byte and could hit the PostgREST statement timeout.
--
-- The critical franchise payload is now lightweight. Variant/porting details
-- are requested on demand for a single game through franchise_game_variants().

begin;

create or replace function public.franchise_detail(p_slug text)
returns jsonb
language sql
stable
security definer
set search_path = ''
set statement_timeout = '8s'
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
      )
      from selected f
    ),
    'tracks', coalesce((
      select public.franchise_tracks_json(f.id)
      from selected f
    ), '[]'::jsonb),
    'relations', coalesce((
      select public.franchise_game_relations_json(f.id)
      from selected f
    ), '[]'::jsonb),
    'games', coalesce((
      select jsonb_agg(
        public.catalog_game_card_json(cg)
        || jsonb_build_object(
          'game_id', fg.game_id,
          'relation_type', fg.relation_type,
          'release_order', fg.release_order,
          'narrative_order', fg.narrative_order,
          'franchise_note', fg.note,
          'variants_lazy', true,
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
      from selected f
      join public.franchise_games fg on fg.franchise_id = f.id
      join public.catalog_games cg on cg.match_key = fg.game_key
    ), '[]'::jsonb)
  ) end;
$$;

create or replace function public.franchise_game_variants(
  p_slug text,
  p_game_key text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
set statement_timeout = '10s'
as $$
declare
  v_slug text := lower(trim(coalesce(p_slug, '')));
  v_key text := trim(coalesce(p_game_key, ''));
  v_result jsonb;
begin
  if v_slug = '' or v_key = '' then
    return null;
  end if;

  if not exists (
    select 1
    from public.franchises f
    join public.franchise_games fg on fg.franchise_id = f.id
    where f.slug = v_slug
      and f.status = 'published'
      and fg.game_key = v_key
  ) then
    return null;
  end if;

  v_result := public.catalog_game_work_json(v_key);

  return coalesce(v_result, jsonb_build_object(
    'editorial_work_key', null,
    'variant_count', 0,
    'variant_keys', '[]'::jsonb,
    'variants', '[]'::jsonb,
    'platforms', '[]'::jsonb,
    'stores', '[]'::jsonb
  ));
end;
$$;

revoke all on function public.franchise_detail(text) from public;
revoke all on function public.franchise_game_variants(text, text) from public;
grant execute on function public.franchise_detail(text) to anon, authenticated;
grant execute on function public.franchise_game_variants(text, text) to anon, authenticated;

comment on function public.franchise_detail(text) is
  'Ludograph v5.3.9: lightweight public franchise payload; variant graphs are loaded lazily.';
comment on function public.franchise_game_variants(text, text) is
  'Ludograph v5.3.9: returns versions and portings for one game linked to a published franchise.';

commit;

notify pgrst, 'reload schema';
