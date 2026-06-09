-- The Free Vault v3.3 — recensioni, voti e contenuti pubblici

create unique index if not exists profiles_username_lower_unique
on public.profiles (lower(username));

create table if not exists public.game_reviews (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null
    constraint game_reviews_user_id_fkey
    references public.profiles(id) on delete cascade,
  game_key text not null,
  game_title text not null check (char_length(game_title) between 1 and 200),
  game_image_url text,
  store_url text,
  rating smallint not null check (rating between 1 and 5),
  title text check (title is null or char_length(title) <= 120),
  body text check (body is null or char_length(body) <= 5000),
  contains_spoilers boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, game_key)
);

create index if not exists game_reviews_game_key_idx
on public.game_reviews (game_key, updated_at desc);

create index if not exists game_reviews_user_id_idx
on public.game_reviews (user_id, updated_at desc);

-- Helper usato dalle policy per rispettare profilo e preferenze di privacy.
create or replace function public.can_view_user_content(
  owner_id uuid,
  content_kind text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.profiles p
    left join public.user_settings s on s.user_id = p.id
    where p.id = owner_id
      and p.is_public = true
      and case content_kind
        when 'lists' then coalesce(s.show_lists, true)
        when 'activity' then coalesce(s.show_activity, true)
        when 'library' then coalesce(s.show_library, true)
        else false
      end
  );
$$;

revoke all on function public.can_view_user_content(uuid, text) from public;
grant execute on function public.can_view_user_content(uuid, text) to anon, authenticated;

alter table public.game_reviews enable row level security;

drop policy if exists "Public or own reviews are readable" on public.game_reviews;
create policy "Public or own reviews are readable"
on public.game_reviews for select
using (
  (select auth.uid()) = user_id
  or public.can_view_user_content(user_id, 'activity')
);

drop policy if exists "Users insert own reviews" on public.game_reviews;
create policy "Users insert own reviews"
on public.game_reviews for insert
to authenticated
with check ((select auth.uid()) = user_id);

drop policy if exists "Users update own reviews" on public.game_reviews;
create policy "Users update own reviews"
on public.game_reviews for update
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

drop policy if exists "Users delete own reviews" on public.game_reviews;
create policy "Users delete own reviews"
on public.game_reviews for delete
to authenticated
using ((select auth.uid()) = user_id);

-- Le liste dichiarate pubbliche sono visibili soltanto se il profilo e la
-- relativa preferenza di privacy lo consentono. Il proprietario vede sempre le proprie.
drop policy if exists "Users read own or public lists" on public.user_lists;
create policy "Users read own or public lists"
on public.user_lists for select
using (
  (select auth.uid()) = user_id
  or (
    visibility = 'public'
    and public.can_view_user_content(user_id, 'lists')
  )
);

grant select on public.game_reviews to anon, authenticated;
grant insert, update, delete on public.game_reviews to authenticated;
