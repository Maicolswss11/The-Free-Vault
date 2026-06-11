-- The Free Vault v4.6 — Franchise, saghe e collezioni editoriali.
-- Eseguire dopo la v4.5.
-- Le tabelle contengono soltanto metadati e riferimenti ai match_key del catalogo:
-- nessuna copia dei record di catalog_games.

create table if not exists public.franchises (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique
    check (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' and char_length(slug) between 2 and 100),
  name text not null check (char_length(name) between 2 and 160),
  description text check (description is null or char_length(description) <= 5000),
  hero_image_url text,
  status text not null default 'draft' check (status in ('draft', 'published')),
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.franchise_games (
  franchise_id uuid not null references public.franchises(id) on delete cascade,
  game_key text not null references public.catalog_games(match_key) on delete cascade,
  relation_type text not null default 'main'
    check (relation_type in ('main', 'spin_off', 'remake', 'remaster', 'dlc', 'expansion', 'other')),
  release_order integer not null check (release_order > 0),
  narrative_order integer check (narrative_order is null or narrative_order > 0),
  note text check (note is null or char_length(note) <= 1000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (franchise_id, game_key)
);

create table if not exists public.editorial_collections (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique
    check (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' and char_length(slug) between 2 and 100),
  title text not null check (char_length(title) between 2 and 160),
  description text check (description is null or char_length(description) <= 5000),
  cover_image_url text,
  curator_note text check (curator_note is null or char_length(curator_note) <= 5000),
  status text not null default 'draft' check (status in ('draft', 'published')),
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.editorial_collection_games (
  collection_id uuid not null references public.editorial_collections(id) on delete cascade,
  game_key text not null references public.catalog_games(match_key) on delete cascade,
  position integer not null check (position > 0),
  editorial_note text check (editorial_note is null or char_length(editorial_note) <= 2000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (collection_id, game_key)
);

create index if not exists franchise_games_release_idx
on public.franchise_games(franchise_id, release_order, game_key);

create index if not exists franchise_games_narrative_idx
on public.franchise_games(franchise_id, narrative_order, game_key)
where narrative_order is not null;

create index if not exists franchise_games_game_key_idx
on public.franchise_games(game_key);

create index if not exists editorial_collection_games_position_idx
on public.editorial_collection_games(collection_id, position, game_key);

create index if not exists editorial_collection_games_game_key_idx
on public.editorial_collection_games(game_key);

alter table public.franchises enable row level security;
alter table public.franchise_games enable row level security;
alter table public.editorial_collections enable row level security;
alter table public.editorial_collection_games enable row level security;

revoke all on public.franchises from anon, authenticated;
revoke all on public.franchise_games from anon, authenticated;
revoke all on public.editorial_collections from anon, authenticated;
revoke all on public.editorial_collection_games from anon, authenticated;

grant select, insert, update, delete on public.franchises to service_role;
grant select, insert, update, delete on public.franchise_games to service_role;
grant select, insert, update, delete on public.editorial_collections to service_role;
grant select, insert, update, delete on public.editorial_collection_games to service_role;

create or replace function public.touch_editorial_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists franchises_touch_updated_at on public.franchises;
create trigger franchises_touch_updated_at
before update on public.franchises
for each row execute function public.touch_editorial_updated_at();

drop trigger if exists franchise_games_touch_updated_at on public.franchise_games;
create trigger franchise_games_touch_updated_at
before update on public.franchise_games
for each row execute function public.touch_editorial_updated_at();

drop trigger if exists editorial_collections_touch_updated_at on public.editorial_collections;
create trigger editorial_collections_touch_updated_at
before update on public.editorial_collections
for each row execute function public.touch_editorial_updated_at();

drop trigger if exists editorial_collection_games_touch_updated_at on public.editorial_collection_games;
create trigger editorial_collection_games_touch_updated_at
before update on public.editorial_collection_games
for each row execute function public.touch_editorial_updated_at();

create or replace function public.editorial_directory()
returns jsonb
language sql
stable
security definer
set search_path = ''
set statement_timeout = '10s'
as $$
  select jsonb_build_object(
    'franchises', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', f.id,
          'slug', f.slug,
          'name', f.name,
          'description', f.description,
          'hero_image_url', f.hero_image_url,
          'game_count', (select count(*) from public.franchise_games fg where fg.franchise_id = f.id)
        ) order by lower(f.name), f.slug
      )
      from public.franchises f
      where f.status = 'published'
    ), '[]'::jsonb),
    'collections', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', c.id,
          'slug', c.slug,
          'title', c.title,
          'description', c.description,
          'cover_image_url', c.cover_image_url,
          'curator_note', c.curator_note,
          'game_count', (select count(*) from public.editorial_collection_games ecg where ecg.collection_id = c.id)
        ) order by c.updated_at desc, lower(c.title), c.slug
      )
      from public.editorial_collections c
      where c.status = 'published'
    ), '[]'::jsonb)
  );
$$;

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
    'games', coalesce((
      select jsonb_agg(
        public.catalog_game_card_json(cg)
        || jsonb_build_object(
          'relation_type', fg.relation_type,
          'release_order', fg.release_order,
          'narrative_order', fg.narrative_order,
          'franchise_note', fg.note
        )
        order by fg.release_order, lower(cg.title), cg.match_key
      )
      from selected f
      join public.franchise_games fg on fg.franchise_id = f.id
      join public.catalog_games cg on cg.match_key = fg.game_key
    ), '[]'::jsonb)
  ) end;
$$;

create or replace function public.editorial_collection_detail(p_slug text)
returns jsonb
language sql
stable
security definer
set search_path = ''
set statement_timeout = '10s'
as $$
  with selected as materialized (
    select c.*
    from public.editorial_collections c
    where c.slug = lower(trim(p_slug))
      and c.status = 'published'
    limit 1
  )
  select case when not exists (select 1 from selected) then null else jsonb_build_object(
    'collection', (
      select jsonb_build_object(
        'id', c.id,
        'slug', c.slug,
        'title', c.title,
        'description', c.description,
        'cover_image_url', c.cover_image_url,
        'curator_note', c.curator_note,
        'status', c.status,
        'updated_at', c.updated_at
      ) from selected c
    ),
    'games', coalesce((
      select jsonb_agg(
        public.catalog_game_card_json(cg)
        || jsonb_build_object(
          'collection_position', ecg.position,
          'editorial_note', ecg.editorial_note
        )
        order by ecg.position, lower(cg.title), cg.match_key
      )
      from selected c
      join public.editorial_collection_games ecg on ecg.collection_id = c.id
      join public.catalog_games cg on cg.match_key = ecg.game_key
    ), '[]'::jsonb)
  ) end;
$$;

create or replace function public.catalog_editorial_memberships(p_key text)
returns jsonb
language sql
stable
security definer
set search_path = ''
set statement_timeout = '10s'
as $$
  with resolved as materialized (
    select cg.match_key
    from public.catalog_games cg
    where cg.match_key = p_key or cg.canonical_id = p_key
    order by case when cg.match_key = p_key then 0 else 1 end
    limit 1
  )
  select jsonb_build_object(
    'franchises', coalesce((
      select jsonb_agg(jsonb_build_object('slug', f.slug, 'name', f.name, 'relation_type', fg.relation_type) order by lower(f.name))
      from resolved r
      join public.franchise_games fg on fg.game_key = r.match_key
      join public.franchises f on f.id = fg.franchise_id and f.status = 'published'
    ), '[]'::jsonb),
    'collections', coalesce((
      select jsonb_agg(jsonb_build_object('slug', c.slug, 'title', c.title, 'position', ecg.position) order by lower(c.title))
      from resolved r
      join public.editorial_collection_games ecg on ecg.game_key = r.match_key
      join public.editorial_collections c on c.id = ecg.collection_id and c.status = 'published'
    ), '[]'::jsonb)
  );
$$;

create or replace function public.admin_list_franchises()
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
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', f.id, 'slug', f.slug, 'name', f.name, 'description', f.description,
      'hero_image_url', f.hero_image_url, 'status', f.status,
      'game_count', (select count(*) from public.franchise_games fg where fg.franchise_id = f.id),
      'updated_at', f.updated_at
    ) order by f.updated_at desc, lower(f.name)
  ), '[]'::jsonb)
  into result
  from public.franchises f;
  return result;
end;
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
    'games', coalesce((
      select jsonb_agg(
        public.catalog_game_card_json(cg)
        || jsonb_build_object(
          'relation_type', fg.relation_type,
          'release_order', fg.release_order,
          'narrative_order', fg.narrative_order,
          'franchise_note', fg.note
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

create or replace function public.admin_save_franchise(
  p_id uuid,
  p_slug text,
  p_name text,
  p_description text,
  p_hero_image_url text,
  p_status text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_user uuid := (select auth.uid());
  v_slug text := lower(trim(coalesce(p_slug, '')));
  v_name text := trim(coalesce(p_name, ''));
begin
  if not public.is_admin() then
    raise exception 'Accesso amministratore richiesto' using errcode = '42501';
  end if;
  if v_slug !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' or char_length(v_slug) not between 2 and 100 then
    raise exception 'Slug non valido';
  end if;
  if char_length(v_name) not between 2 and 160 then raise exception 'Nome non valido'; end if;
  if p_status not in ('draft', 'published') then raise exception 'Stato non valido'; end if;

  if p_id is null then
    insert into public.franchises(slug, name, description, hero_image_url, status, created_by, updated_by)
    values (v_slug, v_name, nullif(trim(p_description), ''), nullif(trim(p_hero_image_url), ''), p_status, v_user, v_user)
    returning id into v_id;
  else
    update public.franchises
    set slug = v_slug,
        name = v_name,
        description = nullif(trim(p_description), ''),
        hero_image_url = nullif(trim(p_hero_image_url), ''),
        status = p_status,
        updated_by = v_user,
        updated_at = now()
    where id = p_id
    returning id into v_id;
    if v_id is null then raise exception 'Franchise non trovato'; end if;
  end if;

  insert into public.admin_audit_log(actor_id, action, target_type, target_id)
  values (v_user, 'franchise_saved', 'franchise', v_id::text);
  return public.admin_get_franchise(v_id);
end;
$$;

create or replace function public.admin_delete_franchise(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
begin
  if not public.is_admin() then
    raise exception 'Accesso amministratore richiesto' using errcode = '42501';
  end if;
  delete from public.franchises where id = p_id;
  if not found then raise exception 'Franchise non trovato'; end if;
  insert into public.admin_audit_log(actor_id, action, target_type, target_id)
  values (v_user, 'franchise_deleted', 'franchise', p_id::text);
  return jsonb_build_object('deleted', true, 'id', p_id);
end;
$$;

create or replace function public.admin_save_franchise_game(
  p_franchise_id uuid,
  p_game_key text,
  p_relation_type text,
  p_release_order integer,
  p_narrative_order integer,
  p_note text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_key text := trim(coalesce(p_game_key, ''));
begin
  if not public.is_admin() then
    raise exception 'Accesso amministratore richiesto' using errcode = '42501';
  end if;
  if p_relation_type not in ('main', 'spin_off', 'remake', 'remaster', 'dlc', 'expansion', 'other') then
    raise exception 'Tipo relazione non valido';
  end if;
  if coalesce(p_release_order, 0) <= 0 then raise exception 'Ordine di uscita non valido'; end if;
  if p_narrative_order is not null and p_narrative_order <= 0 then raise exception 'Ordine narrativo non valido'; end if;
  if not exists (select 1 from public.franchises where id = p_franchise_id) then raise exception 'Franchise non trovato'; end if;
  if not exists (select 1 from public.catalog_games where match_key = v_key) then raise exception 'Gioco non trovato nel catalogo'; end if;

  insert into public.franchise_games(franchise_id, game_key, relation_type, release_order, narrative_order, note)
  values (p_franchise_id, v_key, p_relation_type, p_release_order, p_narrative_order, nullif(trim(p_note), ''))
  on conflict (franchise_id, game_key) do update set
    relation_type = excluded.relation_type,
    release_order = excluded.release_order,
    narrative_order = excluded.narrative_order,
    note = excluded.note,
    updated_at = now();

  insert into public.admin_audit_log(actor_id, action, target_type, target_id, metadata)
  values (v_user, 'franchise_game_saved', 'franchise', p_franchise_id::text, jsonb_build_object('game_key', v_key));
  return public.admin_get_franchise(p_franchise_id);
end;
$$;

create or replace function public.admin_remove_franchise_game(p_franchise_id uuid, p_game_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
begin
  if not public.is_admin() then
    raise exception 'Accesso amministratore richiesto' using errcode = '42501';
  end if;
  delete from public.franchise_games where franchise_id = p_franchise_id and game_key = p_game_key;
  insert into public.admin_audit_log(actor_id, action, target_type, target_id, metadata)
  values (v_user, 'franchise_game_removed', 'franchise', p_franchise_id::text, jsonb_build_object('game_key', p_game_key));
  return public.admin_get_franchise(p_franchise_id);
end;
$$;

create or replace function public.admin_list_editorial_collections()
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
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', c.id, 'slug', c.slug, 'title', c.title, 'description', c.description,
      'cover_image_url', c.cover_image_url, 'curator_note', c.curator_note,
      'status', c.status,
      'game_count', (select count(*) from public.editorial_collection_games ecg where ecg.collection_id = c.id),
      'updated_at', c.updated_at
    ) order by c.updated_at desc, lower(c.title)
  ), '[]'::jsonb)
  into result
  from public.editorial_collections c;
  return result;
end;
$$;

create or replace function public.admin_get_editorial_collection(p_id uuid)
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
    'collection', jsonb_build_object(
      'id', c.id, 'slug', c.slug, 'title', c.title, 'description', c.description,
      'cover_image_url', c.cover_image_url, 'curator_note', c.curator_note,
      'status', c.status, 'created_at', c.created_at, 'updated_at', c.updated_at
    ),
    'games', coalesce((
      select jsonb_agg(
        public.catalog_game_card_json(cg)
        || jsonb_build_object('collection_position', ecg.position, 'editorial_note', ecg.editorial_note)
        order by ecg.position, lower(cg.title), cg.match_key
      )
      from public.editorial_collection_games ecg
      join public.catalog_games cg on cg.match_key = ecg.game_key
      where ecg.collection_id = c.id
    ), '[]'::jsonb)
  ) into result
  from public.editorial_collections c
  where c.id = p_id;
  return result;
end;
$$;

create or replace function public.admin_save_editorial_collection(
  p_id uuid,
  p_slug text,
  p_title text,
  p_description text,
  p_cover_image_url text,
  p_curator_note text,
  p_status text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_user uuid := (select auth.uid());
  v_slug text := lower(trim(coalesce(p_slug, '')));
  v_title text := trim(coalesce(p_title, ''));
begin
  if not public.is_admin() then
    raise exception 'Accesso amministratore richiesto' using errcode = '42501';
  end if;
  if v_slug !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' or char_length(v_slug) not between 2 and 100 then
    raise exception 'Slug non valido';
  end if;
  if char_length(v_title) not between 2 and 160 then raise exception 'Titolo non valido'; end if;
  if p_status not in ('draft', 'published') then raise exception 'Stato non valido'; end if;

  if p_id is null then
    insert into public.editorial_collections(slug, title, description, cover_image_url, curator_note, status, created_by, updated_by)
    values (v_slug, v_title, nullif(trim(p_description), ''), nullif(trim(p_cover_image_url), ''), nullif(trim(p_curator_note), ''), p_status, v_user, v_user)
    returning id into v_id;
  else
    update public.editorial_collections
    set slug = v_slug,
        title = v_title,
        description = nullif(trim(p_description), ''),
        cover_image_url = nullif(trim(p_cover_image_url), ''),
        curator_note = nullif(trim(p_curator_note), ''),
        status = p_status,
        updated_by = v_user,
        updated_at = now()
    where id = p_id
    returning id into v_id;
    if v_id is null then raise exception 'Collezione non trovata'; end if;
  end if;

  insert into public.admin_audit_log(actor_id, action, target_type, target_id)
  values (v_user, 'editorial_collection_saved', 'editorial_collection', v_id::text);
  return public.admin_get_editorial_collection(v_id);
end;
$$;

create or replace function public.admin_delete_editorial_collection(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
begin
  if not public.is_admin() then
    raise exception 'Accesso amministratore richiesto' using errcode = '42501';
  end if;
  delete from public.editorial_collections where id = p_id;
  if not found then raise exception 'Collezione non trovata'; end if;
  insert into public.admin_audit_log(actor_id, action, target_type, target_id)
  values (v_user, 'editorial_collection_deleted', 'editorial_collection', p_id::text);
  return jsonb_build_object('deleted', true, 'id', p_id);
end;
$$;

create or replace function public.admin_save_editorial_collection_game(
  p_collection_id uuid,
  p_game_key text,
  p_position integer,
  p_editorial_note text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_key text := trim(coalesce(p_game_key, ''));
begin
  if not public.is_admin() then
    raise exception 'Accesso amministratore richiesto' using errcode = '42501';
  end if;
  if coalesce(p_position, 0) <= 0 then raise exception 'Posizione non valida'; end if;
  if not exists (select 1 from public.editorial_collections where id = p_collection_id) then raise exception 'Collezione non trovata'; end if;
  if not exists (select 1 from public.catalog_games where match_key = v_key) then raise exception 'Gioco non trovato nel catalogo'; end if;

  insert into public.editorial_collection_games(collection_id, game_key, position, editorial_note)
  values (p_collection_id, v_key, p_position, nullif(trim(p_editorial_note), ''))
  on conflict (collection_id, game_key) do update set
    position = excluded.position,
    editorial_note = excluded.editorial_note,
    updated_at = now();

  insert into public.admin_audit_log(actor_id, action, target_type, target_id, metadata)
  values (v_user, 'editorial_collection_game_saved', 'editorial_collection', p_collection_id::text, jsonb_build_object('game_key', v_key));
  return public.admin_get_editorial_collection(p_collection_id);
end;
$$;

create or replace function public.admin_remove_editorial_collection_game(p_collection_id uuid, p_game_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
begin
  if not public.is_admin() then
    raise exception 'Accesso amministratore richiesto' using errcode = '42501';
  end if;
  delete from public.editorial_collection_games where collection_id = p_collection_id and game_key = p_game_key;
  insert into public.admin_audit_log(actor_id, action, target_type, target_id, metadata)
  values (v_user, 'editorial_collection_game_removed', 'editorial_collection', p_collection_id::text, jsonb_build_object('game_key', p_game_key));
  return public.admin_get_editorial_collection(p_collection_id);
end;
$$;

revoke all on function public.editorial_directory() from public;
revoke all on function public.franchise_detail(text) from public;
revoke all on function public.editorial_collection_detail(text) from public;
revoke all on function public.catalog_editorial_memberships(text) from public;
revoke all on function public.admin_list_franchises() from public;
revoke all on function public.admin_get_franchise(uuid) from public;
revoke all on function public.admin_save_franchise(uuid,text,text,text,text,text) from public;
revoke all on function public.admin_delete_franchise(uuid) from public;
revoke all on function public.admin_save_franchise_game(uuid,text,text,integer,integer,text) from public;
revoke all on function public.admin_remove_franchise_game(uuid,text) from public;
revoke all on function public.admin_list_editorial_collections() from public;
revoke all on function public.admin_get_editorial_collection(uuid) from public;
revoke all on function public.admin_save_editorial_collection(uuid,text,text,text,text,text,text) from public;
revoke all on function public.admin_delete_editorial_collection(uuid) from public;
revoke all on function public.admin_save_editorial_collection_game(uuid,text,integer,text) from public;
revoke all on function public.admin_remove_editorial_collection_game(uuid,text) from public;

grant execute on function public.editorial_directory() to anon, authenticated;
grant execute on function public.franchise_detail(text) to anon, authenticated;
grant execute on function public.editorial_collection_detail(text) to anon, authenticated;
grant execute on function public.catalog_editorial_memberships(text) to anon, authenticated;
grant execute on function public.admin_list_franchises() to authenticated;
grant execute on function public.admin_get_franchise(uuid) to authenticated;
grant execute on function public.admin_save_franchise(uuid,text,text,text,text,text) to authenticated;
grant execute on function public.admin_delete_franchise(uuid) to authenticated;
grant execute on function public.admin_save_franchise_game(uuid,text,text,integer,integer,text) to authenticated;
grant execute on function public.admin_remove_franchise_game(uuid,text) to authenticated;
grant execute on function public.admin_list_editorial_collections() to authenticated;
grant execute on function public.admin_get_editorial_collection(uuid) to authenticated;
grant execute on function public.admin_save_editorial_collection(uuid,text,text,text,text,text,text) to authenticated;
grant execute on function public.admin_delete_editorial_collection(uuid) to authenticated;
grant execute on function public.admin_save_editorial_collection_game(uuid,text,integer,text) to authenticated;
grant execute on function public.admin_remove_editorial_collection_game(uuid,text) to authenticated;

-- Bozze iniziali: l'admin le completa collegando i match_key reali e poi le pubblica.
insert into public.franchises(slug, name, description, status)
values
  ('resident-evil', 'Resident Evil', 'Cronologia completa della saga Resident Evil.', 'draft'),
  ('alan-wake', 'Alan Wake', 'Giochi, espansioni e collegamenti narrativi della saga Alan Wake.', 'draft')
on conflict (slug) do nothing;

comment on table public.franchises is 'Metadati leggeri delle saghe; i giochi restano in catalog_games.';
comment on table public.franchise_games is 'Relazioni tra franchise e match_key con ordini di uscita e narrativo.';
comment on table public.editorial_collections is 'Collezioni ufficiali curate dagli amministratori, distinte dalle liste utente.';
comment on table public.editorial_collection_games is 'Elementi ordinati delle collezioni editoriali senza duplicare il catalogo.';
