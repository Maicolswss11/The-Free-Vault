-- The Free Vault v3.3.1 — fondazione catalogo multi-store
-- Queste tabelle separano il gioco canonico dalle edizioni e dalle listing dei singoli store.

create table if not exists public.games (
  id text primary key,
  title text not null,
  normalized_title text not null,
  description text,
  release_date date,
  developer text,
  publisher text,
  market_segment text not null default 'unclassified'
    check (market_segment in ('aaa', 'indie', 'unclassified')),
  genres text[] not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.game_releases (
  id uuid primary key default gen_random_uuid(),
  game_id text not null references public.games(id) on delete cascade,
  edition_name text,
  platform_family text not null
    check (platform_family in ('pc', 'playstation', 'xbox', 'nintendo', 'other')),
  release_date date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.store_listings (
  id text primary key,
  release_id uuid not null references public.game_releases(id) on delete cascade,
  store text not null
    check (store in ('epic', 'steam', 'playstation', 'xbox', 'nintendo', 'other')),
  external_id text not null,
  namespace text,
  store_url text,
  currency_code text,
  original_price integer,
  discount_price integer,
  available boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  last_synced_at timestamptz not null default now(),
  unique (store, external_id)
);

create table if not exists public.external_game_mappings (
  store text not null,
  external_id text not null,
  game_id text not null references public.games(id) on delete cascade,
  confidence numeric(4,3) not null default 0
    check (confidence >= 0 and confidence <= 1),
  verified boolean not null default false,
  mapping_source text not null default 'automatic'
    check (mapping_source in ('automatic', 'manual', 'external_id')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (store, external_id)
);

create index if not exists games_normalized_title_idx
on public.games (normalized_title);

create index if not exists game_releases_game_id_idx
on public.game_releases (game_id);

create index if not exists store_listings_release_id_idx
on public.store_listings (release_id);

create index if not exists store_listings_store_idx
on public.store_listings (store);

create index if not exists external_game_mappings_game_id_idx
on public.external_game_mappings (game_id);

alter table public.games enable row level security;
alter table public.game_releases enable row level security;
alter table public.store_listings enable row level security;
alter table public.external_game_mappings enable row level security;

drop policy if exists "Canonical games are publicly readable" on public.games;
create policy "Canonical games are publicly readable"
on public.games for select
using (true);

drop policy if exists "Game releases are publicly readable" on public.game_releases;
create policy "Game releases are publicly readable"
on public.game_releases for select
using (true);

drop policy if exists "Store listings are publicly readable" on public.store_listings;
create policy "Store listings are publicly readable"
on public.store_listings for select
using (true);

drop policy if exists "External mappings are publicly readable" on public.external_game_mappings;
create policy "External mappings are publicly readable"
on public.external_game_mappings for select
using (true);

grant select on public.games to anon, authenticated;
grant select on public.game_releases to anon, authenticated;
grant select on public.store_listings to anon, authenticated;
grant select on public.external_game_mappings to anon, authenticated;
