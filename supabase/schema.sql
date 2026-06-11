-- The Free Vault — schema utenti e sincronizzazione
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null unique check (char_length(username) between 3 and 30),
  display_name text not null check (char_length(display_name) between 1 and 60),
  bio text check (char_length(bio) <= 500),
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.user_library (
  user_id uuid not null references auth.users(id) on delete cascade,
  game_key text not null,
  data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, game_key)
);

create table if not exists public.user_lists (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 80),
  description text check (char_length(description) <= 500),
  visibility text not null default 'private' check (visibility in ('private', 'public')),
  game_keys text[] not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists user_library_user_id_idx on public.user_library(user_id);
create index if not exists user_lists_user_id_idx on public.user_lists(user_id);
create index if not exists user_lists_visibility_idx on public.user_lists(visibility);

alter table public.profiles enable row level security;
alter table public.user_library enable row level security;
alter table public.user_lists enable row level security;

drop policy if exists "Public profiles are readable" on public.profiles;
create policy "Public profiles are readable"
on public.profiles for select
using (true);

drop policy if exists "Users update own profile" on public.profiles;
create policy "Users update own profile"
on public.profiles for update
to authenticated
using ((select auth.uid()) = id)
with check ((select auth.uid()) = id);

drop policy if exists "Users insert own profile" on public.profiles;
create policy "Users insert own profile"
on public.profiles for insert
to authenticated
with check ((select auth.uid()) = id);

drop policy if exists "Users manage own library" on public.user_library;
create policy "Users manage own library"
on public.user_library for all
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

drop policy if exists "Users read own or public lists" on public.user_lists;
create policy "Users read own or public lists"
on public.user_lists for select
using (visibility = 'public' or (select auth.uid()) = user_id);

drop policy if exists "Users insert own lists" on public.user_lists;
create policy "Users insert own lists"
on public.user_lists for insert
to authenticated
with check ((select auth.uid()) = user_id);

drop policy if exists "Users update own lists" on public.user_lists;
create policy "Users update own lists"
on public.user_lists for update
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

drop policy if exists "Users delete own lists" on public.user_lists;
create policy "Users delete own lists"
on public.user_lists for delete
to authenticated
using ((select auth.uid()) = user_id);

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = ''
as $$
begin
  insert into public.profiles (id, username, display_name)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'username', 'user_' || substr(new.id::text, 1, 8)),
    coalesce(new.raw_user_meta_data ->> 'display_name', new.raw_user_meta_data ->> 'username', 'Nuovo utente')
  );
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute procedure public.handle_new_user();


-- v3.2 — impostazioni, privacy e avatar
alter table public.profiles
  add column if not exists is_public boolean not null default true;

create table if not exists public.user_settings (
  user_id uuid primary key references auth.users(id) on delete cascade,
  show_library boolean not null default true,
  show_lists boolean not null default true,
  show_activity boolean not null default true,
  email_notifications boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.user_settings (user_id)
select id from public.profiles
on conflict (user_id) do nothing;

alter table public.user_settings enable row level security;

drop policy if exists "Public profiles are readable" on public.profiles;
drop policy if exists "Public or own profiles are readable" on public.profiles;
create policy "Public or own profiles are readable"
on public.profiles for select
using (is_public or (select auth.uid()) = id);

drop policy if exists "Users manage own settings" on public.user_settings;
create policy "Users manage own settings"
on public.user_settings for all
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'avatars',
  'avatars',
  true,
  2097152,
  array['image/png', 'image/jpeg', 'image/webp']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Users upload own avatar" on storage.objects;
create policy "Users upload own avatar"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

drop policy if exists "Users update own avatar" on storage.objects;
create policy "Users update own avatar"
on storage.objects for update
to authenticated
using (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = (select auth.uid())::text
)
with check (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

drop policy if exists "Users delete own avatar" on storage.objects;
create policy "Users delete own avatar"
on storage.objects for delete
to authenticated
using (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

drop policy if exists "Users list own avatar" on storage.objects;
create policy "Users list own avatar"
on storage.objects for select
to authenticated
using (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = ''
as $$
begin
  insert into public.profiles (id, username, display_name)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'username', 'user_' || substr(new.id::text, 1, 8)),
    coalesce(new.raw_user_meta_data ->> 'display_name', new.raw_user_meta_data ->> 'username', 'Nuovo utente')
  )
  on conflict (id) do nothing;

  insert into public.user_settings (user_id)
  values (new.id)
  on conflict (user_id) do nothing;

  return new;
end;
$$;


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

-- The Free Vault v3.4 — follow, feed, like, commenti e notifiche interne

create table if not exists public.user_follows (
  follower_id uuid not null
    constraint user_follows_follower_id_fkey
    references public.profiles(id) on delete cascade,
  following_id uuid not null
    constraint user_follows_following_id_fkey
    references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (follower_id, following_id),
  check (follower_id <> following_id)
);

create table if not exists public.review_likes (
  review_id uuid not null
    constraint review_likes_review_id_fkey
    references public.game_reviews(id) on delete cascade,
  user_id uuid not null
    constraint review_likes_user_id_fkey
    references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (review_id, user_id)
);

create table if not exists public.list_likes (
  list_id uuid not null
    constraint list_likes_list_id_fkey
    references public.user_lists(id) on delete cascade,
  user_id uuid not null
    constraint list_likes_user_id_fkey
    references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (list_id, user_id)
);

create table if not exists public.content_comments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null
    constraint content_comments_user_id_fkey
    references public.profiles(id) on delete cascade,
  target_type text not null check (target_type in ('review', 'list')),
  target_id uuid not null,
  body text not null check (char_length(btrim(body)) between 1 and 2000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.activities (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null
    constraint activities_user_id_fkey
    references public.profiles(id) on delete cascade,
  activity_type text not null check (
    activity_type in (
      'followed_user',
      'review_published',
      'list_published',
      'comment_published'
    )
  ),
  target_type text not null check (
    target_type in ('profile', 'review', 'list')
  ),
  target_id uuid not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.user_notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null
    constraint user_notifications_user_id_fkey
    references public.profiles(id) on delete cascade,
  actor_id uuid
    constraint user_notifications_actor_id_fkey
    references public.profiles(id) on delete cascade,
  notification_type text not null check (
    notification_type in (
      'new_follower',
      'review_like',
      'list_like',
      'review_comment',
      'list_comment'
    )
  ),
  target_type text not null check (
    target_type in ('profile', 'review', 'list')
  ),
  target_id uuid not null,
  metadata jsonb not null default '{}'::jsonb,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists user_follows_follower_idx
on public.user_follows (follower_id, created_at desc);

create index if not exists user_follows_following_idx
on public.user_follows (following_id, created_at desc);

create index if not exists review_likes_review_idx
on public.review_likes (review_id, created_at desc);

create index if not exists list_likes_list_idx
on public.list_likes (list_id, created_at desc);

create index if not exists content_comments_target_idx
on public.content_comments (target_type, target_id, created_at asc);

create index if not exists content_comments_user_idx
on public.content_comments (user_id, created_at desc);

create index if not exists activities_user_idx
on public.activities (user_id, created_at desc);

create index if not exists user_notifications_user_idx
on public.user_notifications (user_id, read_at, created_at desc);

-- Determina se il visitatore può vedere il contenuto sociale indicato.
create or replace function public.can_view_social_target(
  requested_type text,
  requested_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if requested_type = 'review' then
    return exists (
      select 1
      from public.game_reviews r
      where r.id = requested_id
        and (
          r.user_id = (select auth.uid())
          or public.can_view_user_content(r.user_id, 'activity')
        )
    );
  elsif requested_type = 'list' then
    return exists (
      select 1
      from public.user_lists l
      where l.id = requested_id
        and (
          l.user_id = (select auth.uid())
          or (
            l.visibility = 'public'
            and public.can_view_user_content(l.user_id, 'lists')
          )
        )
    );
  end if;
  return false;
end;
$$;

revoke all on function public.can_view_social_target(text, uuid) from public;
grant execute on function public.can_view_social_target(text, uuid) to anon, authenticated;

create or replace function public.is_public_profile(requested_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = requested_id
      and p.is_public = true
  );
$$;

revoke all on function public.is_public_profile(uuid) from public;
grant execute on function public.is_public_profile(uuid) to anon, authenticated;


create or replace function public.get_follow_counts(requested_id uuid)
returns table (followers bigint, following bigint)
language sql
stable
security definer
set search_path = ''
as $$
  select
    (select count(*) from public.user_follows f where f.following_id = requested_id) as followers,
    (select count(*) from public.user_follows f where f.follower_id = requested_id) as following
  where public.is_public_profile(requested_id)
     or requested_id = (select auth.uid());
$$;

revoke all on function public.get_follow_counts(uuid) from public;
grant execute on function public.get_follow_counts(uuid) to anon, authenticated;


create or replace function public.notification_actor_metadata(requested_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (
      select jsonb_build_object(
        'actor_username', p.username,
        'actor_display_name', p.display_name,
        'actor_avatar_url', p.avatar_url
      )
      from public.profiles p
      where p.id = requested_id
    ),
    '{}'::jsonb
  );
$$;

create or replace function public.touch_content_comment_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists content_comments_touch_updated_at on public.content_comments;
create trigger content_comments_touch_updated_at
before update on public.content_comments
for each row execute function public.touch_content_comment_updated_at();

-- Attività e notifiche generate sul server.
create or replace function public.handle_follow_created_v34()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.activities (
    user_id, activity_type, target_type, target_id, metadata
  )
  select
    new.follower_id,
    'followed_user',
    'profile',
    new.following_id,
    jsonb_build_object(
      'following_id', p.id,
      'following_username', p.username,
      'following_display_name', p.display_name
    )
  from public.profiles p
  where p.id = new.following_id;

  insert into public.user_notifications (
    user_id, actor_id, notification_type, target_type, target_id, metadata
  )
  values (
    new.following_id,
    new.follower_id,
    'new_follower',
    'profile',
    new.follower_id,
    public.notification_actor_metadata(new.follower_id)
  );

  return new;
end;
$$;

drop trigger if exists user_follows_after_insert_v34 on public.user_follows;
create trigger user_follows_after_insert_v34
after insert on public.user_follows
for each row execute function public.handle_follow_created_v34();

create or replace function public.handle_review_published_v34()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.activities (
    user_id, activity_type, target_type, target_id, metadata
  )
  values (
    new.user_id,
    'review_published',
    'review',
    new.id,
    jsonb_build_object(
      'game_key', new.game_key,
      'game_title', new.game_title,
      'game_image_url', new.game_image_url,
      'rating', new.rating,
      'review_title', new.title
    )
  );
  return new;
end;
$$;

drop trigger if exists game_reviews_after_insert_v34 on public.game_reviews;
create trigger game_reviews_after_insert_v34
after insert on public.game_reviews
for each row execute function public.handle_review_published_v34();

create or replace function public.handle_public_list_published_v34()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if new.visibility = 'public' then
      insert into public.activities (
        user_id, activity_type, target_type, target_id, metadata
      )
      values (
        new.user_id,
        'list_published',
        'list',
        new.id,
        jsonb_build_object(
          'name', new.name,
          'description', new.description,
          'game_count', coalesce(array_length(new.game_keys, 1), 0)
        )
      );
    end if;
  elsif tg_op = 'UPDATE' then
    if new.visibility = 'public'
       and old.visibility is distinct from new.visibility then
      insert into public.activities (
        user_id, activity_type, target_type, target_id, metadata
      )
      values (
        new.user_id,
        'list_published',
        'list',
        new.id,
        jsonb_build_object(
          'name', new.name,
          'description', new.description,
          'game_count', coalesce(array_length(new.game_keys, 1), 0)
        )
      );
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists user_lists_after_publish_v34 on public.user_lists;
create trigger user_lists_after_publish_v34
after insert or update of visibility on public.user_lists
for each row execute function public.handle_public_list_published_v34();

create or replace function public.handle_review_like_v34()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  owner_id uuid;
  review_game_title text;
  review_game_key text;
begin
  select r.user_id, r.game_title, r.game_key
  into owner_id, review_game_title, review_game_key
  from public.game_reviews r
  where r.id = new.review_id;

  if owner_id is not null and owner_id <> new.user_id then
    insert into public.user_notifications (
      user_id, actor_id, notification_type, target_type, target_id, metadata
    )
    values (
      owner_id,
      new.user_id,
      'review_like',
      'review',
      new.review_id,
      public.notification_actor_metadata(new.user_id)
      || jsonb_build_object(
        'game_title', review_game_title,
        'game_key', review_game_key
      )
    );
  end if;
  return new;
end;
$$;

drop trigger if exists review_likes_after_insert_v34 on public.review_likes;
create trigger review_likes_after_insert_v34
after insert on public.review_likes
for each row execute function public.handle_review_like_v34();

create or replace function public.handle_list_like_v34()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  owner_id uuid;
  list_name text;
begin
  select l.user_id, l.name
  into owner_id, list_name
  from public.user_lists l
  where l.id = new.list_id;

  if owner_id is not null and owner_id <> new.user_id then
    insert into public.user_notifications (
      user_id, actor_id, notification_type, target_type, target_id, metadata
    )
    values (
      owner_id,
      new.user_id,
      'list_like',
      'list',
      new.list_id,
      public.notification_actor_metadata(new.user_id)
      || jsonb_build_object('list_name', list_name)
    );
  end if;
  return new;
end;
$$;

drop trigger if exists list_likes_after_insert_v34 on public.list_likes;
create trigger list_likes_after_insert_v34
after insert on public.list_likes
for each row execute function public.handle_list_like_v34();

create or replace function public.handle_comment_created_v34()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  owner_id uuid;
  label text;
  notification_kind text;
  linked_game_key text;
begin
  if new.target_type = 'review' then
    select r.user_id, r.game_title, r.game_key
    into owner_id, label, linked_game_key
    from public.game_reviews r
    where r.id = new.target_id;
    notification_kind := 'review_comment';
  elsif new.target_type = 'list' then
    select l.user_id, l.name
    into owner_id, label
    from public.user_lists l
    where l.id = new.target_id;
    notification_kind := 'list_comment';
  end if;

  if owner_id is null then
    raise exception 'Target sociale inesistente';
  end if;

  insert into public.activities (
    user_id, activity_type, target_type, target_id, metadata
  )
  values (
    new.user_id,
    'comment_published',
    new.target_type,
    new.target_id,
    jsonb_build_object(
      'label', label,
      'game_key', linked_game_key
    )
  );

  if owner_id <> new.user_id then
    insert into public.user_notifications (
      user_id, actor_id, notification_type, target_type, target_id, metadata
    )
    values (
      owner_id,
      new.user_id,
      notification_kind,
      new.target_type,
      new.target_id,
      public.notification_actor_metadata(new.user_id)
      || jsonb_build_object(
        'label', label,
        'game_key', linked_game_key
      )
    );
  end if;

  return new;
end;
$$;

drop trigger if exists content_comments_after_insert_v34 on public.content_comments;
create trigger content_comments_after_insert_v34
after insert on public.content_comments
for each row execute function public.handle_comment_created_v34();

alter table public.user_follows enable row level security;
alter table public.review_likes enable row level security;
alter table public.list_likes enable row level security;
alter table public.content_comments enable row level security;
alter table public.activities enable row level security;
alter table public.user_notifications enable row level security;

drop policy if exists "Visible follow relationships are readable" on public.user_follows;
create policy "Visible follow relationships are readable"
on public.user_follows for select
using (
  follower_id = (select auth.uid())
  or following_id = (select auth.uid())
  or (
    public.is_public_profile(follower_id)
    and public.is_public_profile(following_id)
  )
);

drop policy if exists "Users follow from own account" on public.user_follows;
create policy "Users follow from own account"
on public.user_follows for insert
to authenticated
with check (
  follower_id = (select auth.uid())
  and follower_id <> following_id
  and public.is_public_profile(following_id)
);

drop policy if exists "Users unfollow from own account" on public.user_follows;
create policy "Users unfollow from own account"
on public.user_follows for delete
to authenticated
using (follower_id = (select auth.uid()));

drop policy if exists "Visible review likes are readable" on public.review_likes;
create policy "Visible review likes are readable"
on public.review_likes for select
using (public.can_view_social_target('review', review_id));

drop policy if exists "Users like reviews from own account" on public.review_likes;
create policy "Users like reviews from own account"
on public.review_likes for insert
to authenticated
with check (
  user_id = (select auth.uid())
  and public.can_view_social_target('review', review_id)
);

drop policy if exists "Users remove own review likes" on public.review_likes;
create policy "Users remove own review likes"
on public.review_likes for delete
to authenticated
using (user_id = (select auth.uid()));

drop policy if exists "Visible list likes are readable" on public.list_likes;
create policy "Visible list likes are readable"
on public.list_likes for select
using (public.can_view_social_target('list', list_id));

drop policy if exists "Users like lists from own account" on public.list_likes;
create policy "Users like lists from own account"
on public.list_likes for insert
to authenticated
with check (
  user_id = (select auth.uid())
  and public.can_view_social_target('list', list_id)
);

drop policy if exists "Users remove own list likes" on public.list_likes;
create policy "Users remove own list likes"
on public.list_likes for delete
to authenticated
using (user_id = (select auth.uid()));

drop policy if exists "Visible comments are readable" on public.content_comments;
create policy "Visible comments are readable"
on public.content_comments for select
using (public.can_view_social_target(target_type, target_id));

drop policy if exists "Users create comments from own account" on public.content_comments;
create policy "Users create comments from own account"
on public.content_comments for insert
to authenticated
with check (
  user_id = (select auth.uid())
  and public.can_view_social_target(target_type, target_id)
);

drop policy if exists "Users update own comments" on public.content_comments;
create policy "Users update own comments"
on public.content_comments for update
to authenticated
using (user_id = (select auth.uid()))
with check (
  user_id = (select auth.uid())
  and public.can_view_social_target(target_type, target_id)
);

drop policy if exists "Users delete own comments" on public.content_comments;
create policy "Users delete own comments"
on public.content_comments for delete
to authenticated
using (user_id = (select auth.uid()));

drop policy if exists "Visible activities are readable" on public.activities;
create policy "Visible activities are readable"
on public.activities for select
using (
  user_id = (select auth.uid())
  or public.can_view_user_content(user_id, 'activity')
);

drop policy if exists "Users read own notifications" on public.user_notifications;
create policy "Users read own notifications"
on public.user_notifications for select
to authenticated
using (user_id = (select auth.uid()));

drop policy if exists "Users update own notifications" on public.user_notifications;
create policy "Users update own notifications"
on public.user_notifications for update
to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

drop policy if exists "Users delete own notifications" on public.user_notifications;
create policy "Users delete own notifications"
on public.user_notifications for delete
to authenticated
using (user_id = (select auth.uid()));

grant select on public.user_follows to anon, authenticated;
grant insert, delete on public.user_follows to authenticated;

grant select on public.review_likes to anon, authenticated;
grant insert, delete on public.review_likes to authenticated;

grant select on public.list_likes to anon, authenticated;
grant insert, delete on public.list_likes to authenticated;

grant select on public.content_comments to anon, authenticated;
grant insert, update, delete on public.content_comments to authenticated;

grant select on public.activities to anon, authenticated;
grant select, update, delete on public.user_notifications to authenticated;



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

-- The Free Vault v4.1 — catalogo server-side, ricerca indicizzata e paginazione.
-- Eseguire dopo la migrazione v4.0.

create extension if not exists pg_trgm with schema extensions;

create table if not exists public.catalog_items (
  listing_id text primary key,
  canonical_id text not null,
  match_key text not null,
  store text not null
    check (store in ('epic', 'steam', 'playstation', 'xbox', 'nintendo', 'other')),
  external_id text not null,
  namespace text,
  title text not null,
  canonical_title text not null,
  description text,
  developer text,
  publisher text,
  image_url text,
  store_url text,
  product_slug text,
  offer_type text,
  category_group text not null default 'other'
    check (category_group in ('base_game', 'dlc', 'bundle', 'edition', 'other')),
  edition_name text,
  market_segment text not null default 'unclassified'
    check (market_segment in ('aaa', 'indie', 'unclassified')),
  release_date date,
  release_year integer,
  original_price integer,
  discount_price integer,
  currency_code text,
  currency_decimals integer not null default 2,
  fmt_original_price text,
  fmt_discount_price text,
  platforms text[] not null default '{}',
  genres text[] not null default '{}',
  tags text[] not null default '{}',
  categories text[] not null default '{}',
  available boolean not null default true,
  sync_run_id uuid not null,
  last_synced_at timestamptz not null default now(),
  search_text text generated always as (
    trim(
      coalesce(title, '') || ' ' ||
      coalesce(canonical_title, '') || ' ' ||
      coalesce(developer, '') || ' ' ||
      coalesce(publisher, '')
    )
  ) stored,
  search_document tsvector generated always as (
    setweight(to_tsvector('simple', coalesce(title, '')), 'A') ||
    setweight(to_tsvector('simple', coalesce(canonical_title, '')), 'A') ||
    setweight(to_tsvector('simple', coalesce(developer, '')), 'B') ||
    setweight(to_tsvector('simple', coalesce(publisher, '')), 'B') ||
    setweight(to_tsvector('simple', coalesce(description, '')), 'C')
  ) stored,
  unique (store, external_id)
);

create table if not exists public.catalog_sync_state (
  store text primary key
    check (store in ('epic', 'steam', 'playstation', 'xbox', 'nintendo', 'other')),
  run_id uuid,
  status text not null default 'idle'
    check (status in ('idle', 'running', 'completed', 'failed')),
  listing_count bigint not null default 0,
  canonical_count bigint not null default 0,
  started_at timestamptz,
  completed_at timestamptz,
  error_message text,
  metadata jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

create index if not exists catalog_items_canonical_id_idx
on public.catalog_items(canonical_id);

create index if not exists catalog_items_match_key_idx
on public.catalog_items(match_key);

create index if not exists catalog_items_store_idx
on public.catalog_items(store);

create index if not exists catalog_items_category_idx
on public.catalog_items(category_group);

create index if not exists catalog_items_segment_idx
on public.catalog_items(market_segment);

create index if not exists catalog_items_release_year_idx
on public.catalog_items(release_year desc);

create index if not exists catalog_items_price_idx
on public.catalog_items(discount_price, original_price);

create index if not exists catalog_items_search_document_idx
on public.catalog_items using gin(search_document);

create index if not exists catalog_items_title_trgm_idx
on public.catalog_items using gin(lower(title) extensions.gin_trgm_ops);

create index if not exists catalog_items_search_text_trgm_idx
on public.catalog_items using gin(lower(search_text) extensions.gin_trgm_ops);

alter table public.catalog_items enable row level security;
alter table public.catalog_sync_state enable row level security;

drop policy if exists "Catalog items are publicly readable" on public.catalog_items;
drop policy if exists "Catalog sync state is publicly readable" on public.catalog_sync_state;

-- Il catalogo completo non è interrogabile direttamente dal browser: il client
-- usa esclusivamente le RPC paginate definite sotto.
revoke all on public.catalog_items from anon, authenticated;
revoke all on public.catalog_sync_state from anon, authenticated;
grant select, insert, update, delete on public.catalog_items to service_role;
grant select, insert, update, delete on public.catalog_sync_state to service_role;

create or replace function public.begin_catalog_sync(
  p_store text,
  p_run_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.catalog_sync_state (
    store, run_id, status, listing_count, canonical_count,
    started_at, completed_at, error_message, updated_at
  )
  values (
    p_store, p_run_id, 'running', 0, 0,
    now(), null, null, now()
  )
  on conflict (store) do update set
    run_id = excluded.run_id,
    status = 'running',
    started_at = now(),
    completed_at = null,
    error_message = null,
    updated_at = now();
end;
$$;

create or replace function public.finalize_catalog_sync(
  p_store text,
  p_run_id uuid,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_listing_count bigint;
  v_canonical_count bigint;
begin
  delete from public.catalog_items
  where store = p_store
    and sync_run_id <> p_run_id;

  select count(*), count(distinct match_key)
  into v_listing_count, v_canonical_count
  from public.catalog_items
  where store = p_store
    and sync_run_id = p_run_id;

  insert into public.catalog_sync_state (
    store, run_id, status, listing_count, canonical_count,
    started_at, completed_at, error_message, metadata, updated_at
  )
  values (
    p_store, p_run_id, 'completed', v_listing_count, v_canonical_count,
    now(), now(), null, coalesce(p_metadata, '{}'::jsonb), now()
  )
  on conflict (store) do update set
    run_id = excluded.run_id,
    status = 'completed',
    listing_count = v_listing_count,
    canonical_count = v_canonical_count,
    completed_at = now(),
    error_message = null,
    metadata = coalesce(p_metadata, '{}'::jsonb),
    updated_at = now();

  return jsonb_build_object(
    'store', p_store,
    'listing_count', v_listing_count,
    'canonical_count', v_canonical_count,
    'completed_at', now()
  );
end;
$$;

create or replace function public.fail_catalog_sync(
  p_store text,
  p_run_id uuid,
  p_error_message text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.catalog_sync_state (
    store, run_id, status, error_message, started_at, updated_at
  )
  values (
    p_store, p_run_id, 'failed', left(p_error_message, 4000), now(), now()
  )
  on conflict (store) do update set
    run_id = excluded.run_id,
    status = 'failed',
    error_message = left(p_error_message, 4000),
    completed_at = now(),
    updated_at = now();
end;
$$;

revoke all on function public.begin_catalog_sync(text, uuid) from public;
revoke all on function public.finalize_catalog_sync(text, uuid, jsonb) from public;
revoke all on function public.fail_catalog_sync(text, uuid, text) from public;
grant execute on function public.begin_catalog_sync(text, uuid) to service_role;
grant execute on function public.finalize_catalog_sync(text, uuid, jsonb) to service_role;
grant execute on function public.fail_catalog_sync(text, uuid, text) to service_role;

create or replace function public.catalog_stats()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'total_listings', (select count(*) from public.catalog_items where available),
    'total_games', (select count(distinct match_key) from public.catalog_items where available),
    'stores', coalesce((
      select jsonb_object_agg(store, listing_count)
      from (
        select store, count(*) as listing_count
        from public.catalog_items
        where available
        group by store
      ) s
    ), '{}'::jsonb),
    'years', coalesce((
      select jsonb_agg(release_year order by release_year desc)
      from (
        select distinct release_year
        from public.catalog_items
        where available and release_year is not null
      ) y
    ), '[]'::jsonb),
    'sync', coalesce((
      select jsonb_agg(to_jsonb(css) order by css.store)
      from public.catalog_sync_state css
    ), '[]'::jsonb)
  );
$$;

revoke all on function public.catalog_stats() from public;
grant execute on function public.catalog_stats() to anon, authenticated;

create or replace function public.search_catalog(
  p_query text default '',
  p_stores text[] default null,
  p_category text default null,
  p_segment text default null,
  p_price text default null,
  p_year integer default null,
  p_library_keys text[] default null,
  p_favorite_keys text[] default null,
  p_personal_filter text default null,
  p_sort text default 'relevance',
  p_limit integer default 36,
  p_offset integer default 0
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
with params as (
  select
    lower(trim(coalesce(p_query, ''))) as q,
    greatest(1, least(coalesce(p_limit, 36), 100)) as page_limit,
    greatest(0, coalesce(p_offset, 0)) as page_offset
),
filtered as (
  select
    ci.*,
    case
      when p.q = '' then 0::real
      when lower(ci.title) = p.q then 100::real
      when lower(ci.canonical_title) = p.q then 95::real
      when lower(ci.title) like p.q || '%' then 70::real
      when lower(ci.canonical_title) like p.q || '%' then 65::real
      else (
        ts_rank_cd(ci.search_document, websearch_to_tsquery('simple', p.q)) * 20
        + extensions.similarity(lower(ci.title), p.q) * 10
        + extensions.similarity(lower(ci.search_text), p.q) * 3
      )::real
    end as relevance_score,
    (
      (case when ci.store = 'epic' then 3 else 0 end)
      + (case when nullif(ci.description, '') is not null then 2 else 0 end)
      + (case when ci.image_url is not null then 2 else 0 end)
      + (case when ci.developer is not null then 1 else 0 end)
      + (case when ci.publisher is not null then 1 else 0 end)
      + (case when ci.release_date is not null then 1 else 0 end)
    ) as richness_score
  from public.catalog_items ci
  cross join params p
  where ci.available
    and (p_stores is null or cardinality(p_stores) = 0 or ci.store = any(p_stores))
    and (p_category is null or p_category = '' or p_category = 'all' or ci.category_group = p_category)
    and (p_segment is null or p_segment = '' or p_segment = 'all' or ci.market_segment = p_segment)
    and (p_year is null or ci.release_year = p_year)
    and (
      p_price is null or p_price = '' or p_price = 'all'
      or (p_price = 'free' and coalesce(ci.discount_price, ci.original_price, 1) = 0)
      or (p_price = 'discounted' and ci.original_price is not null and ci.discount_price is not null and ci.discount_price < ci.original_price)
      or (p_price = 'paid' and coalesce(ci.discount_price, ci.original_price, 0) > 0)
    )
    and (
      p_personal_filter is null or p_personal_filter = '' or p_personal_filter = 'all'
      or (p_personal_filter = 'saved' and (ci.match_key = any(coalesce(p_library_keys, '{}'::text[])) or ci.canonical_id = any(coalesce(p_library_keys, '{}'::text[]))))
      or (p_personal_filter = 'favorite' and (ci.match_key = any(coalesce(p_favorite_keys, '{}'::text[])) or ci.canonical_id = any(coalesce(p_favorite_keys, '{}'::text[]))))
    )
    and (
      p.q = ''
      or lower(ci.search_text) like '%' || p.q || '%'
      or ci.search_document @@ websearch_to_tsquery('simple', p.q)
      or extensions.similarity(lower(ci.title), p.q) >= 0.22
    )
),
representatives as (
  select *
  from (
    select
      f.*,
      row_number() over (
        partition by f.match_key
        order by f.richness_score desc, f.store asc, f.listing_id asc
      ) as representative_rank
    from filtered f
  ) ranked
  where representative_rank = 1
),
grouped as (
  select
    max(r.canonical_id) as canonical_id,
    r.match_key,
    max(r.canonical_title) as canonical_title,
    max(r.title) as title,
    max(r.description) as description,
    max(r.developer) as developer,
    max(r.publisher) as publisher,
    max(r.image_url) as image_url,
    max(r.release_date) as release_date,
    max(r.release_year) as release_year,
    max(r.market_segment) as market_segment,
    max(r.category_group) as category_group,
    max(r.relevance_score) as relevance_score,
    array_agg(distinct f.store order by f.store) as stores,
    jsonb_agg(
      jsonb_build_object(
        'listing_id', f.listing_id,
        'store', f.store,
        'external_id', f.external_id,
        'namespace', f.namespace,
        'title', f.title,
        'store_url', f.store_url,
        'image_url', f.image_url,
        'offer_type', f.offer_type,
        'category_group', f.category_group,
        'edition_name', f.edition_name,
        'original_price', f.original_price,
        'discount_price', f.discount_price,
        'currency_code', f.currency_code,
        'currency_decimals', f.currency_decimals,
        'fmt_original_price', f.fmt_original_price,
        'fmt_discount_price', f.fmt_discount_price
      ) order by f.store, f.listing_id
    ) as store_listings,
    max(coalesce(f.discount_price, f.original_price, 0)) as sort_price
  from representatives r
  join filtered f on f.match_key = r.match_key
  group by r.match_key
),
ordered as (
  select
    g.*,
    count(*) over () as total_count,
    row_number() over (
      order by
        case when p_sort = 'title' then lower(g.title) end asc nulls last,
        case when p_sort = 'date' then g.release_date end desc nulls last,
        case when p_sort = 'value' then g.sort_price end desc nulls last,
        case when p_sort not in ('title', 'date', 'value') then g.relevance_score end desc nulls last,
        lower(g.title) asc
    ) as sort_position
  from grouped g
),
paged as (
  select o.*
  from ordered o
  cross join params p
  where o.sort_position > p.page_offset
    and o.sort_position <= p.page_offset + p.page_limit
)
select jsonb_build_object(
  'items', coalesce(jsonb_agg(
    jsonb_build_object(
      'canonical_id', canonical_id,
      'match_key', match_key,
      'internal_id', canonical_id,
      'listing_id', (store_listings -> 0 ->> 'listing_id'),
      'source_kind', 'catalog',
      'store', (store_listings -> 0 ->> 'store'),
      'stores', to_jsonb(stores),
      'store_listings', store_listings,
      'title', title,
      'canonical_title', canonical_title,
      'description', description,
      'developer', developer,
      'publisher', publisher,
      'image_url', image_url,
      'store_url', (store_listings -> 0 ->> 'store_url'),
      'release_date', release_date,
      'release_year', release_year,
      'market_segment', market_segment,
      'category_group', category_group,
      'original_price', (store_listings -> 0 -> 'original_price'),
      'discount_price', (store_listings -> 0 -> 'discount_price'),
      'currency_code', (store_listings -> 0 ->> 'currency_code'),
      'fmt_original_price', (store_listings -> 0 ->> 'fmt_original_price'),
      'fmt_discount_price', (store_listings -> 0 ->> 'fmt_discount_price')
    ) order by sort_position
  ), '[]'::jsonb),
  'total', coalesce(max(total_count), 0),
  'limit', (select page_limit from params),
  'offset', (select page_offset from params)
)
from paged;
$$;

revoke all on function public.search_catalog(text, text[], text, text, text, integer, text[], text[], text, text, integer, integer) from public;
grant execute on function public.search_catalog(text, text[], text, text, text, integer, text[], text[], text, text, integer, integer) to anon, authenticated;

create or replace function public.get_catalog_game(p_key text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
with target as (
  select ci.match_key
  from public.catalog_items ci
  where ci.available
    and (
      ci.canonical_id = p_key
      or ci.match_key = p_key
      or ci.listing_id = p_key
    )
  order by case when ci.match_key = p_key then 0 when ci.canonical_id = p_key then 1 when ci.listing_id = p_key then 2 else 3 end
  limit 1
),
ranked as (
  select
    ci.*,
    row_number() over (
      order by
        (case when ci.store = 'epic' then 3 else 0 end)
        + (case when nullif(ci.description, '') is not null then 2 else 0 end)
        + (case when ci.image_url is not null then 2 else 0 end) desc,
        ci.store,
        ci.listing_id
    ) as rn
  from public.catalog_items ci
  join target t on t.match_key = ci.match_key
  where ci.available
),
representative as (
  select * from ranked where rn = 1
)
select case when not exists(select 1 from representative) then null else jsonb_build_object(
  'canonical_id', r.canonical_id,
  'match_key', r.match_key,
  'internal_id', r.canonical_id,
  'listing_id', r.listing_id,
  'source_kind', 'catalog',
  'store', r.store,
  'stores', (select jsonb_agg(distinct x.store) from ranked x),
  'store_listings', (select jsonb_agg(
    jsonb_build_object(
      'listing_id', x.listing_id,
      'store', x.store,
      'external_id', x.external_id,
      'namespace', x.namespace,
      'title', x.title,
      'store_url', x.store_url,
      'image_url', x.image_url,
      'offer_type', x.offer_type,
      'category_group', x.category_group,
      'edition_name', x.edition_name,
      'original_price', x.original_price,
      'discount_price', x.discount_price,
      'currency_code', x.currency_code,
      'currency_decimals', x.currency_decimals,
      'fmt_original_price', x.fmt_original_price,
      'fmt_discount_price', x.fmt_discount_price
    ) order by x.store, x.listing_id
  ) from ranked x),
  'title', r.title,
  'canonical_title', r.canonical_title,
  'description', r.description,
  'developer', r.developer,
  'publisher', r.publisher,
  'image_url', r.image_url,
  'store_url', r.store_url,
  'release_date', r.release_date,
  'release_year', r.release_year,
  'market_segment', r.market_segment,
  'category_group', r.category_group,
  'offer_type', r.offer_type,
  'original_price', r.original_price,
  'discount_price', r.discount_price,
  'currency_code', r.currency_code,
  'currency_decimals', r.currency_decimals,
  'fmt_original_price', r.fmt_original_price,
  'fmt_discount_price', r.fmt_discount_price,
  'platforms', to_jsonb(r.platforms),
  'genres', to_jsonb(r.genres),
  'categories', to_jsonb(r.categories)
) end
from representative r;
$$;

revoke all on function public.get_catalog_game(text) from public;
grant execute on function public.get_catalog_game(text) to anon, authenticated;

comment on table public.catalog_items is
'Denormalized, indexed projection of all store listings used by the public catalog UI.';

comment on function public.search_catalog is
'Paginated server-side catalog search with filters, fuzzy matching and canonical grouping.';

create or replace function public.get_catalog_games(p_keys text[])
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
with requested as (
  select distinct unnest(coalesce(p_keys, '{}'::text[])) as requested_key
),
targets as (
  select distinct ci.match_key
  from public.catalog_items ci
  join requested r
    on ci.canonical_id = r.requested_key
    or ci.match_key = r.requested_key
    or ci.listing_id = r.requested_key
  where ci.available
),
ranked as (
  select
    ci.*,
    row_number() over (
      partition by ci.match_key
      order by
        (
          (case when ci.store = 'epic' then 3 else 0 end)
          + (case when nullif(ci.description, '') is not null then 2 else 0 end)
          + (case when ci.image_url is not null then 2 else 0 end)
        ) desc,
        ci.store,
        ci.listing_id
    ) as rn
  from public.catalog_items ci
  join targets t on t.match_key = ci.match_key
  where ci.available
),
grouped as (
  select
    max(r.canonical_id) as canonical_id,
    r.match_key,
    max(r.title) filter (where r.rn = 1) as title,
    max(r.canonical_title) filter (where r.rn = 1) as canonical_title,
    max(r.description) filter (where r.rn = 1) as description,
    max(r.developer) filter (where r.rn = 1) as developer,
    max(r.publisher) filter (where r.rn = 1) as publisher,
    max(r.image_url) filter (where r.rn = 1) as image_url,
    max(r.store_url) filter (where r.rn = 1) as store_url,
    max(r.store) filter (where r.rn = 1) as store,
    max(r.release_date) filter (where r.rn = 1) as release_date,
    max(r.release_year) filter (where r.rn = 1) as release_year,
    max(r.market_segment) filter (where r.rn = 1) as market_segment,
    max(r.category_group) filter (where r.rn = 1) as category_group,
    array_agg(distinct r.store order by r.store) as stores,
    jsonb_agg(
      jsonb_build_object(
        'listing_id', r.listing_id,
        'store', r.store,
        'external_id', r.external_id,
        'namespace', r.namespace,
        'title', r.title,
        'store_url', r.store_url,
        'image_url', r.image_url,
        'offer_type', r.offer_type,
        'category_group', r.category_group,
        'edition_name', r.edition_name,
        'original_price', r.original_price,
        'discount_price', r.discount_price,
        'currency_code', r.currency_code,
        'currency_decimals', r.currency_decimals,
        'fmt_original_price', r.fmt_original_price,
        'fmt_discount_price', r.fmt_discount_price
      ) order by r.store, r.listing_id
    ) as store_listings
  from ranked r
  group by r.match_key
)
select coalesce(jsonb_agg(jsonb_build_object(
  'canonical_id', canonical_id,
  'match_key', match_key,
  'internal_id', canonical_id,
  'source_kind', 'catalog',
  'store', store,
  'stores', to_jsonb(stores),
  'store_listings', store_listings,
  'title', title,
  'canonical_title', canonical_title,
  'description', description,
  'developer', developer,
  'publisher', publisher,
  'image_url', image_url,
  'store_url', store_url,
  'release_date', release_date,
  'release_year', release_year,
  'market_segment', market_segment,
  'category_group', category_group
)), '[]'::jsonb)
from grouped;
$$;

revoke all on function public.get_catalog_games(text[]) from public;
grant execute on function public.get_catalog_games(text[]) to anon, authenticated;


-- v4.1.1 catalog finalize timeout fix
-- The Free Vault v4.1.1 — finalizzazione catalogo senza timeout.
-- Eseguire dopo 20260610_v41_catalog_performance.sql.

create index if not exists catalog_items_store_run_listing_idx
on public.catalog_items(store, sync_run_id, listing_id);

create index if not exists catalog_items_store_run_match_idx
on public.catalog_items(store, sync_run_id, match_key);

create or replace function public.cleanup_catalog_sync(
  p_store text,
  p_run_id uuid,
  p_limit integer default 5000
)
returns integer
language plpgsql
security definer
set search_path = ''
set statement_timeout = '60s'
as $$
declare
  v_deleted integer := 0;
  v_limit integer := greatest(100, least(coalesce(p_limit, 5000), 10000));
begin
  with doomed as (
    select ci.listing_id
    from public.catalog_items ci
    where ci.store = p_store
      and ci.sync_run_id <> p_run_id
    order by ci.listing_id
    limit v_limit
  )
  delete from public.catalog_items ci
  using doomed d
  where ci.listing_id = d.listing_id;

  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$$;

revoke all on function public.cleanup_catalog_sync(text, uuid, integer) from public;
grant execute on function public.cleanup_catalog_sync(text, uuid, integer) to service_role;

create or replace function public.finalize_catalog_sync(
  p_store text,
  p_run_id uuid,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
set statement_timeout = '60s'
as $$
declare
  v_listing_count bigint;
  v_canonical_count bigint;
begin
  v_listing_count := nullif(p_metadata ->> 'listing_count', '')::bigint;
  v_canonical_count := nullif(p_metadata ->> 'canonical_count', '')::bigint;

  -- Fallback per client vecchi. Il client v4.1.1 passa già entrambi i conteggi.
  if v_listing_count is null or v_canonical_count is null then
    select count(*), count(distinct match_key)
    into v_listing_count, v_canonical_count
    from public.catalog_items
    where store = p_store
      and sync_run_id = p_run_id;
  end if;

  insert into public.catalog_sync_state (
    store, run_id, status, listing_count, canonical_count,
    started_at, completed_at, error_message, metadata, updated_at
  )
  values (
    p_store, p_run_id, 'completed', v_listing_count, v_canonical_count,
    now(), now(), null, coalesce(p_metadata, '{}'::jsonb), now()
  )
  on conflict (store) do update set
    run_id = excluded.run_id,
    status = 'completed',
    listing_count = excluded.listing_count,
    canonical_count = excluded.canonical_count,
    completed_at = now(),
    error_message = null,
    metadata = excluded.metadata,
    updated_at = now();

  return jsonb_build_object(
    'store', p_store,
    'listing_count', v_listing_count,
    'canonical_count', v_canonical_count,
    'completed_at', now()
  );
end;
$$;

revoke all on function public.finalize_catalog_sync(text, uuid, jsonb) from public;
grant execute on function public.finalize_catalog_sync(text, uuid, jsonb) to service_role;

-- v4.1.3 is installed through:
-- supabase/migrations/20260610_v413_incremental_catalog_sync.sql
-- It intentionally remains a separate migration because it replaces catalog
-- synchronization functions created by v4.1-v4.1.2.

-- v4.1.4 is installed through:
-- supabase/migrations/20260610_v414_setbased_catalog_upsert.sql
-- It replaces the procedural row-by-row catalog upsert with a set-based merge.



-- v4.2 — diario di gioco, progressi e statistiche personali
-- Migrazione sorgente: supabase/migrations/20260610_v42_game_journal.sql
alter table public.user_settings
  add column if not exists show_diary boolean not null default true;

create table if not exists public.user_game_progress (
  user_id uuid not null references auth.users(id) on delete cascade,
  game_key text not null,
  game_title text not null check (char_length(game_title) between 1 and 300),
  game_image_url text,
  status text not null default 'saved'
    check (status in ('saved', 'backlog', 'playing', 'paused', 'completed', 'abandoned', 'replay')),
  progress_percent smallint not null default 0 check (progress_percent between 0 and 100),
  started_at date,
  completed_at date,
  completion_count smallint not null default 0 check (completion_count between 0 and 999),
  manual_playtime_minutes integer not null default 0 check (manual_playtime_minutes >= 0),
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
  visibility text not null default 'private' check (visibility in ('private', 'public')),
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


-- v4.4 — discovery avanzata
-- Migrazione sorgente: supabase/migrations/20260611_v44_discovery.sql
-- The Free Vault v4.4 — Discovery avanzata
-- Aggiunge sezioni curate, pagine sviluppatore/publisher e giochi correlati.
-- Non crea nuove tabelle né indici pesanti.

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
    'internal_id', (p_game).canonical_id,
    'listing_id', ((p_game).store_listings -> 0 ->> 'listing_id'),
    'source_kind', 'catalog',
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

create or replace function public.catalog_discovery(p_limit integer default 12)
returns jsonb
language sql
stable
security definer
set search_path = ''
set statement_timeout = '15s'
as $$
with params as (
  select greatest(4, least(coalesce(p_limit, 12), 24)) as item_limit
),
public_review_scores as materialized (
  select
    gr.game_key,
    count(*)::integer as review_count,
    round(avg(gr.rating)::numeric, 2) as average_rating
  from public.game_reviews gr
  where public.can_view_user_content(gr.user_id, 'activity')
  group by gr.game_key
),
resolved_scores as materialized (
  select
    prs.review_count,
    prs.average_rating,
    cg.match_key
  from public_review_scores prs
  join lateral (
    select candidate.match_key
    from public.catalog_games candidate
    where candidate.match_key = prs.game_key
       or candidate.canonical_id = prs.game_key
    order by case when candidate.match_key = prs.game_key then 0 else 1 end
    limit 1
  ) cg on true
),
recent_keys as materialized (
  select recent_game.match_key
  from public.catalog_games recent_game
  where recent_game.category_group = 'base_game'
    and recent_game.release_date is not null
    and recent_game.release_date <= current_date
    and recent_game.image_url is not null
  order by recent_game.release_date desc, recent_game.match_key
  limit (select item_limit from params)
),
multi_store_keys as materialized (
  select multi_game.match_key
  from public.catalog_games multi_game
  where multi_game.stores @> array['epic', 'steam']::text[]
    and multi_game.category_group = 'base_game'
    and multi_game.image_url is not null
  order by multi_game.release_date desc nulls last, multi_game.match_key
  limit (select item_limit from params)
),
indie_keys as materialized (
  select indie_game.match_key
  from public.catalog_games indie_game
  where indie_game.market_segment = 'indie'
    and indie_game.category_group = 'base_game'
    and indie_game.image_url is not null
  order by indie_game.release_date desc nulls last, indie_game.match_key
  limit (select item_limit from params)
),
top_rated_keys as materialized (
  select rs.match_key, rs.review_count, rs.average_rating
  from resolved_scores rs
  order by rs.average_rating desc, rs.review_count desc, rs.match_key
  limit (select item_limit from params)
),
most_reviewed_keys as materialized (
  select rs.match_key, rs.review_count, rs.average_rating
  from resolved_scores rs
  order by rs.review_count desc, rs.average_rating desc, rs.match_key
  limit (select item_limit from params)
)
select jsonb_build_object(
  'generated_at', now(),
  'recent', coalesce((
    select jsonb_agg(public.catalog_game_card_json(cg) order by cg.release_date desc nulls last, lower(cg.title), cg.match_key)
    from recent_keys rk
    join public.catalog_games cg on cg.match_key = rk.match_key
  ), '[]'::jsonb),
  'community_top', coalesce((
    select jsonb_agg(
      public.catalog_game_card_json(cg)
      || jsonb_build_object(
        'average_rating', trk.average_rating,
        'review_count', trk.review_count
      )
      order by trk.average_rating desc, trk.review_count desc, cg.match_key
    )
    from top_rated_keys trk
    join public.catalog_games cg on cg.match_key = trk.match_key
  ), '[]'::jsonb),
  'most_reviewed', coalesce((
    select jsonb_agg(
      public.catalog_game_card_json(cg)
      || jsonb_build_object(
        'average_rating', mrk.average_rating,
        'review_count', mrk.review_count
      )
      order by mrk.review_count desc, mrk.average_rating desc, cg.match_key
    )
    from most_reviewed_keys mrk
    join public.catalog_games cg on cg.match_key = mrk.match_key
  ), '[]'::jsonb),
  'multi_store', coalesce((
    select jsonb_agg(public.catalog_game_card_json(cg) order by cg.release_date desc nulls last, lower(cg.title), cg.match_key)
    from multi_store_keys msk
    join public.catalog_games cg on cg.match_key = msk.match_key
  ), '[]'::jsonb),
  'indie', coalesce((
    select jsonb_agg(public.catalog_game_card_json(cg) order by cg.release_date desc nulls last, lower(cg.title), cg.match_key)
    from indie_keys ik
    join public.catalog_games cg on cg.match_key = ik.match_key
  ), '[]'::jsonb)
);
$$;

revoke all on function public.catalog_discovery(integer) from public;
grant execute on function public.catalog_discovery(integer) to anon, authenticated;

create or replace function public.catalog_entity(
  p_kind text,
  p_name text,
  p_limit integer default 36,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
set statement_timeout = '15s'
as $$
declare
  v_kind text := lower(trim(coalesce(p_kind, '')));
  v_name text := trim(coalesce(p_name, ''));
  v_limit integer := greatest(1, least(coalesce(p_limit, 36), 100));
  v_offset integer := greatest(0, coalesce(p_offset, 0));
begin
  if v_kind not in ('developer', 'publisher') then
    raise exception 'Unsupported catalog entity kind: %', v_kind;
  end if;

  if v_name = '' then
    return jsonb_build_object(
      'kind', v_kind,
      'name', v_name,
      'total', 0,
      'limit', v_limit,
      'offset', v_offset,
      'items', '[]'::jsonb
    );
  end if;

  return (
    with filtered as materialized (
      select cg.match_key
      from public.catalog_games cg
      where (
        (v_kind = 'developer' and lower(coalesce(cg.developer, '')) = lower(v_name))
        or
        (v_kind = 'publisher' and lower(coalesce(cg.publisher, '')) = lower(v_name))
      )
      and (
        cg.search_document @@ plainto_tsquery('simple', v_name)
        or lower(cg.title) = lower(v_name)
      )
    ),
    page_keys as materialized (
      select cg.match_key
      from filtered f
      join public.catalog_games cg on cg.match_key = f.match_key
      order by cg.release_date desc nulls last, lower(cg.title), cg.match_key
      limit v_limit
      offset v_offset
    )
    select jsonb_build_object(
      'kind', v_kind,
      'name', v_name,
      'total', (select count(*) from filtered),
      'limit', v_limit,
      'offset', v_offset,
      'items', coalesce((
        select jsonb_agg(
          public.catalog_game_card_json(cg)
          order by cg.release_date desc nulls last, lower(cg.title), cg.match_key
        )
        from page_keys pk
        join public.catalog_games cg on cg.match_key = pk.match_key
      ), '[]'::jsonb)
    )
  );
end;
$$;

revoke all on function public.catalog_entity(text, text, integer, integer) from public;
grant execute on function public.catalog_entity(text, text, integer, integer) to anon, authenticated;

create or replace function public.catalog_related_games(
  p_key text,
  p_limit integer default 12
)
returns jsonb
language sql
stable
security definer
set search_path = ''
set statement_timeout = '15s'
as $$
with params as (
  select greatest(1, least(coalesce(p_limit, 12), 24)) as item_limit
),
target as materialized (
  select cg.*
  from public.catalog_games cg
  where cg.match_key = p_key
     or cg.canonical_id = p_key
     or exists (
       select 1
       from jsonb_array_elements(cg.store_listings) listing
       where listing ->> 'listing_id' = p_key
     )
  order by case when cg.match_key = p_key then 0 when cg.canonical_id = p_key then 1 else 2 end
  limit 1
),
developer_candidates as materialized (
  select cg.match_key
  from target t
  join public.catalog_games cg
    on t.developer is not null
   and t.developer <> ''
   and lower(cg.developer) = lower(t.developer)
   and cg.search_document @@ plainto_tsquery('simple', t.developer)
  where cg.match_key <> t.match_key
  order by cg.release_date desc nulls last, cg.match_key
  limit 80
),
publisher_candidates as materialized (
  select cg.match_key
  from target t
  join public.catalog_games cg
    on t.publisher is not null
   and t.publisher <> ''
   and lower(cg.publisher) = lower(t.publisher)
   and cg.search_document @@ plainto_tsquery('simple', t.publisher)
  where cg.match_key <> t.match_key
  order by cg.release_date desc nulls last, cg.match_key
  limit 80
),
category_candidates as materialized (
  select cg.match_key
  from target t
  join public.catalog_games cg
    on cg.category_group = t.category_group
   and (
     t.release_year is null
     or cg.release_year between t.release_year - 3 and t.release_year + 3
   )
  where cg.match_key <> t.match_key
  order by cg.release_date desc nulls last, cg.match_key
  limit 100
),
candidate_keys as materialized (
  select match_key from developer_candidates
  union
  select match_key from publisher_candidates
  union
  select match_key from category_candidates
),
scored as materialized (
  select
    cg.match_key,
    (
      case when t.developer is not null and lower(cg.developer) = lower(t.developer) then 10 else 0 end
      + case when t.publisher is not null and lower(cg.publisher) = lower(t.publisher) then 7 else 0 end
      + case when cg.category_group = t.category_group then 3 else 0 end
      + case when cg.market_segment = t.market_segment then 2 else 0 end
      + case when cg.stores && t.stores then 1 else 0 end
      + greatest(
          0,
          4 - coalesce(abs(cg.release_year - t.release_year), 4)
        )
      + least(
          6,
          cardinality(array(
            select genre
            from unnest(cg.genres) genre
            intersect
            select target_genre
            from unnest(t.genres) target_genre
          )) * 2
        )
    )::integer as relation_score
  from candidate_keys ck
  join public.catalog_games cg on cg.match_key = ck.match_key
  cross join target t
)
select coalesce(jsonb_agg(
  public.catalog_game_card_json(cg)
  || jsonb_build_object('relation_score', s.relation_score)
  order by s.relation_score desc, cg.release_date desc nulls last, lower(cg.title), cg.match_key
), '[]'::jsonb)
from (
  select scored.*
  from scored
  order by relation_score desc, match_key
  limit (select item_limit from params)
) s
join public.catalog_games cg on cg.match_key = s.match_key;
$$;

revoke all on function public.catalog_related_games(text, integer) from public;
grant execute on function public.catalog_related_games(text, integer) to anon, authenticated;

comment on function public.catalog_discovery(integer) is
'Lightweight discovery sections built from the canonical catalog and public reviews.';

comment on function public.catalog_entity(text, text, integer, integer) is
'Paginated exact developer or publisher page without exposing catalog tables.';

comment on function public.catalog_related_games(text, integer) is
'Bounded related-games query based on developer, publisher, genre, category and release year.';
-- The Free Vault v4.5 — Catalog Quality & Admin Tools
-- Eseguire dopo la v4.4.
-- Tabelle leggere, RPC protette e trigger per preservare gli override catalogo.

create table if not exists public.admin_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null default 'admin' check (role in ('admin', 'moderator')),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.catalog_overrides (
  match_key text primary key references public.catalog_games(match_key) on delete cascade,
  title text,
  canonical_title text,
  description text,
  developer text,
  publisher text,
  image_url text,
  store_url text,
  release_year integer,
  market_segment text check (market_segment is null or market_segment in ('aaa', 'indie', 'unclassified')),
  category_group text check (category_group is null or category_group in ('base_game', 'dlc', 'bundle', 'edition', 'other')),
  locked_fields text[] not null default '{}',
  updated_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.moderation_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references auth.users(id) on delete cascade,
  target_type text not null check (target_type in ('review', 'comment', 'list')),
  target_id uuid not null,
  reason text not null check (char_length(reason) between 3 and 1000),
  status text not null default 'open' check (status in ('open', 'dismissed', 'removed')),
  resolution_note text check (resolution_note is null or char_length(resolution_note) <= 2000),
  resolved_by uuid references auth.users(id) on delete set null,
  resolved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists moderation_reports_open_unique
on public.moderation_reports(reporter_id, target_type, target_id)
where status = 'open';

create index if not exists moderation_reports_status_idx
on public.moderation_reports(status, created_at desc);

create table if not exists public.admin_audit_log (
  id bigint generated by default as identity primary key,
  actor_id uuid references auth.users(id) on delete set null,
  action text not null,
  target_type text not null,
  target_id text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists admin_audit_log_created_idx
on public.admin_audit_log(created_at desc);

alter table public.canonical_match_queue
  add column if not exists reviewed_by uuid references auth.users(id) on delete set null,
  add column if not exists reviewed_at timestamptz,
  add column if not exists review_note text;

alter table public.admin_users enable row level security;
alter table public.catalog_overrides enable row level security;
alter table public.moderation_reports enable row level security;
alter table public.admin_audit_log enable row level security;

revoke all on public.admin_users from anon, authenticated;
revoke all on public.catalog_overrides from anon, authenticated;
revoke all on public.moderation_reports from anon, authenticated;
revoke all on public.admin_audit_log from anon, authenticated;

create or replace function public.current_admin_role()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select au.role
  from public.admin_users au
  where au.user_id = (select auth.uid())
  limit 1;
$$;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(public.current_admin_role() = 'admin', false);
$$;

create or replace function public.can_moderate()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(public.current_admin_role() in ('admin', 'moderator'), false);
$$;

revoke all on function public.current_admin_role() from public;
revoke all on function public.is_admin() from public;
revoke all on function public.can_moderate() from public;
grant execute on function public.current_admin_role() to authenticated;
grant execute on function public.is_admin() to authenticated;
grant execute on function public.can_moderate() to authenticated;

create or replace function public.admin_context()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'role', public.current_admin_role(),
    'is_admin', public.is_admin(),
    'can_moderate', public.can_moderate()
  );
$$;

revoke all on function public.admin_context() from public;
grant execute on function public.admin_context() to authenticated;

create or replace function public.apply_catalog_override_to_row()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  o public.catalog_overrides%rowtype;
begin
  select * into o
  from public.catalog_overrides
  where match_key = new.match_key;

  if not found then
    return new;
  end if;

  if 'title' = any(o.locked_fields) and o.title is not null then new.title := o.title; end if;
  if 'canonical_title' = any(o.locked_fields) and o.canonical_title is not null then new.canonical_title := o.canonical_title; end if;
  if 'description' = any(o.locked_fields) and o.description is not null then new.description := o.description; end if;
  if 'developer' = any(o.locked_fields) and o.developer is not null then new.developer := o.developer; end if;
  if 'publisher' = any(o.locked_fields) and o.publisher is not null then new.publisher := o.publisher; end if;
  if 'image_url' = any(o.locked_fields) and o.image_url is not null then new.image_url := o.image_url; end if;
  if 'store_url' = any(o.locked_fields) and o.store_url is not null then new.store_url := o.store_url; end if;
  if 'release_year' = any(o.locked_fields) and o.release_year is not null then new.release_year := o.release_year; end if;
  if 'market_segment' = any(o.locked_fields) and o.market_segment is not null then new.market_segment := o.market_segment; end if;
  if 'category_group' = any(o.locked_fields) and o.category_group is not null then new.category_group := o.category_group; end if;

  return new;
end;
$$;

drop trigger if exists catalog_games_apply_override on public.catalog_games;
create trigger catalog_games_apply_override
before insert or update on public.catalog_games
for each row execute function public.apply_catalog_override_to_row();

create or replace function public.admin_get_catalog_record(p_key text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
set statement_timeout = '10s'
as $$
declare
  g public.catalog_games%rowtype;
  o public.catalog_overrides%rowtype;
begin
  if not public.is_admin() then
    raise exception 'Accesso amministratore richiesto' using errcode = '42501';
  end if;

  select * into g
  from public.catalog_games
  where match_key = p_key or canonical_id = p_key
  order by case when match_key = p_key then 0 else 1 end
  limit 1;

  if not found then return null; end if;
  select * into o from public.catalog_overrides where match_key = g.match_key;

  return jsonb_build_object(
    'game', jsonb_build_object(
      'match_key', g.match_key,
      'canonical_id', g.canonical_id,
      'title', g.title,
      'canonical_title', g.canonical_title,
      'description', g.description,
      'developer', g.developer,
      'publisher', g.publisher,
      'image_url', g.image_url,
      'store_url', g.store_url,
      'release_year', g.release_year,
      'market_segment', g.market_segment,
      'category_group', g.category_group,
      'stores', g.stores,
      'store_listings', g.store_listings,
      'updated_at', g.updated_at
    ),
    'override', case when o.match_key is null then null else jsonb_build_object(
      'match_key', o.match_key,
      'title', o.title,
      'canonical_title', o.canonical_title,
      'description', o.description,
      'developer', o.developer,
      'publisher', o.publisher,
      'image_url', o.image_url,
      'store_url', o.store_url,
      'release_year', o.release_year,
      'market_segment', o.market_segment,
      'category_group', o.category_group,
      'locked_fields', o.locked_fields,
      'updated_at', o.updated_at
    ) end
  );
end;
$$;

create or replace function public.admin_save_catalog_override(
  p_match_key text,
  p_patch jsonb,
  p_locked_fields text[]
)
returns jsonb
language plpgsql
security definer
set search_path = ''
set statement_timeout = '10s'
as $$
declare
  allowed_fields constant text[] := array[
    'title','canonical_title','description','developer','publisher','image_url',
    'store_url','release_year','market_segment','category_group'
  ];
  locks text[];
  v_user uuid := (select auth.uid());
  segment_value text := nullif(btrim(p_patch ->> 'market_segment'), '');
  category_value text := nullif(btrim(p_patch ->> 'category_group'), '');
begin
  if not public.is_admin() then
    raise exception 'Accesso amministratore richiesto' using errcode = '42501';
  end if;
  if not exists (select 1 from public.catalog_games where match_key = p_match_key) then
    raise exception 'Gioco catalogo non trovato';
  end if;
  if exists (
    select 1 from unnest(coalesce(p_locked_fields, '{}'::text[])) f
    where not (f = any(allowed_fields))
  ) then
    raise exception 'Campo override non consentito';
  end if;

  select coalesce(array_agg(distinct f order by f), '{}'::text[])
  into locks
  from unnest(coalesce(p_locked_fields, '{}'::text[])) f;

  if segment_value is not null and segment_value not in ('aaa','indie','unclassified') then
    raise exception 'Segmento non valido';
  end if;
  if category_value is not null and category_value not in ('base_game','dlc','bundle','edition','other') then
    raise exception 'Categoria non valida';
  end if;

  insert into public.catalog_overrides (
    match_key, title, canonical_title, description, developer, publisher,
    image_url, store_url, release_year, market_segment, category_group,
    locked_fields, updated_by, updated_at
  ) values (
    p_match_key,
    nullif(btrim(p_patch ->> 'title'), ''),
    nullif(btrim(p_patch ->> 'canonical_title'), ''),
    nullif(btrim(p_patch ->> 'description'), ''),
    nullif(btrim(p_patch ->> 'developer'), ''),
    nullif(btrim(p_patch ->> 'publisher'), ''),
    nullif(btrim(p_patch ->> 'image_url'), ''),
    nullif(btrim(p_patch ->> 'store_url'), ''),
    case when p_patch ->> 'release_year' ~ '^[0-9]{4}$' then (p_patch ->> 'release_year')::integer else null end,
    segment_value,
    category_value,
    locks,
    v_user,
    now()
  )
  on conflict (match_key) do update set
    title = excluded.title,
    canonical_title = excluded.canonical_title,
    description = excluded.description,
    developer = excluded.developer,
    publisher = excluded.publisher,
    image_url = excluded.image_url,
    store_url = excluded.store_url,
    release_year = excluded.release_year,
    market_segment = excluded.market_segment,
    category_group = excluded.category_group,
    locked_fields = excluded.locked_fields,
    updated_by = excluded.updated_by,
    updated_at = now();

  update public.catalog_games
  set updated_at = now()
  where match_key = p_match_key;

  insert into public.admin_audit_log(actor_id, action, target_type, target_id, metadata)
  values (v_user, 'catalog_override_saved', 'catalog_game', p_match_key, jsonb_build_object('locked_fields', locks));

  return public.admin_get_catalog_record(p_match_key);
end;
$$;

create or replace function public.admin_clear_catalog_override(p_match_key text)
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
  delete from public.catalog_overrides where match_key = p_match_key;
  insert into public.admin_audit_log(actor_id, action, target_type, target_id)
  values (v_user, 'catalog_override_cleared', 'catalog_game', p_match_key);
  return jsonb_build_object('ok', true, 'message', 'Override rimosso. I dati automatici torneranno al prossimo sync.');
end;
$$;

create or replace function public.admin_list_match_queue(
  p_status text default 'pending',
  p_limit integer default 50,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
set statement_timeout = '10s'
as $$
declare
  result jsonb;
begin
  if not public.is_admin() then
    raise exception 'Accesso amministratore richiesto' using errcode = '42501';
  end if;
  if p_status not in ('pending','verified','rejected','all') then raise exception 'Stato non valido'; end if;

  with filtered as materialized (
    select q.*
    from public.canonical_match_queue q
    where p_status = 'all' or q.status = p_status
  ), page as (
    select * from filtered
    order by case when status = 'pending' then 0 else 1 end, confidence desc, created_at desc
    limit greatest(1, least(coalesce(p_limit, 50), 100))
    offset greatest(coalesce(p_offset, 0), 0)
  )
  select jsonb_build_object(
    'items', coalesce((select jsonb_agg(to_jsonb(page) order by confidence desc, created_at desc) from page), '[]'::jsonb),
    'total', (select count(*) from filtered)
  ) into result;
  return result;
end;
$$;

create or replace function public.admin_review_match(
  p_id uuid,
  p_status text,
  p_resolved_game_id text default null,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  updated_row public.canonical_match_queue%rowtype;
begin
  if not public.is_admin() then
    raise exception 'Accesso amministratore richiesto' using errcode = '42501';
  end if;
  if p_status not in ('verified','rejected','pending') then raise exception 'Stato non valido'; end if;

  update public.canonical_match_queue
  set status = p_status,
      resolved_game_id = case when p_status = 'verified' then p_resolved_game_id else null end,
      review_note = nullif(btrim(p_note), ''),
      reviewed_by = v_user,
      reviewed_at = now(),
      updated_at = now()
  where id = p_id
  returning * into updated_row;

  if not found then raise exception 'Candidato non trovato'; end if;
  insert into public.admin_audit_log(actor_id, action, target_type, target_id, metadata)
  values (v_user, 'catalog_match_reviewed', 'canonical_match', p_id::text, jsonb_build_object('status', p_status));
  return to_jsonb(updated_row);
end;
$$;

create or replace function public.report_content(
  p_target_type text,
  p_target_id uuid,
  p_reason text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  existing_id uuid;
  new_id uuid;
begin
  if v_user is null then raise exception 'Accedi per inviare una segnalazione' using errcode = '42501'; end if;
  if p_target_type not in ('review','comment','list') then raise exception 'Tipo contenuto non valido'; end if;
  if char_length(btrim(coalesce(p_reason, ''))) < 3 then raise exception 'Descrivi brevemente il problema'; end if;

  if p_target_type = 'review' and not exists (select 1 from public.game_reviews where id = p_target_id) then raise exception 'Recensione non trovata'; end if;
  if p_target_type = 'comment' and not exists (select 1 from public.content_comments where id = p_target_id) then raise exception 'Commento non trovato'; end if;
  if p_target_type = 'list' and not exists (select 1 from public.user_lists where id = p_target_id) then raise exception 'Lista non trovata'; end if;

  select id into existing_id
  from public.moderation_reports
  where reporter_id = v_user and target_type = p_target_type and target_id = p_target_id and status = 'open'
  limit 1;
  if existing_id is not null then return existing_id; end if;

  insert into public.moderation_reports(reporter_id, target_type, target_id, reason)
  values (v_user, p_target_type, p_target_id, left(btrim(p_reason), 1000))
  returning id into new_id;
  return new_id;
end;
$$;

create or replace function public.admin_list_reports(
  p_status text default 'open',
  p_limit integer default 50,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
set statement_timeout = '10s'
as $$
declare
  result jsonb;
begin
  if not public.can_moderate() then
    raise exception 'Permesso moderazione richiesto' using errcode = '42501';
  end if;
  if p_status not in ('open','dismissed','removed','all') then raise exception 'Stato non valido'; end if;

  with filtered as materialized (
    select r.*
    from public.moderation_reports r
    where p_status = 'all' or r.status = p_status
  ), enriched as (
    select
      f.*,
      p.username as reporter_username,
      p.display_name as reporter_display_name,
      case
        when f.target_type = 'review' then (
          select jsonb_build_object('label', gr.game_title, 'body', gr.body, 'author_id', gr.user_id)
          from public.game_reviews gr where gr.id = f.target_id
        )
        when f.target_type = 'comment' then (
          select jsonb_build_object('label', 'Commento', 'body', cc.body, 'author_id', cc.user_id)
          from public.content_comments cc where cc.id = f.target_id
        )
        when f.target_type = 'list' then (
          select jsonb_build_object('label', ul.name, 'body', ul.description, 'author_id', ul.user_id)
          from public.user_lists ul where ul.id = f.target_id
        )
      end as target
    from filtered f
    left join public.profiles p on p.id = f.reporter_id
    order by f.created_at desc
    limit greatest(1, least(coalesce(p_limit, 50), 100))
    offset greatest(coalesce(p_offset, 0), 0)
  )
  select jsonb_build_object(
    'items', coalesce((select jsonb_agg(to_jsonb(enriched) order by created_at desc) from enriched), '[]'::jsonb),
    'total', (select count(*) from filtered)
  ) into result;
  return result;
end;
$$;

create or replace function public.admin_resolve_report(
  p_report_id uuid,
  p_action text,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  r public.moderation_reports%rowtype;
begin
  if not public.can_moderate() then
    raise exception 'Permesso moderazione richiesto' using errcode = '42501';
  end if;
  if p_action not in ('dismiss','remove') then raise exception 'Azione non valida'; end if;

  select * into r from public.moderation_reports where id = p_report_id for update;
  if not found then raise exception 'Segnalazione non trovata'; end if;

  if p_action = 'remove' then
    if r.target_type = 'review' then
      delete from public.content_comments where target_type = 'review' and target_id = r.target_id;
      delete from public.game_reviews where id = r.target_id;
    elsif r.target_type = 'comment' then
      delete from public.content_comments where id = r.target_id;
    elsif r.target_type = 'list' then
      delete from public.content_comments where target_type = 'list' and target_id = r.target_id;
      delete from public.user_lists where id = r.target_id;
    end if;
  end if;

  update public.moderation_reports
  set status = case when p_action = 'remove' then 'removed' else 'dismissed' end,
      resolution_note = nullif(btrim(p_note), ''),
      resolved_by = v_user,
      resolved_at = now(),
      updated_at = now()
  where id = p_report_id
  returning * into r;

  insert into public.admin_audit_log(actor_id, action, target_type, target_id, metadata)
  values (v_user, 'moderation_' || p_action, r.target_type, r.target_id::text, jsonb_build_object('report_id', r.id));
  return to_jsonb(r);
end;
$$;

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
begin
  if not public.is_admin() then
    raise exception 'Accesso amministratore richiesto' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(to_jsonb(s) order by s.store), '[]'::jsonb)
  into sync_rows
  from public.catalog_sync_state s;

  select jsonb_build_object(
    'database_size_bytes', pg_database_size(current_database()),
    'catalog_size_bytes', pg_total_relation_size('public.catalog_games'::regclass),
    'catalog_games', coalesce(c.total_games, 0),
    'catalog_listings', coalesce(c.total_listings, 0),
    'catalog_status', coalesce(c.status, 'unknown'),
    'catalog_updated_at', c.updated_at,
    'open_reports', (select count(*) from public.moderation_reports where status = 'open'),
    'pending_matches', (select count(*) from public.canonical_match_queue where status = 'pending'),
    'sync', sync_rows
  ) into stats
  from public.catalog_stats_cache c
  where c.singleton;

  if stats is null then
    stats := jsonb_build_object(
      'database_size_bytes', pg_database_size(current_database()),
      'catalog_size_bytes', pg_total_relation_size('public.catalog_games'::regclass),
      'catalog_games', 0,
      'catalog_listings', 0,
      'catalog_status', 'unknown',
      'open_reports', (select count(*) from public.moderation_reports where status = 'open'),
      'pending_matches', (select count(*) from public.canonical_match_queue where status = 'pending'),
      'sync', sync_rows
    );
  end if;
  return stats;
end;
$$;

revoke all on function public.admin_get_catalog_record(text) from public;
revoke all on function public.admin_save_catalog_override(text,jsonb,text[]) from public;
revoke all on function public.admin_clear_catalog_override(text) from public;
revoke all on function public.admin_list_match_queue(text,integer,integer) from public;
revoke all on function public.admin_review_match(uuid,text,text,text) from public;
revoke all on function public.report_content(text,uuid,text) from public;
revoke all on function public.admin_list_reports(text,integer,integer) from public;
revoke all on function public.admin_resolve_report(uuid,text,text) from public;
revoke all on function public.admin_system_status() from public;

grant execute on function public.admin_get_catalog_record(text) to authenticated;
grant execute on function public.admin_save_catalog_override(text,jsonb,text[]) to authenticated;
grant execute on function public.admin_clear_catalog_override(text) to authenticated;
grant execute on function public.admin_list_match_queue(text,integer,integer) to authenticated;
grant execute on function public.admin_review_match(uuid,text,text,text) to authenticated;
grant execute on function public.report_content(text,uuid,text) to authenticated;
grant execute on function public.admin_list_reports(text,integer,integer) to authenticated;
grant execute on function public.admin_resolve_report(uuid,text,text) to authenticated;
grant execute on function public.admin_system_status() to authenticated;

comment on table public.catalog_overrides is 'Override editoriali persistenti rispettati dai sync catalogo.';
comment on table public.moderation_reports is 'Segnalazioni utente per recensioni, commenti e liste.';
comment on function public.admin_system_status() is 'Dashboard tecnica leggera senza scansioni complete del catalogo.';

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
