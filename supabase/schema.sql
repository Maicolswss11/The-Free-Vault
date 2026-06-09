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
