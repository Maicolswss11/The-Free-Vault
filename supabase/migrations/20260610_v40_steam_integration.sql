-- The Free Vault v4.0 — integrazione Steam
-- Eseguire dopo le migrazioni v3.2–v3.4 e la fondazione multi-store v3.3.1.

create table if not exists public.steam_accounts (
  user_id uuid primary key references auth.users(id) on delete cascade,
  steam_id text not null unique check (steam_id ~ '^[0-9]{17}$'),
  persona_name text,
  profile_url text,
  avatar_url text,
  last_sync_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.steam_link_states (
  state uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  return_url text not null,
  expires_at timestamptz not null default (now() + interval '10 minutes'),
  consumed_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.user_owned_listings (
  user_id uuid not null references auth.users(id) on delete cascade,
  store text not null check (store in ('epic', 'steam', 'playstation', 'xbox', 'nintendo', 'other')),
  external_id text not null,
  listing_id text,
  canonical_id text,
  playtime_minutes integer not null default 0 check (playtime_minutes >= 0),
  acquired_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, store, external_id)
);

create table if not exists public.canonical_match_queue (
  id uuid primary key default gen_random_uuid(),
  source_store text not null,
  source_external_id text not null,
  candidate_store text not null,
  candidate_external_id text not null,
  source_title text not null,
  candidate_title text not null,
  confidence numeric(4,3) not null default 0 check (confidence between 0 and 1),
  status text not null default 'pending'
    check (status in ('pending', 'verified', 'rejected')),
  resolved_game_id text references public.games(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (source_store, source_external_id, candidate_store, candidate_external_id)
);

create index if not exists steam_accounts_steam_id_idx
on public.steam_accounts(steam_id);

create index if not exists steam_link_states_user_id_idx
on public.steam_link_states(user_id);

create index if not exists steam_link_states_expires_at_idx
on public.steam_link_states(expires_at);

create index if not exists user_owned_listings_user_store_idx
on public.user_owned_listings(user_id, store);

create index if not exists canonical_match_queue_status_idx
on public.canonical_match_queue(status, confidence desc);

alter table public.steam_accounts enable row level security;
alter table public.steam_link_states enable row level security;
alter table public.user_owned_listings enable row level security;
alter table public.canonical_match_queue enable row level security;

drop policy if exists "Users read own Steam account" on public.steam_accounts;
create policy "Users read own Steam account"
on public.steam_accounts for select
to authenticated
using ((select auth.uid()) = user_id);

drop policy if exists "Users delete own Steam account" on public.steam_accounts;
create policy "Users delete own Steam account"
on public.steam_accounts for delete
to authenticated
using ((select auth.uid()) = user_id);

drop policy if exists "Users read own owned listings" on public.user_owned_listings;
create policy "Users read own owned listings"
on public.user_owned_listings for select
to authenticated
using ((select auth.uid()) = user_id);

drop policy if exists "Users delete own owned listings" on public.user_owned_listings;
create policy "Users delete own owned listings"
on public.user_owned_listings for delete
to authenticated
using ((select auth.uid()) = user_id);

-- steam_link_states e canonical_match_queue sono gestite soltanto dalle Edge
-- Functions con secret/service role; nessuna policy client viene concessa.

comment on table public.steam_accounts is
'Collegamento verificato via Steam OpenID 2.0.';

comment on table public.user_owned_listings is
'Possesso e playtime per singola listing di store.';

comment on table public.canonical_match_queue is
'Coda di matching tra listing di store diversi per revisione futura.';
