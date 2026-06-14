-- The Free Vault v5.0 — Universal Game Database, fase 1.
--
-- Rende public.games il database Master indipendente dagli store e mantiene
-- catalog_games come read model compatibile con il frontend v4.x. Gli import
-- Steam/Epic/PlayStation continuano a funzionare; IGDB aggiunge giochi storici,
-- delistati e retro anche quando non esiste alcuna listing commerciale.

-- ---------------------------------------------------------------------------
-- 1. Enciclopedia Master
-- ---------------------------------------------------------------------------

alter table public.games
  add column if not exists slug text,
  add column if not exists original_title text,
  add column if not exists summary text,
  add column if not exists storyline text,
  add column if not exists first_release_date date,
  add column if not exists cover_url text,
  add column if not exists source_url text,
  add column if not exists source_provider text,
  add column if not exists source_external_id text,
  add column if not exists source_checksum text,
  add column if not exists source_updated_at timestamptz,
  add column if not exists game_type text,
  add column if not exists game_status text,
  add column if not exists alternative_titles text[] not null default '{}',
  add column if not exists metadata jsonb not null default '{}'::jsonb;

create unique index if not exists games_source_identity_uidx
on public.games(source_provider, source_external_id)
where source_provider is not null and source_external_id is not null;

create index if not exists games_first_release_date_idx
on public.games(first_release_date desc nulls last, id);

create index if not exists games_source_updated_at_idx
on public.games(source_provider, source_updated_at desc nulls last);

create index if not exists games_alternative_titles_idx
on public.games using gin(alternative_titles);

create table if not exists public.platforms (
  id text primary key,
  name text not null,
  slug text not null,
  abbreviation text,
  family text,
  generation integer,
  manufacturer text,
  source_provider text,
  source_external_id text,
  source_checksum text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (source_provider, source_external_id)
);

create index if not exists platforms_slug_idx
on public.platforms(slug);

create table if not exists public.game_titles (
  id uuid primary key default gen_random_uuid(),
  game_id text not null references public.games(id) on delete cascade,
  title text not null,
  normalized_title text not null,
  title_type text not null default 'alternative'
    check (title_type in ('primary', 'original', 'alternative', 'regional')),
  locale text,
  source_provider text not null default 'manual',
  source_external_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (game_id, title, title_type, source_provider)
);

create index if not exists game_titles_game_id_idx
on public.game_titles(game_id);

create index if not exists game_titles_normalized_idx
on public.game_titles(normalized_title);

alter table public.game_releases
  add column if not exists platform_id text references public.platforms(id) on delete set null,
  add column if not exists region text,
  add column if not exists human_release_date text,
  add column if not exists date_precision text,
  add column if not exists release_status text,
  add column if not exists source_provider text,
  add column if not exists source_external_id text,
  add column if not exists source_checksum text,
  add column if not exists metadata jsonb not null default '{}'::jsonb;

create unique index if not exists game_releases_source_identity_uidx
on public.game_releases(source_provider, source_external_id)
where source_provider is not null and source_external_id is not null;

create index if not exists game_releases_platform_id_idx
on public.game_releases(platform_id, release_date desc nulls last);

alter table public.external_game_mappings
  add column if not exists external_type text,
  add column if not exists source_url text,
  add column if not exists metadata jsonb not null default '{}'::jsonb;

comment on table public.external_game_mappings is
'Identificatori esterni collegati al gioco Master. Il campo store contiene anche provider enciclopedici come igdb, gog e itch_io per compatibilità v3.3.1.';

create table if not exists public.game_key_aliases (
  alias_key text primary key,
  game_id text not null references public.games(id) on delete cascade,
  alias_kind text not null default 'legacy',
  provider text,
  confidence numeric(4,3) not null default 1
    check (confidence between 0 and 1),
  verified boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists game_key_aliases_game_id_idx
on public.game_key_aliases(game_id);

create table if not exists public.master_sync_state (
  provider text primary key,
  run_id uuid,
  status text not null default 'idle'
    check (status in ('idle', 'running', 'paused', 'completed', 'failed')),
  cursor_id bigint not null default 0,
  imported_count bigint not null default 0,
  batch_count bigint not null default 0,
  started_at timestamptz,
  completed_at timestamptz,
  error_message text,
  metadata jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- 2. Collegamento graduale dei dati utente/editoriali al Master
-- ---------------------------------------------------------------------------

alter table public.user_library
  add column if not exists game_id text references public.games(id) on delete set null;

alter table public.game_reviews
  add column if not exists game_id text references public.games(id) on delete set null;

alter table public.user_game_progress
  add column if not exists game_id text references public.games(id) on delete set null;

alter table public.game_diary_entries
  add column if not exists game_id text references public.games(id) on delete set null;

alter table public.user_owned_listings
  add column if not exists game_id text references public.games(id) on delete set null;

alter table public.franchise_games
  add column if not exists game_id text references public.games(id) on delete set null;

alter table public.editorial_collection_games
  add column if not exists game_id text references public.games(id) on delete set null;

create index if not exists user_library_game_id_idx on public.user_library(game_id);
create index if not exists game_reviews_game_id_idx on public.game_reviews(game_id);
create index if not exists user_game_progress_game_id_idx on public.user_game_progress(game_id);
create index if not exists game_diary_entries_game_id_idx on public.game_diary_entries(game_id);
create index if not exists user_owned_listings_game_id_idx on public.user_owned_listings(game_id);
create index if not exists franchise_games_game_id_idx on public.franchise_games(game_id);
create index if not exists editorial_collection_games_game_id_idx on public.editorial_collection_games(game_id);

alter table public.catalog_games
  add column if not exists source_kind text not null default 'catalog',
  add column if not exists master_game_id text references public.games(id) on delete set null;

alter table public.catalog_games
  alter column source_kind set default 'catalog';

update public.catalog_games
set source_kind = 'catalog'
where source_kind = 'store';

alter table public.catalog_games
  drop constraint if exists catalog_games_source_kind_check;

alter table public.catalog_games
  add constraint catalog_games_source_kind_check
  check (source_kind in ('catalog', 'master', 'hybrid'));

create index if not exists catalog_games_master_game_id_idx
on public.catalog_games(master_game_id);

create or replace function public.resolve_master_game_id(p_key text)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (
      select a.game_id
      from public.game_key_aliases a
      where a.alias_key = nullif(trim(p_key), '')
      limit 1
    ),
    (
      select g.id
      from public.games g
      where g.id = nullif(trim(p_key), '')
      limit 1
    ),
    (
      select cg.master_game_id
      from public.catalog_games cg
      where cg.master_game_id is not null
        and (
          cg.match_key = nullif(trim(p_key), '')
          or cg.canonical_id = nullif(trim(p_key), '')
        )
      order by case when cg.match_key = nullif(trim(p_key), '') then 0 else 1 end
      limit 1
    )
  );
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
  if new.game_id is null and nullif(trim(new.game_key), '') is not null then
    new.game_id := public.resolve_master_game_id(new.game_key);
  end if;
  return new;
end;
$$;

revoke all on function public.attach_master_game_id_from_key() from public;

-- Tutte queste tabelle hanno game_key; il trigger mantiene le RPC/frontend v4.x
-- compatibili mentre popola gradualmente il riferimento Master.
drop trigger if exists user_library_attach_master_game on public.user_library;
create trigger user_library_attach_master_game
before insert or update of game_key on public.user_library
for each row execute function public.attach_master_game_id_from_key();

drop trigger if exists game_reviews_attach_master_game on public.game_reviews;
create trigger game_reviews_attach_master_game
before insert or update of game_key on public.game_reviews
for each row execute function public.attach_master_game_id_from_key();

drop trigger if exists user_game_progress_attach_master_game on public.user_game_progress;
create trigger user_game_progress_attach_master_game
before insert or update of game_key on public.user_game_progress
for each row execute function public.attach_master_game_id_from_key();

drop trigger if exists game_diary_entries_attach_master_game on public.game_diary_entries;
create trigger game_diary_entries_attach_master_game
before insert or update of game_key on public.game_diary_entries
for each row execute function public.attach_master_game_id_from_key();

drop trigger if exists franchise_games_attach_master_game on public.franchise_games;
create trigger franchise_games_attach_master_game
before insert or update of game_key on public.franchise_games
for each row execute function public.attach_master_game_id_from_key();

drop trigger if exists editorial_collection_games_attach_master_game on public.editorial_collection_games;
create trigger editorial_collection_games_attach_master_game
before insert or update of game_key on public.editorial_collection_games
for each row execute function public.attach_master_game_id_from_key();

-- ---------------------------------------------------------------------------
-- 3. RLS e permessi
-- ---------------------------------------------------------------------------

alter table public.platforms enable row level security;
alter table public.game_titles enable row level security;
alter table public.game_key_aliases enable row level security;
alter table public.master_sync_state enable row level security;

drop policy if exists "Platforms are publicly readable" on public.platforms;
create policy "Platforms are publicly readable"
on public.platforms for select using (true);

drop policy if exists "Game titles are publicly readable" on public.game_titles;
create policy "Game titles are publicly readable"
on public.game_titles for select using (true);

drop policy if exists "Game aliases are publicly readable" on public.game_key_aliases;
create policy "Game aliases are publicly readable"
on public.game_key_aliases for select using (true);

revoke all on public.platforms from anon, authenticated;
revoke all on public.game_titles from anon, authenticated;
revoke all on public.game_key_aliases from anon, authenticated;
revoke all on public.master_sync_state from anon, authenticated;

grant select on public.platforms to anon, authenticated;
grant select on public.game_titles to anon, authenticated;
grant select on public.game_key_aliases to anon, authenticated;

grant select, insert, update, delete on public.platforms to service_role;
grant select, insert, update, delete on public.game_titles to service_role;
grant select, insert, update, delete on public.game_key_aliases to service_role;
grant select, insert, update, delete on public.master_sync_state to service_role;

-- ---------------------------------------------------------------------------
-- 4. RPC di sincronizzazione IGDB, set-based e riprendibile
-- ---------------------------------------------------------------------------

create or replace function public.begin_master_catalog_sync(
  p_provider text,
  p_run_id uuid,
  p_reset_cursor boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_provider text := lower(trim(coalesce(p_provider, '')));
  v_cursor bigint := 0;
begin
  if v_provider = '' then
    raise exception 'Provider Master non valido';
  end if;
  if p_run_id is null then
    raise exception 'p_run_id non può essere nullo';
  end if;

  insert into public.master_sync_state(
    provider, run_id, status, cursor_id, imported_count, batch_count,
    started_at, completed_at, error_message, updated_at
  ) values (
    v_provider, p_run_id, 'running', 0, 0, 0,
    now(), null, null, now()
  )
  on conflict (provider) do update set
    run_id = excluded.run_id,
    status = 'running',
    cursor_id = case when p_reset_cursor then 0 else public.master_sync_state.cursor_id end,
    imported_count = case when p_reset_cursor then 0 else public.master_sync_state.imported_count end,
    batch_count = case when p_reset_cursor then 0 else public.master_sync_state.batch_count end,
    started_at = now(),
    completed_at = null,
    error_message = null,
    updated_at = now();

  select cursor_id into v_cursor
  from public.master_sync_state
  where provider = v_provider;

  return jsonb_build_object(
    'provider', v_provider,
    'run_id', p_run_id,
    'cursor_id', coalesce(v_cursor, 0)
  );
end;
$$;

create or replace function public.upsert_igdb_master_batch(
  p_run_id uuid,
  p_cursor_id bigint,
  p_games jsonb,
  p_platforms jsonb default '[]'::jsonb,
  p_releases jsonb default '[]'::jsonb,
  p_external_ids jsonb default '[]'::jsonb,
  p_titles jsonb default '[]'::jsonb,
  p_aliases jsonb default '[]'::jsonb,
  p_projections jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
set statement_timeout = '90s'
as $$
declare
  v_game_count integer := 0;
  v_platform_count integer := 0;
  v_release_count integer := 0;
  v_mapping_count integer := 0;
begin
  if p_run_id is null then
    raise exception 'p_run_id non può essere nullo';
  end if;
  if p_games is null or jsonb_typeof(p_games) <> 'array' then
    raise exception 'p_games deve essere un array JSON';
  end if;

  -- Piattaforme
  with input as (
    select *
    from jsonb_to_recordset(coalesce(p_platforms, '[]'::jsonb)) as x(
      id text,
      name text,
      slug text,
      abbreviation text,
      family text,
      generation integer,
      manufacturer text,
      source_provider text,
      source_external_id text,
      source_checksum text,
      metadata jsonb
    )
  ), upserted as (
    insert into public.platforms(
      id, name, slug, abbreviation, family, generation, manufacturer,
      source_provider, source_external_id, source_checksum, metadata, updated_at
    )
    select
      id,
      coalesce(nullif(trim(name), ''), id),
      coalesce(nullif(trim(slug), ''), id),
      nullif(trim(abbreviation), ''),
      nullif(trim(family), ''),
      generation,
      nullif(trim(manufacturer), ''),
      nullif(trim(source_provider), ''),
      nullif(trim(source_external_id), ''),
      nullif(trim(source_checksum), ''),
      coalesce(metadata, '{}'::jsonb),
      now()
    from input
    where nullif(trim(id), '') is not null
    on conflict (id) do update set
      name = excluded.name,
      slug = excluded.slug,
      abbreviation = excluded.abbreviation,
      family = excluded.family,
      generation = excluded.generation,
      manufacturer = excluded.manufacturer,
      source_provider = excluded.source_provider,
      source_external_id = excluded.source_external_id,
      source_checksum = excluded.source_checksum,
      metadata = excluded.metadata,
      updated_at = now()
    returning 1
  )
  select count(*) into v_platform_count from upserted;

  -- Giochi Master
  with input as (
    select *
    from jsonb_to_recordset(p_games) as x(
      id text,
      title text,
      normalized_title text,
      slug text,
      original_title text,
      summary text,
      storyline text,
      first_release_date text,
      developer text,
      publisher text,
      market_segment text,
      genres jsonb,
      cover_url text,
      source_url text,
      source_provider text,
      source_external_id text,
      source_checksum text,
      source_updated_at text,
      game_type text,
      game_status text,
      alternative_titles jsonb,
      metadata jsonb
    )
  ), prepared as (
    select
      id,
      nullif(trim(title), '') as title,
      coalesce(nullif(trim(normalized_title), ''), lower(trim(title))) as normalized_title,
      nullif(trim(slug), '') as slug,
      nullif(trim(original_title), '') as original_title,
      nullif(trim(summary), '') as summary,
      nullif(trim(storyline), '') as storyline,
      public.catalog_safe_date(nullif(trim(first_release_date), '')) as first_release_date,
      nullif(trim(developer), '') as developer,
      nullif(trim(publisher), '') as publisher,
      case when market_segment in ('aaa', 'indie', 'unclassified') then market_segment else 'unclassified' end as market_segment,
      array(
        select distinct value
        from jsonb_array_elements_text(case when jsonb_typeof(genres) = 'array' then genres else '[]'::jsonb end) g(value)
        where nullif(trim(value), '') is not null
        order by value
      ) as genres,
      nullif(trim(cover_url), '') as cover_url,
      nullif(trim(source_url), '') as source_url,
      nullif(trim(source_provider), '') as source_provider,
      nullif(trim(source_external_id), '') as source_external_id,
      nullif(trim(source_checksum), '') as source_checksum,
      case
        when nullif(trim(source_updated_at), '') is null then null
        else source_updated_at::timestamptz
      end as source_updated_at,
      nullif(trim(game_type), '') as game_type,
      nullif(trim(game_status), '') as game_status,
      array(
        select distinct value
        from jsonb_array_elements_text(case when jsonb_typeof(alternative_titles) = 'array' then alternative_titles else '[]'::jsonb end) a(value)
        where nullif(trim(value), '') is not null
        order by value
      ) as alternative_titles,
      coalesce(metadata, '{}'::jsonb) as metadata
    from input
    where nullif(trim(id), '') is not null
      and nullif(trim(title), '') is not null
  ), upserted as (
    insert into public.games(
      id, title, normalized_title, description, release_date, developer, publisher,
      market_segment, genres, slug, original_title, summary, storyline,
      first_release_date, cover_url, source_url, source_provider,
      source_external_id, source_checksum, source_updated_at, game_type,
      game_status, alternative_titles, metadata, updated_at
    )
    select
      id, title, normalized_title, summary, first_release_date, developer, publisher,
      market_segment, genres, slug, original_title, summary, storyline,
      first_release_date, cover_url, source_url, source_provider,
      source_external_id, source_checksum, source_updated_at, game_type,
      game_status, alternative_titles, metadata, now()
    from prepared
    on conflict (id) do update set
      title = excluded.title,
      normalized_title = excluded.normalized_title,
      description = excluded.description,
      release_date = excluded.release_date,
      developer = excluded.developer,
      publisher = excluded.publisher,
      market_segment = excluded.market_segment,
      genres = excluded.genres,
      slug = excluded.slug,
      original_title = excluded.original_title,
      summary = excluded.summary,
      storyline = excluded.storyline,
      first_release_date = excluded.first_release_date,
      cover_url = excluded.cover_url,
      source_url = excluded.source_url,
      source_provider = excluded.source_provider,
      source_external_id = excluded.source_external_id,
      source_checksum = excluded.source_checksum,
      source_updated_at = excluded.source_updated_at,
      game_type = excluded.game_type,
      game_status = excluded.game_status,
      alternative_titles = excluded.alternative_titles,
      metadata = excluded.metadata,
      updated_at = now()
    returning 1
  )
  select count(*) into v_game_count from upserted;

  -- Release storiche per piattaforma. L'indice parziale evita duplicati IGDB.
  with input as (
    select *
    from jsonb_to_recordset(coalesce(p_releases, '[]'::jsonb)) as x(
      game_id text,
      platform_id text,
      platform_family text,
      edition_name text,
      release_date text,
      region text,
      human_release_date text,
      date_precision text,
      release_status text,
      source_provider text,
      source_external_id text,
      source_checksum text,
      metadata jsonb
    )
  ), inserted as (
    insert into public.game_releases(
      game_id, platform_id, platform_family, edition_name, release_date,
      region, human_release_date, date_precision, release_status,
      source_provider, source_external_id, source_checksum, metadata, updated_at
    )
    select
      game_id,
      nullif(trim(platform_id), ''),
      case
        when platform_family in ('pc', 'playstation', 'xbox', 'nintendo', 'other') then platform_family
        else 'other'
      end,
      nullif(trim(edition_name), ''),
      public.catalog_safe_date(nullif(trim(release_date), '')),
      nullif(trim(region), ''),
      nullif(trim(human_release_date), ''),
      nullif(trim(date_precision), ''),
      nullif(trim(release_status), ''),
      nullif(trim(source_provider), ''),
      nullif(trim(source_external_id), ''),
      nullif(trim(source_checksum), ''),
      coalesce(metadata, '{}'::jsonb),
      now()
    from input
    where nullif(trim(game_id), '') is not null
      and exists(select 1 from public.games g where g.id = input.game_id)
    on conflict do nothing
    returning 1
  )
  select count(*) into v_release_count from inserted;

  -- Aggiorna anche release già note senza dipendere dall'inferenza dell'indice parziale.
  with input as (
    select *
    from jsonb_to_recordset(coalesce(p_releases, '[]'::jsonb)) as x(
      game_id text,
      platform_id text,
      platform_family text,
      edition_name text,
      release_date text,
      region text,
      human_release_date text,
      date_precision text,
      release_status text,
      source_provider text,
      source_external_id text,
      source_checksum text,
      metadata jsonb
    )
  )
  update public.game_releases gr
  set
    game_id = input.game_id,
    platform_id = nullif(trim(input.platform_id), ''),
    platform_family = case
      when input.platform_family in ('pc', 'playstation', 'xbox', 'nintendo', 'other') then input.platform_family
      else 'other'
    end,
    release_date = public.catalog_safe_date(nullif(trim(input.release_date), '')),
    region = nullif(trim(input.region), ''),
    human_release_date = nullif(trim(input.human_release_date), ''),
    date_precision = nullif(trim(input.date_precision), ''),
    release_status = nullif(trim(input.release_status), ''),
    source_checksum = nullif(trim(input.source_checksum), ''),
    metadata = coalesce(input.metadata, '{}'::jsonb),
    updated_at = now()
  from input
  where gr.source_provider = nullif(trim(input.source_provider), '')
    and gr.source_external_id = nullif(trim(input.source_external_id), '');

  -- ID esterni: IGDB stesso, Steam, Epic, PlayStation Store, GOG, ecc.
  with input as (
    select *
    from jsonb_to_recordset(coalesce(p_external_ids, '[]'::jsonb)) as x(
      provider text,
      external_id text,
      game_id text,
      external_type text,
      source_url text,
      confidence numeric,
      verified boolean,
      metadata jsonb
    )
  ), upserted as (
    insert into public.external_game_mappings(
      store, external_id, game_id, confidence, verified, mapping_source,
      external_type, source_url, metadata, updated_at
    )
    select
      lower(trim(provider)),
      trim(external_id),
      game_id,
      greatest(0, least(coalesce(confidence, 1), 1)),
      coalesce(verified, true),
      'external_id',
      nullif(trim(external_type), ''),
      nullif(trim(source_url), ''),
      coalesce(metadata, '{}'::jsonb),
      now()
    from input
    where nullif(trim(provider), '') is not null
      and nullif(trim(external_id), '') is not null
      and exists(select 1 from public.games g where g.id = input.game_id)
    on conflict (store, external_id) do update set
      game_id = excluded.game_id,
      confidence = excluded.confidence,
      verified = excluded.verified,
      mapping_source = excluded.mapping_source,
      external_type = excluded.external_type,
      source_url = excluded.source_url,
      metadata = excluded.metadata,
      updated_at = now()
    returning 1
  )
  select count(*) into v_mapping_count from upserted;

  -- Titoli alternativi e regionali.
  insert into public.game_titles(
    game_id, title, normalized_title, title_type, locale,
    source_provider, source_external_id, updated_at
  )
  select
    game_id,
    trim(title),
    trim(normalized_title),
    case when title_type in ('primary', 'original', 'alternative', 'regional') then title_type else 'alternative' end,
    nullif(trim(locale), ''),
    coalesce(nullif(trim(source_provider), ''), 'igdb'),
    nullif(trim(source_external_id), ''),
    now()
  from jsonb_to_recordset(coalesce(p_titles, '[]'::jsonb)) as x(
    game_id text,
    title text,
    normalized_title text,
    title_type text,
    locale text,
    source_provider text,
    source_external_id text
  )
  where nullif(trim(game_id), '') is not null
    and nullif(trim(title), '') is not null
    and nullif(trim(normalized_title), '') is not null
    and exists(select 1 from public.games g where g.id = x.game_id)
  on conflict (game_id, title, title_type, source_provider) do update set
    normalized_title = excluded.normalized_title,
    locale = excluded.locale,
    source_external_id = excluded.source_external_id,
    updated_at = now();

  -- Alias compatibili con game_key v4.x.
  insert into public.game_key_aliases(
    alias_key, game_id, alias_kind, provider, confidence, verified, updated_at
  )
  select
    trim(alias_key),
    game_id,
    coalesce(nullif(trim(alias_kind), ''), 'legacy'),
    nullif(trim(provider), ''),
    greatest(0, least(coalesce(confidence, 1), 1)),
    coalesce(verified, true),
    now()
  from jsonb_to_recordset(coalesce(p_aliases, '[]'::jsonb)) as x(
    alias_key text,
    game_id text,
    alias_kind text,
    provider text,
    confidence numeric,
    verified boolean
  )
  where nullif(trim(alias_key), '') is not null
    and exists(select 1 from public.games g where g.id = x.game_id)
  on conflict (alias_key) do update set
    game_id = excluded.game_id,
    alias_kind = excluded.alias_kind,
    provider = excluded.provider,
    confidence = excluded.confidence,
    verified = excluded.verified,
    updated_at = now();

  -- Read model: i giochi senza store diventano subito cercabili e recensibili.
  insert into public.catalog_games(
    match_key, canonical_id, title, canonical_title, description,
    developer, publisher, image_url, store_url, release_date, release_year,
    market_segment, category_group, offer_type, platforms, genres,
    categories, stores, store_listings, sort_price, index_run_id,
    source_kind, master_game_id, updated_at
  )
  select
    trim(match_key),
    trim(canonical_id),
    trim(title),
    coalesce(nullif(trim(canonical_title), ''), trim(title)),
    nullif(trim(description), ''),
    nullif(trim(developer), ''),
    nullif(trim(publisher), ''),
    nullif(trim(image_url), ''),
    nullif(trim(store_url), ''),
    public.catalog_safe_date(nullif(trim(release_date), '')),
    release_year,
    case when market_segment in ('aaa', 'indie', 'unclassified') then market_segment else 'unclassified' end,
    coalesce(nullif(trim(category_group), ''), 'other'),
    coalesce(nullif(trim(offer_type), ''), 'IGDB_MASTER'),
    array(
      select distinct value
      from jsonb_array_elements_text(case when jsonb_typeof(platforms) = 'array' then platforms else '[]'::jsonb end) p(value)
      where nullif(trim(value), '') is not null
      order by value
    ),
    array(
      select distinct value
      from jsonb_array_elements_text(case when jsonb_typeof(genres) = 'array' then genres else '[]'::jsonb end) g(value)
      where nullif(trim(value), '') is not null
      order by value
    ),
    array(
      select distinct value
      from jsonb_array_elements_text(case when jsonb_typeof(categories) = 'array' then categories else '[]'::jsonb end) c(value)
      where nullif(trim(value), '') is not null
      order by value
    ),
    '{}'::text[],
    '[]'::jsonb,
    0,
    p_run_id,
    'master',
    trim(master_game_id),
    now()
  from jsonb_to_recordset(coalesce(p_projections, '[]'::jsonb)) as x(
    match_key text,
    canonical_id text,
    master_game_id text,
    title text,
    canonical_title text,
    description text,
    developer text,
    publisher text,
    image_url text,
    store_url text,
    release_date text,
    release_year integer,
    market_segment text,
    category_group text,
    offer_type text,
    platforms jsonb,
    genres jsonb,
    categories jsonb
  )
  where nullif(trim(match_key), '') is not null
    and nullif(trim(master_game_id), '') is not null
    and exists(select 1 from public.games g where g.id = x.master_game_id)
  on conflict (match_key) do update set
    canonical_id = excluded.canonical_id,
    title = excluded.title,
    canonical_title = excluded.canonical_title,
    description = excluded.description,
    developer = excluded.developer,
    publisher = excluded.publisher,
    image_url = excluded.image_url,
    store_url = excluded.store_url,
    release_date = excluded.release_date,
    release_year = excluded.release_year,
    market_segment = excluded.market_segment,
    category_group = excluded.category_group,
    offer_type = excluded.offer_type,
    platforms = excluded.platforms,
    genres = excluded.genres,
    categories = excluded.categories,
    index_run_id = excluded.index_run_id,
    source_kind = 'master',
    master_game_id = excluded.master_game_id,
    updated_at = now();

  update public.master_sync_state
  set
    cursor_id = greatest(cursor_id, coalesce(p_cursor_id, cursor_id)),
    imported_count = imported_count + v_game_count,
    batch_count = batch_count + 1,
    metadata = metadata || jsonb_build_object(
      'last_batch_games', v_game_count,
      'last_batch_platforms', v_platform_count,
      'last_batch_releases', v_release_count,
      'last_batch_mappings', v_mapping_count
    ),
    updated_at = now()
  where provider = 'igdb'
    and run_id = p_run_id;

  return jsonb_build_object(
    'games', v_game_count,
    'platforms', v_platform_count,
    'releases_inserted', v_release_count,
    'external_ids', v_mapping_count,
    'cursor_id', p_cursor_id
  );
end;
$$;

create or replace function public.finish_master_catalog_sync(
  p_provider text,
  p_run_id uuid,
  p_complete boolean,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_provider text := lower(trim(coalesce(p_provider, '')));
  v_total_games bigint := 0;
  v_total_listings bigint := 0;
  v_stores jsonb := '{}'::jsonb;
  v_years jsonb := '[]'::jsonb;
  v_state public.master_sync_state%rowtype;
begin
  update public.master_sync_state
  set
    status = case when p_complete then 'completed' else 'paused' end,
    completed_at = case when p_complete then now() else null end,
    error_message = null,
    metadata = metadata || coalesce(p_metadata, '{}'::jsonb),
    updated_at = now()
  where provider = v_provider and run_id = p_run_id
  returning * into v_state;

  if not found then
    raise exception 'Sincronizzazione Master non trovata: provider=% run=%', v_provider, p_run_id;
  end if;

  select count(*) into v_total_games from public.catalog_games;

  select
    coalesce(total_listings, 0),
    coalesce(stores, '{}'::jsonb)
  into v_total_listings, v_stores
  from public.catalog_stats_cache
  where singleton;

  select coalesce(jsonb_agg(y order by y desc), '[]'::jsonb)
  into v_years
  from (
    select distinct release_year as y
    from public.catalog_games
    where release_year is not null
  ) years;

  insert into public.catalog_stats_cache(
    singleton, run_id, status, total_listings, total_games,
    stores, years, completed_at, error_message, updated_at
  ) values (
    true, p_run_id, 'completed', v_total_listings, v_total_games,
    v_stores, v_years, now(), null, now()
  )
  on conflict (singleton) do update set
    run_id = excluded.run_id,
    status = 'completed',
    total_listings = excluded.total_listings,
    total_games = excluded.total_games,
    stores = excluded.stores,
    years = excluded.years,
    completed_at = now(),
    error_message = null,
    updated_at = now();

  return jsonb_build_object(
    'provider', v_provider,
    'status', v_state.status,
    'cursor_id', v_state.cursor_id,
    'imported_count', v_state.imported_count,
    'batch_count', v_state.batch_count,
    'total_games', v_total_games
  );
end;
$$;

create or replace function public.fail_master_catalog_sync(
  p_provider text,
  p_run_id uuid,
  p_error_message text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.master_sync_state
  set
    status = 'failed',
    error_message = left(coalesce(p_error_message, 'Errore sconosciuto'), 4000),
    completed_at = now(),
    updated_at = now()
  where provider = lower(trim(coalesce(p_provider, '')))
    and run_id = p_run_id;
end;
$$;

revoke all on function public.begin_master_catalog_sync(text, uuid, boolean) from public;
revoke all on function public.upsert_igdb_master_batch(uuid, bigint, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb) from public;
revoke all on function public.finish_master_catalog_sync(text, uuid, boolean, jsonb) from public;
revoke all on function public.fail_master_catalog_sync(text, uuid, text) from public;

grant execute on function public.begin_master_catalog_sync(text, uuid, boolean) to service_role;
grant execute on function public.upsert_igdb_master_batch(uuid, bigint, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb) to service_role;
grant execute on function public.finish_master_catalog_sync(text, uuid, boolean, jsonb) to service_role;
grant execute on function public.fail_master_catalog_sync(text, uuid, text) to service_role;

-- ---------------------------------------------------------------------------
-- 5. RPC pubbliche compatibili con giochi Master privi di listing
-- ---------------------------------------------------------------------------

create or replace function public.catalog_game_card_json(p_game public.catalog_games)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'canonical_id', (p_game).canonical_id,
    'match_key', (p_game).match_key,
    'master_game_id', (p_game).master_game_id,
    'internal_id', (p_game).canonical_id,
    'listing_id', ((p_game).store_listings -> 0 ->> 'listing_id'),
    'source_kind', (p_game).source_kind,
    'store', ((p_game).store_listings -> 0 ->> 'store'),
    'stores', to_jsonb((p_game).stores),
    'store_listings', (p_game).store_listings,
    'title', (p_game).title,
    'canonical_title', (p_game).canonical_title,
    'description', (p_game).description,
    'developer', (p_game).developer,
    'publisher', (p_game).publisher,
    'image_url', (p_game).image_url,
    'store_url', (p_game).store_url,
    'release_date', (p_game).release_date,
    'release_year', (p_game).release_year,
    'market_segment', (p_game).market_segment,
    'category_group', (p_game).category_group,
    'offer_type', (p_game).offer_type,
    'platforms', to_jsonb((p_game).platforms),
    'genres', to_jsonb((p_game).genres),
    'categories', to_jsonb((p_game).categories),
    'original_price', ((p_game).store_listings -> 0 -> 'original_price'),
    'discount_price', ((p_game).store_listings -> 0 -> 'discount_price'),
    'currency_code', ((p_game).store_listings -> 0 ->> 'currency_code'),
    'fmt_original_price', ((p_game).store_listings -> 0 ->> 'fmt_original_price'),
    'fmt_discount_price', ((p_game).store_listings -> 0 ->> 'fmt_discount_price')
  );
$$;

revoke all on function public.catalog_game_card_json(public.catalog_games) from public;

create or replace function public.get_catalog_game(p_key text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
with resolved as (
  select coalesce(public.resolve_master_game_id(p_key), '') as master_game_id
), target as (
  select cg as game
  from public.catalog_games cg
  cross join resolved r
  where cg.match_key = p_key
     or cg.canonical_id = p_key
     or cg.master_game_id = nullif(r.master_game_id, '')
     or exists (
       select 1
       from jsonb_array_elements(cg.store_listings) listing
       where listing ->> 'listing_id' = p_key
     )
  order by
    case
      when cg.match_key = p_key then 0
      when cg.canonical_id = p_key then 1
      when cg.master_game_id = nullif(r.master_game_id, '') then 2
      else 3
    end,
    case cg.source_kind when 'hybrid' then 0 when 'master' then 1 else 2 end
  limit 1
)
select public.catalog_game_card_json(game)
from target;
$$;

create or replace function public.get_catalog_games(p_keys text[])
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
with requested as (
  select distinct unnest(coalesce(p_keys, '{}'::text[])) as requested_key
), resolved as (
  select
    requested_key,
    public.resolve_master_game_id(requested_key) as master_game_id
  from requested
), ranked as (
  select
    r.requested_key,
    cg as game,
    row_number() over (
      partition by r.requested_key
      order by
        case
          when cg.match_key = r.requested_key then 0
          when cg.canonical_id = r.requested_key then 1
          when cg.master_game_id = r.master_game_id then 2
          else 3
        end,
        case cg.source_kind when 'hybrid' then 0 when 'master' then 1 else 2 end
    ) as rn
  from resolved r
  join public.catalog_games cg
    on cg.match_key = r.requested_key
    or cg.canonical_id = r.requested_key
    or (r.master_game_id is not null and cg.master_game_id = r.master_game_id)
    or exists (
      select 1
      from jsonb_array_elements(cg.store_listings) listing
      where listing ->> 'listing_id' = r.requested_key
    )
)
select coalesce(jsonb_agg(public.catalog_game_card_json(game) order by requested_key), '[]'::jsonb)
from ranked
where rn = 1;
$$;

revoke all on function public.get_catalog_game(text) from public;
revoke all on function public.get_catalog_games(text[]) from public;
grant execute on function public.get_catalog_game(text) to anon, authenticated;
grant execute on function public.get_catalog_games(text[]) to anon, authenticated;


-- Il rebuild legacy deve rigenerare soltanto le proiezioni provenienti dagli
-- store. Le schede Master non dipendono da catalog_items e non vanno eliminate.
create or replace function public.finalize_catalog_index_rebuild(p_run_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
set statement_timeout = '120s'
as $$
declare
  v_total_games bigint := 0;
  v_total_listings bigint := 0;
  v_stores jsonb := '{}'::jsonb;
  v_years jsonb := '[]'::jsonb;
begin
  delete from public.catalog_games
  where source_kind <> 'master'
    and index_run_id <> p_run_id;

  select count(*) into v_total_games
  from public.catalog_games;

  select
    coalesce(sum(css.listing_count), 0),
    coalesce(jsonb_object_agg(css.store, css.listing_count), '{}'::jsonb)
  into v_total_listings, v_stores
  from public.catalog_sync_state css
  where css.status = 'completed';

  select coalesce(jsonb_agg(y.release_year order by y.release_year desc), '[]'::jsonb)
  into v_years
  from (
    select distinct cg.release_year
    from public.catalog_games cg
    where cg.release_year is not null
  ) y;

  insert into public.catalog_stats_cache (
    singleton, run_id, status, total_listings, total_games,
    stores, years, completed_at, error_message, updated_at
  ) values (
    true, p_run_id, 'completed', v_total_listings, v_total_games,
    v_stores, v_years, now(), null, now()
  )
  on conflict (singleton) do update set
    run_id = excluded.run_id,
    status = 'completed',
    total_listings = excluded.total_listings,
    total_games = excluded.total_games,
    stores = excluded.stores,
    years = excluded.years,
    completed_at = now(),
    error_message = null,
    updated_at = now();

  return jsonb_build_object(
    'run_id', p_run_id,
    'total_listings', v_total_listings,
    'total_games', v_total_games,
    'stores', v_stores,
    'years', v_years
  );
end;
$$;

revoke all on function public.finalize_catalog_index_rebuild(uuid) from public;
grant execute on function public.finalize_catalog_index_rebuild(uuid) to service_role;

-- Lo stato Master compare nel pannello di sistema senza alterare il contratto
-- esistente di catalog_stats.
create or replace function public.catalog_stats()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'total_listings', coalesce(cache.total_listings, 0),
    'total_games', coalesce(cache.total_games, 0),
    'stores', coalesce(cache.stores, '{}'::jsonb),
    'years', coalesce(cache.years, '[]'::jsonb),
    'sync', coalesce((
      select jsonb_agg(to_jsonb(css) order by css.store)
      from public.catalog_sync_state css
    ), '[]'::jsonb),
    'master_sync', coalesce((
      select jsonb_agg(to_jsonb(mss) order by mss.provider)
      from public.master_sync_state mss
    ), '[]'::jsonb)
  )
  from (
    select total_listings, total_games, stores, years
    from public.catalog_stats_cache
    where singleton
  ) cache
  right join (select 1) fallback on true;
$$;

revoke all on function public.catalog_stats() from public;
grant execute on function public.catalog_stats() to anon, authenticated;

create or replace function public.admin_system_status()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
set statement_timeout = '10s'
as $$
declare
  stats jsonb;
  sync_rows jsonb;
  master_sync_rows jsonb;
  master_games bigint := 0;
  master_size bigint := 0;
begin
  if not public.is_admin() then
    raise exception 'Accesso amministratore richiesto' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(to_jsonb(s) order by s.store), '[]'::jsonb)
  into sync_rows
  from public.catalog_sync_state s;

  select coalesce(jsonb_agg(to_jsonb(s) order by s.provider), '[]'::jsonb)
  into master_sync_rows
  from public.master_sync_state s;

  select count(*) into master_games
  from public.games
  where source_provider is not null;

  master_size :=
    pg_total_relation_size('public.games'::regclass)
    + pg_total_relation_size('public.game_releases'::regclass)
    + pg_total_relation_size('public.platforms'::regclass)
    + pg_total_relation_size('public.game_titles'::regclass)
    + pg_total_relation_size('public.external_game_mappings'::regclass);

  select jsonb_build_object(
    'database_size_bytes', pg_database_size(current_database()),
    'catalog_size_bytes', pg_total_relation_size('public.catalog_games'::regclass),
    'master_size_bytes', master_size,
    'catalog_games', coalesce(c.total_games, 0),
    'catalog_listings', coalesce(c.total_listings, 0),
    'master_games', master_games,
    'catalog_status', coalesce(c.status, 'unknown'),
    'catalog_updated_at', c.updated_at,
    'open_reports', (select count(*) from public.moderation_reports where status = 'open'),
    'pending_matches', (select count(*) from public.canonical_match_queue where status = 'pending'),
    'sync', sync_rows,
    'master_sync', master_sync_rows
  ) into stats
  from public.catalog_stats_cache c
  where c.singleton;

  if stats is null then
    stats := jsonb_build_object(
      'database_size_bytes', pg_database_size(current_database()),
      'catalog_size_bytes', pg_total_relation_size('public.catalog_games'::regclass),
      'master_size_bytes', master_size,
      'catalog_games', 0,
      'catalog_listings', 0,
      'master_games', master_games,
      'catalog_status', 'unknown',
      'open_reports', (select count(*) from public.moderation_reports where status = 'open'),
      'pending_matches', (select count(*) from public.canonical_match_queue where status = 'pending'),
      'sync', sync_rows,
      'master_sync', master_sync_rows
    );
  end if;
  return stats;
end;
$$;

revoke all on function public.admin_system_status() from public;
grant execute on function public.admin_system_status() to authenticated;

comment on table public.games is
'Enciclopedia Master indipendente dagli store. Un gioco può esistere senza alcuna listing commerciale.';

comment on table public.platforms is
'Piattaforme storiche e moderne del database Master.';

comment on table public.game_key_aliases is
'Ponte tra game_key legacy, ID provider e identità Master.';

comment on table public.master_sync_state is
'Checkpoint riprendibile delle importazioni enciclopediche, inizialmente IGDB.';
