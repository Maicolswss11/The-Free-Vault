-- The Free Vault v4.2 — Game Journal, progressi e statistiche personali.

alter table public.user_settings
  add column if not exists show_diary boolean not null default true;

create table if not exists public.user_game_progress (
  user_id uuid not null references auth.users(id) on delete cascade,
  game_key text not null,
  game_title text not null check (char_length(game_title) between 1 and 300),
  game_image_url text,
  status text not null default 'saved'
    check (status in ('saved', 'backlog', 'playing', 'paused', 'completed', 'abandoned', 'replay')),
  progress_percent smallint not null default 0
    check (progress_percent between 0 and 100),
  started_at date,
  completed_at date,
  completion_count smallint not null default 0
    check (completion_count between 0 and 999),
  manual_playtime_minutes integer not null default 0
    check (manual_playtime_minutes >= 0),
  primary_platform text check (char_length(primary_platform) <= 80),
  difficulty text check (char_length(difficulty) <= 80),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, game_key)
);

create table if not exists public.game_diary_entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  game_key text not null,
  game_title text not null check (char_length(game_title) between 1 and 300),
  game_image_url text,
  played_at date not null default current_date,
  minutes_played integer not null check (minutes_played between 1 and 1440),
  progress_percent smallint check (progress_percent between 0 and 100),
  platform text check (char_length(platform) <= 80),
  note text check (char_length(note) <= 3000),
  contains_spoilers boolean not null default false,
  visibility text not null default 'private'
    check (visibility in ('private', 'public')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists user_game_progress_user_status_idx
on public.user_game_progress (user_id, status, updated_at desc);

create index if not exists user_game_progress_game_key_idx
on public.user_game_progress (game_key);

create index if not exists game_diary_entries_user_played_idx
on public.game_diary_entries (user_id, played_at desc, created_at desc);

create index if not exists game_diary_entries_game_key_idx
on public.game_diary_entries (game_key, played_at desc);

create index if not exists game_diary_entries_public_idx
on public.game_diary_entries (user_id, played_at desc)
where visibility = 'public';

alter table public.user_game_progress enable row level security;
alter table public.game_diary_entries enable row level security;

drop policy if exists "Users manage own progress" on public.user_game_progress;
create policy "Users manage own progress"
on public.user_game_progress for all
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

drop policy if exists "Users read own or public diary entries" on public.game_diary_entries;
create policy "Users read own or public diary entries"
on public.game_diary_entries for select
to anon, authenticated
using (
  (select auth.uid()) = user_id
  or (
    visibility = 'public'
    and exists (
      select 1
      from public.profiles p
      left join public.user_settings s on s.user_id = p.id
      where p.id = game_diary_entries.user_id
        and p.is_public = true
        and coalesce(s.show_activity, true) = true
        and coalesce(s.show_diary, true) = true
    )
  )
);

drop policy if exists "Users insert own diary entries" on public.game_diary_entries;
create policy "Users insert own diary entries"
on public.game_diary_entries for insert
to authenticated
with check ((select auth.uid()) = user_id);

drop policy if exists "Users update own diary entries" on public.game_diary_entries;
create policy "Users update own diary entries"
on public.game_diary_entries for update
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

drop policy if exists "Users delete own diary entries" on public.game_diary_entries;
create policy "Users delete own diary entries"
on public.game_diary_entries for delete
to authenticated
using ((select auth.uid()) = user_id);

create or replace function public.touch_game_journal_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists user_game_progress_touch_updated_at on public.user_game_progress;
create trigger user_game_progress_touch_updated_at
before update on public.user_game_progress
for each row execute function public.touch_game_journal_updated_at();

drop trigger if exists game_diary_entries_touch_updated_at on public.game_diary_entries;
create trigger game_diary_entries_touch_updated_at
before update on public.game_diary_entries
for each row execute function public.touch_game_journal_updated_at();

grant select, insert, update, delete on public.user_game_progress to authenticated;
grant select on public.game_diary_entries to anon, authenticated;
grant insert, update, delete on public.game_diary_entries to authenticated;

comment on table public.user_game_progress is
'Progressi personali aggregati per gioco: stato, percentuale, date, completamenti e piattaforma.';

comment on table public.game_diary_entries is
'Sessioni di gioco cronologiche, private o pubbliche sul profilo.';
