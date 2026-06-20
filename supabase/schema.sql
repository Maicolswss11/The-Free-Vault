-- The Free Vault — schema utenti e sincronizzazione
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null unique check (char_length(username) between 3 and 30),
  display_name text not null check (char_length(display_name) between 1 and 60),
  bio text check (char_length(bio) <= 500),
  avatar_url text,
  hero_image_url text check (hero_image_url is null or char_length(hero_image_url) <= 2048),
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

alter table public.profiles
  add column if not exists hero_image_url text;

alter table public.profiles
  drop constraint if exists profiles_hero_image_url_length_check;
alter table public.profiles
  add constraint profiles_hero_image_url_length_check
  check (hero_image_url is null or char_length(hero_image_url) <= 2048);

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
  5242880,
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


-- The Free Vault v4.7 — Raccomandazioni personali e inserimento multiplo nelle saghe
-- The Free Vault v4.7 — Raccomandazioni personali e inserimento multiplo nelle saghe.
-- Eseguire dopo la v4.6.
-- Non crea nuove tabelle, copie del catalogo o indici: usa esclusivamente dati già presenti.

create or replace function public.admin_save_franchise_games_batch(
  p_franchise_id uuid,
  p_games jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_item jsonb;
  v_key text;
  v_relation_type text;
  v_release_order integer;
  v_narrative_order integer;
  v_note text;
  v_count integer := 0;
begin
  if not public.is_admin() then
    raise exception 'Accesso amministratore richiesto' using errcode = '42501';
  end if;

  if not exists (select 1 from public.franchises where id = p_franchise_id) then
    raise exception 'Franchise non trovato';
  end if;

  if p_games is null or jsonb_typeof(p_games) <> 'array' or jsonb_array_length(p_games) = 0 then
    raise exception 'Seleziona almeno un gioco';
  end if;

  if jsonb_array_length(p_games) > 100 then
    raise exception 'Puoi aggiungere al massimo 100 giochi per volta';
  end if;

  for v_item in select value from jsonb_array_elements(p_games)
  loop
    v_key := trim(coalesce(v_item ->> 'game_key', ''));
    v_relation_type := coalesce(nullif(trim(v_item ->> 'relation_type'), ''), 'main');
    v_release_order := nullif(v_item ->> 'release_order', '')::integer;
    v_narrative_order := nullif(v_item ->> 'narrative_order', '')::integer;
    v_note := nullif(trim(v_item ->> 'note'), '');

    if v_relation_type not in ('main', 'spin_off', 'remake', 'remaster', 'dlc', 'expansion', 'other') then
      raise exception 'Tipo relazione non valido per %', v_key;
    end if;
    if coalesce(v_release_order, 0) <= 0 then
      raise exception 'Ordine di uscita non valido per %', v_key;
    end if;
    if v_narrative_order is not null and v_narrative_order <= 0 then
      raise exception 'Ordine narrativo non valido per %', v_key;
    end if;
    if not exists (select 1 from public.catalog_games where match_key = v_key) then
      raise exception 'Gioco non trovato nel catalogo: %', v_key;
    end if;

    insert into public.franchise_games(
      franchise_id,
      game_key,
      relation_type,
      release_order,
      narrative_order,
      note
    ) values (
      p_franchise_id,
      v_key,
      v_relation_type,
      v_release_order,
      v_narrative_order,
      v_note
    )
    on conflict (franchise_id, game_key) do update set
      relation_type = excluded.relation_type,
      release_order = excluded.release_order,
      narrative_order = excluded.narrative_order,
      note = excluded.note,
      updated_at = now();

    v_count := v_count + 1;
  end loop;

  insert into public.admin_audit_log(actor_id, action, target_type, target_id, metadata)
  values (
    v_user,
    'franchise_games_batch_saved',
    'franchise',
    p_franchise_id::text,
    jsonb_build_object('count', v_count)
  );

  return public.admin_get_franchise(p_franchise_id);
end;
$$;

revoke all on function public.admin_save_franchise_games_batch(uuid, jsonb) from public;
grant execute on function public.admin_save_franchise_games_batch(uuid, jsonb) to authenticated;

create or replace function public.catalog_personalized_recommendations(
  p_limit integer default 12
)
returns jsonb
language sql
stable
security definer
set search_path = ''
set statement_timeout = '15s'
as $$
with
params as (
  select
    (select auth.uid()) as user_id,
    greatest(4, least(coalesce(p_limit, 12), 24)) as item_limit
),
diary_minutes as materialized (
  select
    gde.game_key,
    sum(gde.minutes_played)::integer as minutes_played
  from public.game_diary_entries gde
  join params p on p.user_id = gde.user_id
  group by gde.game_key
),
library_signals as materialized (
  select
    coalesce(
      nullif(ul.data #>> '{game,match_key}', ''),
      nullif(ul.data #>> '{game,canonical_id}', ''),
      ul.game_key
    ) as ref_key,
    (
      case when coalesce(nullif(ul.data ->> 'favorite', '')::boolean, false) then 6 else 0 end
      + case
          when coalesce(nullif(ul.data ->> 'rating', '')::numeric, 0) >= 4
            then (coalesce(nullif(ul.data ->> 'rating', '')::numeric, 0) - 2) * 2
          when coalesce(nullif(ul.data ->> 'rating', '')::numeric, 0) between 1 and 2 then -4
          else 0
        end
      + case coalesce(ul.data ->> 'status', 'saved')
          when 'completed' then 6
          when 'replay' then 4
          when 'playing' then 3
          when 'paused' then 1
          when 'backlog' then 1
          when 'abandoned' then -7
          else 0.5
        end
      + least(
          4::numeric,
          ln(1 + greatest(0, coalesce(nullif(ul.data ->> 'steamPlaytimeMinutes', '')::numeric, 0)) / 60)
        )
    )::numeric as signal_weight,
    coalesce(nullif(ul.data ->> 'favorite', '')::boolean, false) as favorite,
    coalesce(nullif(ul.data ->> 'rating', '')::numeric, 0) as rating,
    coalesce(ul.data ->> 'status', 'saved') as status,
    greatest(0, coalesce(nullif(ul.data ->> 'steamPlaytimeMinutes', '')::integer, 0)) as playtime_minutes,
    'library'::text as source
  from public.user_library ul
  join params p on p.user_id = ul.user_id
),
progress_signals as materialized (
  select
    ugp.game_key as ref_key,
    (
      case ugp.status
        when 'completed' then 7
        when 'replay' then 5
        when 'playing' then 3
        when 'paused' then 1
        when 'backlog' then 1
        when 'abandoned' then -8
        else 0.5
      end
      + least(
          5::numeric,
          ln(
            1 + greatest(
              0,
              coalesce(ugp.manual_playtime_minutes, 0) + coalesce(dm.minutes_played, 0)
            )::numeric / 60
          )
        )
      + case when ugp.progress_percent >= 80 then 2 when ugp.progress_percent >= 40 then 1 else 0 end
    )::numeric as signal_weight,
    false as favorite,
    0::numeric as rating,
    ugp.status,
    greatest(0, coalesce(ugp.manual_playtime_minutes, 0) + coalesce(dm.minutes_played, 0)) as playtime_minutes,
    'progress'::text as source
  from public.user_game_progress ugp
  join params p on p.user_id = ugp.user_id
  left join diary_minutes dm on dm.game_key = ugp.game_key
),
review_signals as materialized (
  select
    gr.game_key as ref_key,
    case gr.rating
      when 5 then 8
      when 4 then 5
      when 3 then 1
      when 2 then -3
      else -6
    end::numeric as signal_weight,
    false as favorite,
    gr.rating::numeric as rating,
    'reviewed'::text as status,
    0::integer as playtime_minutes,
    'review'::text as source
  from public.game_reviews gr
  join params p on p.user_id = gr.user_id
),
list_signals as materialized (
  select
    unnest(ul.game_keys) as ref_key,
    case
      when lower(ul.name) ~ '(wishlist|desider|da giocare|backlog)' then 2.5
      else 1
    end::numeric as signal_weight,
    false as favorite,
    0::numeric as rating,
    'listed'::text as status,
    0::integer as playtime_minutes,
    'list'::text as source
  from public.user_lists ul
  join params p on p.user_id = ul.user_id
),
raw_signals as materialized (
  select * from library_signals
  union all
  select * from progress_signals
  union all
  select * from review_signals
  union all
  select * from list_signals
),
resolved_signals as materialized (
  select
    cg.match_key,
    cg.title,
    sum(rs.signal_weight)::numeric as affinity,
    bool_or(rs.favorite) as favorite,
    max(rs.rating)::numeric as rating,
    max(rs.playtime_minutes)::integer as playtime_minutes,
    array_agg(distinct rs.status) as statuses,
    array_agg(distinct rs.source) as sources
  from raw_signals rs
  join lateral (
    select candidate.match_key, candidate.title
    from public.catalog_games candidate
    where candidate.match_key = rs.ref_key
       or candidate.canonical_id = rs.ref_key
    order by case when candidate.match_key = rs.ref_key then 0 else 1 end
    limit 1
  ) cg on true
  group by cg.match_key, cg.title
),
positive_games as materialized (
  select * from resolved_signals where affinity > 1
),
negative_games as materialized (
  select * from resolved_signals where affinity < 0
),
top_genres as materialized (
  select genre, round(sum(pg.affinity), 2) as weight
  from positive_games pg
  join public.catalog_games cg on cg.match_key = pg.match_key
  cross join lateral unnest(cg.genres) as genre
  where nullif(trim(genre), '') is not null
  group by genre
  order by weight desc, genre
  limit 8
),
negative_genres as materialized (
  select genre, round(sum(abs(ng.affinity)), 2) as weight
  from negative_games ng
  join public.catalog_games cg on cg.match_key = ng.match_key
  cross join lateral unnest(cg.genres) as genre
  where nullif(trim(genre), '') is not null
  group by genre
  order by weight desc, genre
  limit 8
),
top_developers as materialized (
  select cg.developer, round(sum(pg.affinity), 2) as weight
  from positive_games pg
  join public.catalog_games cg on cg.match_key = pg.match_key
  where nullif(trim(cg.developer), '') is not null
  group by cg.developer
  order by weight desc, cg.developer
  limit 6
),
negative_developers as materialized (
  select cg.developer, round(sum(abs(ng.affinity)), 2) as weight
  from negative_games ng
  join public.catalog_games cg on cg.match_key = ng.match_key
  where nullif(trim(cg.developer), '') is not null
  group by cg.developer
  order by weight desc, cg.developer
  limit 4
),
top_publishers as materialized (
  select cg.publisher, round(sum(pg.affinity), 2) as weight
  from positive_games pg
  join public.catalog_games cg on cg.match_key = pg.match_key
  where nullif(trim(cg.publisher), '') is not null
  group by cg.publisher
  order by weight desc, cg.publisher
  limit 4
),
top_segments as materialized (
  select cg.market_segment, round(sum(pg.affinity), 2) as weight
  from positive_games pg
  join public.catalog_games cg on cg.match_key = pg.match_key
  where cg.market_segment in ('aaa', 'indie')
  group by cg.market_segment
  order by weight desc, cg.market_segment
  limit 2
),
other_positive as materialized (
  select
    gr.user_id,
    gr.game_key as ref_key,
    greatest(1, gr.rating - 3)::numeric as weight
  from public.game_reviews gr
  join params p on gr.user_id <> p.user_id
  where gr.rating >= 4
    and public.can_view_user_content(gr.user_id, 'activity')

  union all

  select
    gde.user_id,
    gde.game_key as ref_key,
    least(3::numeric, 1 + sum(gde.minutes_played)::numeric / 600) as weight
  from public.game_diary_entries gde
  join params p on gde.user_id <> p.user_id
  where gde.visibility = 'public'
    and public.can_view_user_content(gde.user_id, 'activity')
    and (gde.progress_percent >= 50 or gde.minutes_played >= 120)
  group by gde.user_id, gde.game_key
),
similar_users as materialized (
  select
    op.user_id,
    count(distinct op.ref_key)::integer as overlap_count,
    round(sum(least(pg.affinity, 10) * op.weight), 2) as similarity
  from other_positive op
  join positive_games pg on pg.match_key = op.ref_key
  group by op.user_id
  order by similarity desc, overlap_count desc, op.user_id
  limit 30
),
collaborative_raw as materialized (
  select
    op.ref_key,
    round(sum(su.similarity * op.weight), 2) as collaborative_score,
    count(distinct op.user_id)::integer as similar_user_count
  from similar_users su
  join other_positive op on op.user_id = su.user_id
  where not exists (
    select 1 from resolved_signals own where own.match_key = op.ref_key
  )
  group by op.ref_key
  order by collaborative_score desc, similar_user_count desc, op.ref_key
  limit 250
),
collaborative_candidates as materialized (
  select
    cg.match_key,
    max(cr.collaborative_score) as collaborative_score,
    max(cr.similar_user_count) as similar_user_count
  from collaborative_raw cr
  join lateral (
    select candidate.match_key
    from public.catalog_games candidate
    where candidate.match_key = cr.ref_key
       or candidate.canonical_id = cr.ref_key
    order by case when candidate.match_key = cr.ref_key then 0 else 1 end
    limit 1
  ) cg on true
  where not exists (select 1 from resolved_signals own where own.match_key = cg.match_key)
  group by cg.match_key
),
metadata_candidates as materialized (
  select cg.match_key
  from public.catalog_games cg
  where cg.category_group = 'base_game'
    and cg.image_url is not null
    and not exists (select 1 from resolved_signals own where own.match_key = cg.match_key)
    and (
      exists (select 1 from top_genres tg where tg.genre = any(cg.genres))
      or exists (select 1 from top_developers td where lower(td.developer) = lower(cg.developer))
      or exists (select 1 from top_publishers tp where lower(tp.publisher) = lower(cg.publisher))
    )
  order by cg.release_date desc nulls last, cg.match_key
  limit 800
),
candidate_keys as materialized (
  select match_key from metadata_candidates
  union
  select match_key from collaborative_candidates
),
scored_candidates as materialized (
  select
    cg.*,
    coalesce(genre_fit.score, 0) as genre_score,
    coalesce(developer_fit.score, 0) as developer_score,
    coalesce(publisher_fit.score, 0) as publisher_score,
    coalesce(segment_fit.score, 0) as segment_score,
    coalesce(negative_genre_fit.score, 0) as negative_genre_score,
    coalesce(negative_developer_fit.score, 0) as negative_developer_score,
    coalesce(cc.collaborative_score, 0) as collaborative_score,
    coalesce(cc.similar_user_count, 0) as similar_user_count,
    coalesce(community.average_rating, 0) as community_rating,
    coalesce(community.review_count, 0) as community_review_count,
    seed_matches.seed_titles,
    shared_genre.genre as primary_shared_genre,
    (
      coalesce(genre_fit.score, 0) * 1.4
      + coalesce(developer_fit.score, 0) * 2.2
      + coalesce(publisher_fit.score, 0) * 0.9
      + least(8, coalesce(segment_fit.score, 0) * 0.35)
      + least(35, coalesce(cc.collaborative_score, 0) * 0.04)
      + case
          when coalesce(community.review_count, 0) > 0
            then coalesce(community.average_rating, 0) * ln(1 + community.review_count) * 0.55
          else 0
        end
      + case
          when cg.release_year >= extract(year from current_date)::integer - 2 then 2
          when cg.release_year >= extract(year from current_date)::integer - 5 then 1
          else 0
        end
      - coalesce(negative_genre_fit.score, 0) * 1.6
      - coalesce(negative_developer_fit.score, 0) * 2.2
    )::numeric as recommendation_score
  from candidate_keys ck
  join public.catalog_games cg on cg.match_key = ck.match_key
  left join collaborative_candidates cc on cc.match_key = cg.match_key
  left join lateral (
    select round(sum(tg.weight), 2) as score
    from top_genres tg
    where tg.genre = any(cg.genres)
  ) genre_fit on true
  left join lateral (
    select round(sum(td.weight), 2) as score
    from top_developers td
    where lower(td.developer) = lower(cg.developer)
  ) developer_fit on true
  left join lateral (
    select round(sum(tp.weight), 2) as score
    from top_publishers tp
    where lower(tp.publisher) = lower(cg.publisher)
  ) publisher_fit on true
  left join lateral (
    select round(sum(ts.weight), 2) as score
    from top_segments ts
    where ts.market_segment = cg.market_segment
  ) segment_fit on true
  left join lateral (
    select round(sum(ng.weight), 2) as score
    from negative_genres ng
    where ng.genre = any(cg.genres)
  ) negative_genre_fit on true
  left join lateral (
    select round(sum(nd.weight), 2) as score
    from negative_developers nd
    where lower(nd.developer) = lower(cg.developer)
  ) negative_developer_fit on true
  left join lateral (
    select
      round(avg(gr.rating)::numeric, 2) as average_rating,
      count(*)::integer as review_count
    from public.game_reviews gr
    where gr.game_key in (cg.match_key, cg.canonical_id)
      and public.can_view_user_content(gr.user_id, 'activity')
  ) community on true
  left join lateral (
    select array_agg(seed.title order by seed.affinity desc, seed.title) as seed_titles
    from (
      select pg.title, pg.affinity
      from positive_games pg
      join public.catalog_games source_game on source_game.match_key = pg.match_key
      where
        (nullif(source_game.developer, '') is not null and lower(source_game.developer) = lower(cg.developer))
        or source_game.genres && cg.genres
      order by pg.affinity desc, pg.title
      limit 2
    ) seed
  ) seed_matches on true
  left join lateral (
    select tg.genre
    from top_genres tg
    where tg.genre = any(cg.genres)
    order by tg.weight desc, tg.genre
    limit 1
  ) shared_genre on true
),
ranked as materialized (
  select *
  from scored_candidates
  where recommendation_score > 0
  order by recommendation_score desc, community_rating desc, release_date desc nulls last, match_key
  limit (select item_limit from params)
),
recommendation_items as (
  select coalesce(jsonb_agg(
    public.catalog_game_card_json(cg)
    || jsonb_build_object(
      'recommendation_score', round(r.recommendation_score, 2),
      'recommendation_confidence', least(99, greatest(1, round(45 + r.recommendation_score * 1.4)))::integer,
      'similar_user_count', r.similar_user_count,
      'reasons', to_jsonb(array_remove(array[
        case
          when cardinality(r.seed_titles) = 1 then 'Perché hai apprezzato ' || r.seed_titles[1]
          when cardinality(r.seed_titles) >= 2 then 'Perché hai apprezzato ' || r.seed_titles[1] || ' e ' || r.seed_titles[2]
          else null
        end,
        case
          when r.similar_user_count >= 2 then 'Apprezzato da utenti con gusti simili ai tuoi'
          else null
        end,
        case
          when r.primary_shared_genre is not null then 'In linea con il tuo interesse per ' || r.primary_shared_genre
          else null
        end,
        case
          when r.developer_score > 0 and nullif(r.developer, '') is not null then 'Altro titolo di ' || r.developer
          else null
        end
      ]::text[], null))
    )
    order by r.recommendation_score desc, r.community_rating desc, cg.release_date desc nulls last, cg.match_key
  ), '[]'::jsonb) as items
  from ranked r
  join public.catalog_games cg on cg.match_key = r.match_key
),
profile_summary as (
  select jsonb_build_object(
    'positive_signals', (select count(*) from positive_games),
    'negative_signals', (select count(*) from negative_games),
    'similar_users', (select count(*) from similar_users),
    'top_genres', coalesce((
      select jsonb_agg(jsonb_build_object('name', tg.genre, 'weight', tg.weight) order by tg.weight desc, tg.genre)
      from top_genres tg
    ), '[]'::jsonb),
    'top_developers', coalesce((
      select jsonb_agg(jsonb_build_object('name', td.developer, 'weight', td.weight) order by td.weight desc, td.developer)
      from top_developers td
    ), '[]'::jsonb)
  ) as value
)
select jsonb_build_object(
  'mode', case
    when (select user_id from params) is null then 'signed_out'
    when (select count(*) from positive_games) = 0 then 'cold_start'
    else 'personalized'
  end,
  'generated_at', now(),
  'profile', (select value from profile_summary),
  'items', (select items from recommendation_items)
);
$$;

revoke all on function public.catalog_personalized_recommendations(integer) from public;
grant execute on function public.catalog_personalized_recommendations(integer) to authenticated;

comment on function public.catalog_personalized_recommendations(integer) is
'Ranking personale senza nuove tabelle: combina libreria, preferiti, voti, progressi, diario, liste, metadati e segnali aggregati di utenti simili.';
-- The Free Vault v4.7.4 — catalog search performance hotfix.
--
-- The previous RPC materialized complete catalog_games rows before pagination
-- and mixed an indexable trigram predicate with a non-indexable similarity()
-- comparison. On a large catalog this could force broad scans and large
-- temporary results. This replacement searches lightweight keys first, pages
-- them, and only then loads the complete JSON payload for the visible rows.
-- No new table or index is created.

analyze public.catalog_games;

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
set statement_timeout = '12s'
as $$
with params as (
  select
    lower(trim(coalesce(p_query, ''))) as q,
    greatest(1, least(coalesce(p_limit, 36), 100)) as page_limit,
    greatest(0, coalesce(p_offset, 0)) as page_offset
),
search_matches as materialized (
  select
    raw.match_key,
    max(raw.relevance_score)::real as relevance_score
  from (
    -- Substring/exact/prefix lookup: backed by catalog_games_title_trgm_idx.
    select
      cg.match_key,
      case
        when lower(cg.title) = p.q then 100::real
        when lower(cg.canonical_title) = p.q then 95::real
        when lower(cg.title) like p.q || '%' then 80::real
        when lower(cg.canonical_title) like p.q || '%' then 75::real
        else (55 + extensions.similarity(lower(cg.title), p.q) * 20)::real
      end as relevance_score
    from public.catalog_games cg
    cross join params p
    where p.q <> ''
      and lower(cg.title) like '%' || p.q || '%'

    union all

    -- Fuzzy title lookup: the pg_trgm % operator is indexable, unlike
    -- similarity(column, query) >= threshold used as a filter.
    select
      cg.match_key,
      (35 + extensions.similarity(lower(cg.title), p.q) * 25)::real as relevance_score
    from public.catalog_games cg
    cross join params p
    where p.q <> ''
      and char_length(p.q) >= 3
      and lower(cg.title) operator(extensions.%) p.q
  ) raw
  group by raw.match_key
),
eligible as not materialized (
  select
    cg.match_key,
    cg.title,
    cg.release_date,
    cg.sort_price,
    coalesce(sm.relevance_score, 0::real) as relevance_score
  from public.catalog_games cg
  cross join params p
  left join search_matches sm on sm.match_key = cg.match_key
  where
    (p.q = '' or sm.match_key is not null)
    and (p_stores is null or cardinality(p_stores) = 0 or cg.stores && p_stores)
    and (p_category is null or p_category = '' or p_category = 'all' or cg.category_group = p_category)
    and (p_segment is null or p_segment = '' or p_segment = 'all' or cg.market_segment = p_segment)
    and (p_year is null or cg.release_year = p_year)
    and (
      p_price is null or p_price = '' or p_price = 'all'
      or (p_price = 'free' and exists (
        select 1
        from jsonb_array_elements(cg.store_listings) listing
        where coalesce(
          (listing ->> 'discount_price')::bigint,
          (listing ->> 'original_price')::bigint,
          1
        ) = 0
      ))
      or (p_price = 'discounted' and exists (
        select 1
        from jsonb_array_elements(cg.store_listings) listing
        where (listing ->> 'original_price') is not null
          and (listing ->> 'discount_price') is not null
          and (listing ->> 'discount_price')::bigint < (listing ->> 'original_price')::bigint
      ))
      or (p_price = 'paid' and cg.sort_price > 0)
    )
    and (
      p_personal_filter is null or p_personal_filter = '' or p_personal_filter = 'all'
      or (p_personal_filter = 'saved' and (
        cg.match_key = any(coalesce(p_library_keys, '{}'::text[]))
        or cg.canonical_id = any(coalesce(p_library_keys, '{}'::text[]))
      ))
      or (p_personal_filter = 'favorite' and (
        cg.match_key = any(coalesce(p_favorite_keys, '{}'::text[]))
        or cg.canonical_id = any(coalesce(p_favorite_keys, '{}'::text[]))
      ))
    )
),
counted as (
  select case
    when (
      (select q from params) = ''
      and (p_stores is null or cardinality(p_stores) = 0)
      and (p_category is null or p_category in ('', 'all'))
      and (p_segment is null or p_segment in ('', 'all'))
      and (p_price is null or p_price in ('', 'all'))
      and p_year is null
      and (p_personal_filter is null or p_personal_filter in ('', 'all'))
    ) then coalesce((select total_games from public.catalog_stats_cache where singleton), 0)
    else (select count(*) from eligible)
  end as total_count
),
paged_keys as (
  select e.*
  from eligible e
  cross join params p
  order by
    case when p_sort = 'title' or (p_sort = 'relevance' and p.q = '') then lower(e.title) end asc nulls last,
    case when p_sort = 'date' then e.release_date end desc nulls last,
    case when p_sort = 'value' then e.sort_price end desc nulls last,
    case when p_sort = 'relevance' and p.q <> '' then e.relevance_score end desc nulls last,
    lower(e.title) asc,
    e.match_key asc
  limit (select page_limit from params)
  offset (select page_offset from params)
),
page_rows as (
  select
    cg,
    pk.relevance_score,
    pk.title as sort_title,
    pk.release_date as sort_release_date,
    pk.sort_price as sort_value,
    pk.match_key as sort_match_key
  from paged_keys pk
  join public.catalog_games cg on cg.match_key = pk.match_key
)
select jsonb_build_object(
  'items', coalesce(jsonb_agg(
    public.catalog_game_card_json(cg)
    order by
      case when p_sort = 'title' or (p_sort = 'relevance' and (select q from params) = '') then lower(sort_title) end asc nulls last,
      case when p_sort = 'date' then sort_release_date end desc nulls last,
      case when p_sort = 'value' then sort_value end desc nulls last,
      case when p_sort = 'relevance' and (select q from params) <> '' then relevance_score end desc nulls last,
      lower(sort_title) asc,
      sort_match_key asc
  ), '[]'::jsonb),
  'total', (select total_count from counted),
  'limit', (select page_limit from params),
  'offset', (select page_offset from params)
)
from page_rows;
$$;

revoke all on function public.search_catalog(text, text[], text, text, text, integer, text[], text[], text, text, integer, integer) from public;
grant execute on function public.search_catalog(text, text[], text, text, text, integer, text[], text[], text, text, integer, integer) to anon, authenticated;

comment on function public.search_catalog(text, text[], text, text, text, integer, text[], text[], text, text, integer, integer) is
'Catalog search v4.7.4: indexed title matching, lightweight key pagination, full rows loaded only after LIMIT.';


-- Helper date condiviso dal catalogo set-based e dal Database Master.
create or replace function public.catalog_safe_date(p_value text)
returns date
language plpgsql
immutable
strict
set search_path = ''
as $$
begin
  if p_value !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
    return null;
  end if;

  return p_value::date;
exception
  when others then
    return null;
end;
$$;

revoke all on function public.catalog_safe_date(text) from public;
grant execute on function public.catalog_safe_date(text) to service_role;

-- v5.0 — Universal Game Database, fase 1
-- Migrazione sorgente: supabase/migrations/20260614_v50_universal_game_database.sql

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
-- The Free Vault v5.0.2
-- Wrapper RPC a singolo parametro JSONB per evitare ambiguità di risoluzione
-- della firma PostgREST sulla funzione batch IGDB a nove argomenti.

begin;

create or replace function public.upsert_igdb_master_payload(
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
set statement_timeout = '90s'
as $$
begin
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'p_payload deve essere un oggetto JSON';
  end if;

  return public.upsert_igdb_master_batch(
    nullif(p_payload ->> 'p_run_id', '')::uuid,
    coalesce(nullif(p_payload ->> 'p_cursor_id', '')::bigint, 0),
    coalesce(p_payload -> 'p_games', '[]'::jsonb),
    coalesce(p_payload -> 'p_platforms', '[]'::jsonb),
    coalesce(p_payload -> 'p_releases', '[]'::jsonb),
    coalesce(p_payload -> 'p_external_ids', '[]'::jsonb),
    coalesce(p_payload -> 'p_titles', '[]'::jsonb),
    coalesce(p_payload -> 'p_aliases', '[]'::jsonb),
    coalesce(p_payload -> 'p_projections', '[]'::jsonb)
  );
end;
$$;

revoke all on function public.upsert_igdb_master_payload(jsonb) from public;
grant execute on function public.upsert_igdb_master_payload(jsonb) to service_role;

comment on function public.upsert_igdb_master_payload(jsonb) is
'Wrapper PostgREST stabile per l''upsert batch IGDB; riceve un solo oggetto JSONB e delega alla funzione interna tipizzata.';

commit;

notify pgrst, 'reload schema';

-- v5.1 — editor massivo delle saghe
create or replace function public.admin_remove_franchise_games_batch(
  p_franchise_id uuid,
  p_game_keys jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_removed integer := 0;
begin
  if not public.is_admin() then
    raise exception 'Accesso amministratore richiesto' using errcode = '42501';
  end if;

  if not exists (select 1 from public.franchises where id = p_franchise_id) then
    raise exception 'Franchise non trovato';
  end if;

  if p_game_keys is null or jsonb_typeof(p_game_keys) <> 'array' or jsonb_array_length(p_game_keys) = 0 then
    raise exception 'Seleziona almeno un gioco';
  end if;

  if jsonb_array_length(p_game_keys) > 250 then
    raise exception 'Puoi rimuovere al massimo 250 giochi per volta';
  end if;

  delete from public.franchise_games fg
  where fg.franchise_id = p_franchise_id
    and fg.game_key in (
      select trim(value)
      from jsonb_array_elements_text(p_game_keys)
      where trim(value) <> ''
    );

  get diagnostics v_removed = row_count;

  insert into public.admin_audit_log(actor_id, action, target_type, target_id, metadata)
  values (
    v_user,
    'franchise_games_batch_removed',
    'franchise',
    p_franchise_id::text,
    jsonb_build_object('count', v_removed, 'game_keys', p_game_keys)
  );

  return public.admin_get_franchise(p_franchise_id);
end;
$$;

revoke all on function public.admin_remove_franchise_games_batch(uuid, jsonb) from public;
grant execute on function public.admin_remove_franchise_games_batch(uuid, jsonb) to authenticated;
-- The Free Vault v5.2 — Franchise Graph & Editorial Import
-- Percorsi narrativi, sottosaghe, relazioni e import/export JSON controllato.

begin;

create table if not exists public.franchise_tracks (
  id uuid primary key default gen_random_uuid(),
  franchise_id uuid not null references public.franchises(id) on delete cascade,
  parent_id uuid references public.franchise_tracks(id) on delete cascade,
  track_key text not null check (track_key ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' and char_length(track_key) between 2 and 100),
  name text not null check (char_length(name) between 2 and 160),
  track_type text not null default 'continuity'
    check (track_type in ('continuity', 'timeline', 'subseries', 'story_arc', 'anthology', 'remake_line', 'collection', 'other')),
  description text check (description is null or char_length(description) <= 3000),
  sort_order integer not null default 1 check (sort_order > 0),
  is_primary boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(franchise_id, track_key)
);

create table if not exists public.franchise_game_tracks (
  track_id uuid not null references public.franchise_tracks(id) on delete cascade,
  franchise_id uuid not null references public.franchises(id) on delete cascade,
  game_key text not null references public.catalog_games(match_key) on delete cascade,
  game_id text references public.games(id) on delete set null,
  narrative_order integer check (narrative_order is null or narrative_order > 0),
  release_order integer check (release_order is null or release_order > 0),
  canon_status text not null default 'unknown'
    check (canon_status in ('canon', 'alternate_canon', 'reimagining', 'non_canon', 'unknown', 'editorial_only')),
  note text check (note is null or char_length(note) <= 1500),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (track_id, game_key)
);

create table if not exists public.franchise_game_relations (
  franchise_id uuid not null references public.franchises(id) on delete cascade,
  source_game_key text not null references public.catalog_games(match_key) on delete cascade,
  target_game_key text not null references public.catalog_games(match_key) on delete cascade,
  source_game_id text references public.games(id) on delete set null,
  target_game_id text references public.games(id) on delete set null,
  relation_type text not null
    check (relation_type in ('sequel_to', 'prequel_to', 'remake_of', 'remaster_of', 'reimagines', 'alternate_version_of', 'parallel_to', 'expansion_of', 'collection_of', 'contains', 'spiritual_successor_to', 'related_to')),
  note text check (note is null or char_length(note) <= 1500),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (franchise_id, source_game_key, target_game_key, relation_type),
  check (source_game_key <> target_game_key)
);

create index if not exists franchise_tracks_franchise_sort_idx
on public.franchise_tracks(franchise_id, sort_order, track_key);

create index if not exists franchise_tracks_parent_idx
on public.franchise_tracks(parent_id);

create index if not exists franchise_game_tracks_franchise_idx
on public.franchise_game_tracks(franchise_id, track_id, narrative_order, game_key);

create index if not exists franchise_game_tracks_game_key_idx
on public.franchise_game_tracks(game_key);

create index if not exists franchise_game_relations_source_idx
on public.franchise_game_relations(franchise_id, source_game_key);

create index if not exists franchise_game_relations_target_idx
on public.franchise_game_relations(franchise_id, target_game_key);

alter table public.franchise_tracks enable row level security;
alter table public.franchise_game_tracks enable row level security;
alter table public.franchise_game_relations enable row level security;

revoke all on public.franchise_tracks from anon, authenticated;
revoke all on public.franchise_game_tracks from anon, authenticated;
revoke all on public.franchise_game_relations from anon, authenticated;

grant select, insert, update, delete on public.franchise_tracks to service_role;
grant select, insert, update, delete on public.franchise_game_tracks to service_role;
grant select, insert, update, delete on public.franchise_game_relations to service_role;

drop trigger if exists franchise_tracks_touch_updated_at on public.franchise_tracks;
create trigger franchise_tracks_touch_updated_at
before update on public.franchise_tracks
for each row execute function public.touch_editorial_updated_at();

drop trigger if exists franchise_game_tracks_touch_updated_at on public.franchise_game_tracks;
create trigger franchise_game_tracks_touch_updated_at
before update on public.franchise_game_tracks
for each row execute function public.touch_editorial_updated_at();

drop trigger if exists franchise_game_relations_touch_updated_at on public.franchise_game_relations;
create trigger franchise_game_relations_touch_updated_at
before update on public.franchise_game_relations
for each row execute function public.touch_editorial_updated_at();

create or replace function public.attach_franchise_game_track_master_game_id()
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

create or replace function public.attach_franchise_game_relation_master_ids()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.source_game_id is null and nullif(trim(new.source_game_key), '') is not null then
    new.source_game_id := public.resolve_master_game_id(new.source_game_key);
  end if;
  if new.target_game_id is null and nullif(trim(new.target_game_key), '') is not null then
    new.target_game_id := public.resolve_master_game_id(new.target_game_key);
  end if;
  return new;
end;
$$;

revoke all on function public.attach_franchise_game_track_master_game_id() from public;
revoke all on function public.attach_franchise_game_relation_master_ids() from public;

drop trigger if exists franchise_game_tracks_attach_master_game on public.franchise_game_tracks;
create trigger franchise_game_tracks_attach_master_game
before insert or update of game_key on public.franchise_game_tracks
for each row execute function public.attach_franchise_game_track_master_game_id();

drop trigger if exists franchise_game_relations_attach_master_games on public.franchise_game_relations;
create trigger franchise_game_relations_attach_master_games
before insert or update of source_game_key, target_game_key on public.franchise_game_relations
for each row execute function public.attach_franchise_game_relation_master_ids();

create or replace function public.franchise_tracks_json(p_franchise_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', t.id,
      'track_key', t.track_key,
      'name', t.name,
      'track_type', t.track_type,
      'description', t.description,
      'sort_order', t.sort_order,
      'is_primary', t.is_primary,
      'parent_track_key', parent.track_key
    ) order by t.sort_order, lower(t.name), t.track_key
  ), '[]'::jsonb)
  from public.franchise_tracks t
  left join public.franchise_tracks parent on parent.id = t.parent_id
  where t.franchise_id = p_franchise_id;
$$;

create or replace function public.franchise_game_relations_json(p_franchise_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'source_game_key', r.source_game_key,
      'target_game_key', r.target_game_key,
      'source_game_id', r.source_game_id,
      'target_game_id', r.target_game_id,
      'relation_type', r.relation_type,
      'note', r.note
    ) order by r.source_game_key, r.relation_type, r.target_game_key
  ), '[]'::jsonb)
  from public.franchise_game_relations r
  where r.franchise_id = p_franchise_id;
$$;

revoke all on function public.franchise_tracks_json(uuid) from public;
revoke all on function public.franchise_game_relations_json(uuid) from public;
grant execute on function public.franchise_tracks_json(uuid) to anon, authenticated, service_role;
grant execute on function public.franchise_game_relations_json(uuid) to anon, authenticated, service_role;

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
    'tracks', coalesce((select public.franchise_tracks_json(f.id) from selected f), '[]'::jsonb),
    'relations', coalesce((select public.franchise_game_relations_json(f.id) from selected f), '[]'::jsonb),
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
            where fgt.franchise_id = fg.franchise_id and fgt.game_key = fg.game_key
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
            where fgt.franchise_id = fg.franchise_id and fgt.game_key = fg.game_key
          ), '[]'::jsonb)
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

create or replace function public.admin_export_franchise_editorial(p_franchise_id uuid)
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
  if not exists (select 1 from public.franchises where id = p_franchise_id) then
    raise exception 'Franchise non trovato';
  end if;

  select jsonb_build_object(
    'schema_version', 'tfv-franchise-editorial-v2',
    'franchise', jsonb_build_object(
      'id', f.id,
      'slug', f.slug,
      'name', f.name,
      'status', f.status,
      'description', f.description
    ),
    'instructions', jsonb_build_object(
      'edit_only', jsonb_build_array('tracks', 'games.editorial', 'games.track_memberships', 'relations'),
      'do_not_change', jsonb_build_array('franchise.id', 'games.game_key', 'games.game_id', 'games.title'),
      'return_valid_json_only', true
    ),
    'allowed_values', jsonb_build_object(
      'entry_type', jsonb_build_array('main', 'spin_off', 'remake', 'remaster', 'dlc', 'expansion', 'other'),
      'track_type', jsonb_build_array('continuity', 'timeline', 'subseries', 'story_arc', 'anthology', 'remake_line', 'collection', 'other'),
      'canon_status', jsonb_build_array('canon', 'alternate_canon', 'reimagining', 'non_canon', 'unknown', 'editorial_only'),
      'relation_type', jsonb_build_array('sequel_to', 'prequel_to', 'remake_of', 'remaster_of', 'reimagines', 'alternate_version_of', 'parallel_to', 'expansion_of', 'collection_of', 'contains', 'spiritual_successor_to', 'related_to')
    ),
    'tracks', public.franchise_tracks_json(f.id),
    'relations', public.franchise_game_relations_json(f.id),
    'games', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'game_key', fg.game_key,
          'game_id', fg.game_id,
          'title', cg.title,
          'release_date', cg.release_date,
          'release_year', cg.release_year,
          'developer', cg.developer,
          'publisher', cg.publisher,
          'platforms', cg.platforms,
          'stores', cg.stores,
          'category_group', cg.category_group,
          'current', jsonb_build_object(
            'entry_type', fg.relation_type,
            'release_order', fg.release_order,
            'narrative_order', fg.narrative_order,
            'note', fg.note
          ),
          'editorial', jsonb_build_object(
            'entry_type', fg.relation_type,
            'release_order', fg.release_order,
            'narrative_order', fg.narrative_order,
            'canon_status', coalesce((
              select fgt.canon_status
              from public.franchise_game_tracks fgt
              where fgt.franchise_id = fg.franchise_id and fgt.game_key = fg.game_key
              order by case fgt.canon_status when 'canon' then 0 when 'alternate_canon' then 1 when 'reimagining' then 2 else 3 end
              limit 1
            ), 'unknown'),
            'notes', fg.note
          ),
          'track_memberships', coalesce((
            select jsonb_agg(jsonb_build_object(
              'track_key', ft.track_key,
              'narrative_order', fgt.narrative_order,
              'release_order', fgt.release_order,
              'canon_status', fgt.canon_status,
              'note', fgt.note
            ) order by ft.sort_order, fgt.narrative_order nulls last, ft.track_key)
            from public.franchise_game_tracks fgt
            join public.franchise_tracks ft on ft.id = fgt.track_id
            where fgt.franchise_id = fg.franchise_id and fgt.game_key = fg.game_key
          ), '[]'::jsonb)
        ) order by fg.release_order, lower(cg.title), cg.match_key
      )
      from public.franchise_games fg
      join public.catalog_games cg on cg.match_key = fg.game_key
      where fg.franchise_id = f.id
    ), '[]'::jsonb)
  ) into result
  from public.franchises f
  where f.id = p_franchise_id;

  return result;
end;
$$;

create or replace function public.admin_import_franchise_editorial(
  p_franchise_id uuid,
  p_payload jsonb,
  p_dry_run boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_schema text := coalesce(p_payload ->> 'schema_version', '');
  v_payload_franchise uuid;
  v_game jsonb;
  v_track jsonb;
  v_membership jsonb;
  v_relation jsonb;
  v_game_key text;
  v_track_key text;
  v_parent_key text;
  v_track_id uuid;
  v_source_key text;
  v_target_key text;
  v_games integer := 0;
  v_tracks integer := 0;
  v_memberships integer := 0;
  v_relations integer := 0;
  v_release_order integer;
  v_narrative_order integer;
  v_relation_type text;
  v_note text;
begin
  if not public.is_admin() then
    raise exception 'Accesso amministratore richiesto' using errcode = '42501';
  end if;
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'JSON editoriale non valido';
  end if;
  if v_schema <> 'tfv-franchise-editorial-v2' then
    raise exception 'schema_version non supportata: %', v_schema;
  end if;
  if not exists (select 1 from public.franchises where id = p_franchise_id) then
    raise exception 'Franchise non trovato';
  end if;
  if nullif(p_payload #>> '{franchise,id}', '') is not null then
    v_payload_franchise := (p_payload #>> '{franchise,id}')::uuid;
    if v_payload_franchise <> p_franchise_id then
      raise exception 'Il JSON appartiene a un altro franchise';
    end if;
  end if;
  if jsonb_typeof(coalesce(p_payload -> 'games', '[]'::jsonb)) <> 'array' then
    raise exception 'games deve essere un array';
  end if;
  if jsonb_typeof(coalesce(p_payload -> 'tracks', '[]'::jsonb)) <> 'array' then
    raise exception 'tracks deve essere un array';
  end if;
  if jsonb_typeof(coalesce(p_payload -> 'relations', '[]'::jsonb)) <> 'array' then
    raise exception 'relations deve essere un array';
  end if;

  for v_game in select value from jsonb_array_elements(coalesce(p_payload -> 'games', '[]'::jsonb)) loop
    v_game_key := trim(coalesce(v_game ->> 'game_key', v_game ->> 'match_key', ''));
    if v_game_key = '' then
      raise exception 'Un gioco del JSON non contiene game_key';
    end if;
    if not exists (select 1 from public.franchise_games fg where fg.franchise_id = p_franchise_id and fg.game_key = v_game_key) then
      raise exception 'Il gioco % non appartiene a questo franchise', v_game_key;
    end if;
    v_games := v_games + 1;
  end loop;

  for v_track in select value from jsonb_array_elements(coalesce(p_payload -> 'tracks', '[]'::jsonb)) loop
    v_track_key := trim(coalesce(v_track ->> 'track_key', ''));
    if v_track_key = '' or v_track_key !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' then
      raise exception 'track_key non valido: %', v_track_key;
    end if;
    if coalesce(v_track ->> 'track_type', 'continuity') not in ('continuity', 'timeline', 'subseries', 'story_arc', 'anthology', 'remake_line', 'collection', 'other') then
      raise exception 'track_type non valido per %', v_track_key;
    end if;
    v_tracks := v_tracks + 1;
  end loop;

  for v_relation in select value from jsonb_array_elements(coalesce(p_payload -> 'relations', '[]'::jsonb)) loop
    v_source_key := trim(coalesce(v_relation ->> 'source_game_key', ''));
    v_target_key := trim(coalesce(v_relation ->> 'target_game_key', ''));
    if v_source_key = '' or v_target_key = '' then
      raise exception 'Relazione con game_key mancante';
    end if;
    if v_source_key = v_target_key then
      raise exception 'Una relazione non può collegare un gioco a se stesso';
    end if;
    if coalesce(v_relation ->> 'relation_type', '') not in ('sequel_to', 'prequel_to', 'remake_of', 'remaster_of', 'reimagines', 'alternate_version_of', 'parallel_to', 'expansion_of', 'collection_of', 'contains', 'spiritual_successor_to', 'related_to') then
      raise exception 'relation_type non valido';
    end if;
    if not exists (select 1 from public.franchise_games where franchise_id = p_franchise_id and game_key = v_source_key) then
      raise exception 'Relazione con gioco sorgente esterno al franchise: %', v_source_key;
    end if;
    if not exists (select 1 from public.franchise_games where franchise_id = p_franchise_id and game_key = v_target_key) then
      raise exception 'Relazione con gioco target esterno al franchise: %', v_target_key;
    end if;
    v_relations := v_relations + 1;
  end loop;

  if not p_dry_run then
    delete from public.franchise_game_relations where franchise_id = p_franchise_id;
    delete from public.franchise_tracks where franchise_id = p_franchise_id;

    for v_track in select value from jsonb_array_elements(coalesce(p_payload -> 'tracks', '[]'::jsonb)) loop
      insert into public.franchise_tracks(
        franchise_id, track_key, name, track_type, description, sort_order, is_primary
      ) values (
        p_franchise_id,
        trim(v_track ->> 'track_key'),
        left(trim(coalesce(v_track ->> 'name', v_track ->> 'track_key')), 160),
        coalesce(nullif(v_track ->> 'track_type', ''), 'continuity'),
        nullif(v_track ->> 'description', ''),
        greatest(1, coalesce(nullif(v_track ->> 'sort_order', '')::integer, 1)),
        coalesce((v_track ->> 'is_primary')::boolean, false)
      );
    end loop;

    for v_track in select value from jsonb_array_elements(coalesce(p_payload -> 'tracks', '[]'::jsonb)) loop
      v_track_key := trim(v_track ->> 'track_key');
      v_parent_key := trim(coalesce(v_track ->> 'parent_track_key', ''));
      if v_parent_key <> '' then
        update public.franchise_tracks child
        set parent_id = parent.id
        from public.franchise_tracks parent
        where child.franchise_id = p_franchise_id
          and parent.franchise_id = p_franchise_id
          and child.track_key = v_track_key
          and parent.track_key = v_parent_key;
        if not found then
          raise exception 'parent_track_key non trovato: %', v_parent_key;
        end if;
      end if;
    end loop;

    for v_game in select value from jsonb_array_elements(coalesce(p_payload -> 'games', '[]'::jsonb)) loop
      v_game_key := trim(coalesce(v_game ->> 'game_key', v_game ->> 'match_key', ''));
      v_relation_type := coalesce(nullif(v_game #>> '{editorial,entry_type}', ''), nullif(v_game ->> 'relation_type', ''));
      if v_relation_type is not null and v_relation_type not in ('main', 'spin_off', 'remake', 'remaster', 'dlc', 'expansion', 'other') then
        raise exception 'entry_type non valido per %', v_game_key;
      end if;
      v_release_order := nullif(coalesce(v_game #>> '{editorial,release_order}', v_game ->> 'release_order', ''), '')::integer;
      v_narrative_order := nullif(coalesce(v_game #>> '{editorial,narrative_order}', v_game ->> 'narrative_order', ''), '')::integer;
      v_note := coalesce(nullif(v_game #>> '{editorial,notes}', ''), nullif(v_game #>> '{editorial,note}', ''), nullif(v_game ->> 'note', ''));

      update public.franchise_games fg
      set relation_type = coalesce(v_relation_type, fg.relation_type),
          release_order = coalesce(v_release_order, fg.release_order),
          narrative_order = v_narrative_order,
          note = coalesce(v_note, fg.note),
          updated_at = now()
      where fg.franchise_id = p_franchise_id and fg.game_key = v_game_key;

      for v_membership in select value from jsonb_array_elements(coalesce(v_game -> 'track_memberships', '[]'::jsonb)) loop
        v_track_key := trim(coalesce(v_membership ->> 'track_key', ''));
        if v_track_key = '' then
          raise exception 'Membership senza track_key per %', v_game_key;
        end if;
        select id into v_track_id
        from public.franchise_tracks
        where franchise_id = p_franchise_id and track_key = v_track_key;
        if v_track_id is null then
          raise exception 'track_key non trovato per membership: %', v_track_key;
        end if;
        if coalesce(v_membership ->> 'canon_status', 'unknown') not in ('canon', 'alternate_canon', 'reimagining', 'non_canon', 'unknown', 'editorial_only') then
          raise exception 'canon_status non valido per %', v_game_key;
        end if;
        insert into public.franchise_game_tracks(
          track_id, franchise_id, game_key, narrative_order, release_order, canon_status, note
        ) values (
          v_track_id,
          p_franchise_id,
          v_game_key,
          nullif(v_membership ->> 'narrative_order', '')::integer,
          nullif(v_membership ->> 'release_order', '')::integer,
          coalesce(nullif(v_membership ->> 'canon_status', ''), 'unknown'),
          nullif(v_membership ->> 'note', '')
        )
        on conflict (track_id, game_key) do update set
          narrative_order = excluded.narrative_order,
          release_order = excluded.release_order,
          canon_status = excluded.canon_status,
          note = excluded.note,
          updated_at = now();
        v_memberships := v_memberships + 1;
      end loop;
    end loop;

    for v_relation in select value from jsonb_array_elements(coalesce(p_payload -> 'relations', '[]'::jsonb)) loop
      insert into public.franchise_game_relations(
        franchise_id, source_game_key, target_game_key, relation_type, note
      ) values (
        p_franchise_id,
        trim(v_relation ->> 'source_game_key'),
        trim(v_relation ->> 'target_game_key'),
        v_relation ->> 'relation_type',
        nullif(v_relation ->> 'note', '')
      )
      on conflict (franchise_id, source_game_key, target_game_key, relation_type) do update set
        note = excluded.note,
        updated_at = now();
    end loop;

    insert into public.admin_audit_log(actor_id, action, target_type, target_id, metadata)
    values (
      v_user,
      'franchise_editorial_json_imported',
      'franchise',
      p_franchise_id::text,
      jsonb_build_object('games', v_games, 'tracks', v_tracks, 'track_memberships', v_memberships, 'relations', v_relations)
    );
  else
    for v_game in select value from jsonb_array_elements(coalesce(p_payload -> 'games', '[]'::jsonb)) loop
      v_memberships := v_memberships + jsonb_array_length(coalesce(v_game -> 'track_memberships', '[]'::jsonb));
    end loop;
  end if;

  return jsonb_build_object(
    'status', case when p_dry_run then 'validated' else 'applied' end,
    'schema_version', v_schema,
    'counts', jsonb_build_object(
      'games', v_games,
      'tracks', v_tracks,
      'track_memberships', v_memberships,
      'relations', v_relations
    ),
    'franchise', (select jsonb_build_object('id', id, 'slug', slug, 'name', name) from public.franchises where id = p_franchise_id)
  );
end;
$$;

revoke all on function public.admin_export_franchise_editorial(uuid) from public;
revoke all on function public.admin_import_franchise_editorial(uuid, jsonb, boolean) from public;
grant execute on function public.admin_export_franchise_editorial(uuid) to authenticated;
grant execute on function public.admin_import_franchise_editorial(uuid, jsonb, boolean) to authenticated;

comment on table public.franchise_tracks is 'Percorsi editoriali di un franchise: continuità, timeline, sottosaghe e archi narrativi.';
comment on table public.franchise_game_tracks is 'Appartenenza molti-a-molti dei giochi ai percorsi editoriali, con ordine narrativo per percorso.';
comment on table public.franchise_game_relations is 'Relazioni editoriali tra giochi di uno stesso franchise: remake, reinterpretazioni, sequel, raccolte e varianti.';
comment on function public.admin_export_franchise_editorial(uuid) is 'Esporta un pacchetto JSON controllato per organizzare un franchise con strumenti esterni come ChatGPT.';
comment on function public.admin_import_franchise_editorial(uuid, jsonb, boolean) is 'Valida e importa un pacchetto JSON editoriale del franchise in modo transazionale.';

commit;

notify pgrst, 'reload schema';
-- Ludograph v5.3.1 — Search Disambiguation & Franchise Deduplication
-- Raggruppa editorialmente i record con stesso titolo e stessa copertina,
-- senza eliminare i record Master originali dal catalogo.

begin;

create or replace function public.catalog_editorial_identity(
  p_title text,
  p_image_url text
)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_title text;
  v_cover text;
begin
  v_title := lower(regexp_replace(
    replace(replace(replace(coalesce(trim(p_title), ''), '™', ''), '®', ''), '©', ''),
    '[^[:alnum:]]+',
    '',
    'g'
  ));

  v_cover := lower(split_part(coalesce(trim(p_image_url), ''), '?', 1));
  v_cover := regexp_replace(v_cover, '^https?://', '', 'i');
  -- Le immagini IGDB possono cambiare solo per il preset t_cover_*.
  v_cover := regexp_replace(v_cover, '/t_[^/]+/', '/', 'g');

  if v_title = '' or v_cover = '' then
    return null;
  end if;

  return md5(v_title || '|' || v_cover);
end;
$$;

create or replace function public.catalog_game_type_priority(p_game_type text)
returns integer
language sql
immutable
set search_path = ''
as $$
  select case lower(coalesce(p_game_type, ''))
    when 'main_game' then 0
    when 'remake' then 1
    when 'remaster' then 2
    when 'expanded_game' then 3
    when 'standalone_expansion' then 4
    when 'expansion' then 5
    when 'port' then 6
    when 'episode' then 7
    when 'bundle' then 8
    when 'dlc_addon' then 9
    when 'pack' then 10
    when 'update' then 11
    else 20
  end;
$$;

revoke all on function public.catalog_editorial_identity(text, text) from public;
revoke all on function public.catalog_game_type_priority(text) from public;
grant execute on function public.catalog_editorial_identity(text, text) to anon, authenticated, service_role;
grant execute on function public.catalog_game_type_priority(text) to anon, authenticated, service_role;

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
    'fmt_discount_price', ((p_game).store_listings -> 0 ->> 'fmt_discount_price'),
    'game_type', master.game_type,
    'game_status', master.game_status,
    'igdb_id', master.source_external_id,
    'variant_parent_id', case
      when nullif(master.metadata ->> 'parent_game', '') is not null
        then 'igdb:' || (master.metadata ->> 'parent_game')
      when nullif(master.metadata ->> 'version_parent', '') is not null
        then 'igdb:' || (master.metadata ->> 'version_parent')
      else null
    end,
    'editorial_identity', public.catalog_editorial_identity((p_game).title, (p_game).image_url)
  )
  from (select 1) seed
  left join public.games master on master.id = (p_game).master_game_id;
$$;

revoke all on function public.catalog_game_card_json(public.catalog_games) from public;

create or replace function public.admin_search_franchise_candidates(
  p_query text,
  p_limit integer default 50
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
set statement_timeout = '15s'
as $$
declare
  v_result jsonb;
begin
  if not public.is_admin() then
    raise exception 'Accesso amministratore richiesto' using errcode = '42501';
  end if;

  with params as (
    select
      lower(trim(coalesce(p_query, ''))) as q,
      greatest(1, least(coalesce(p_limit, 50), 50)) as group_limit
  ), candidate_keys as materialized (
    select
      cg.match_key,
      coalesce(public.catalog_editorial_identity(cg.title, cg.image_url), cg.match_key) as group_key,
      case
        when lower(cg.title) = p.q then 100
        when lower(cg.canonical_title) = p.q then 95
        when lower(cg.title) like p.q || '%' then 80
        when lower(cg.canonical_title) like p.q || '%' then 75
        else 50
      end as relevance_score,
      public.catalog_game_type_priority(g.game_type) as type_priority,
      (
        case when cg.release_date is not null then 1 else 0 end
        + case when nullif(cg.developer, '') is not null then 1 else 0 end
        + case when cardinality(cg.platforms) > 0 then 1 else 0 end
        + case when nullif(cg.description, '') is not null then 1 else 0 end
      ) as completeness_score
    from public.catalog_games cg
    cross join params p
    left join public.games g on g.id = cg.master_game_id
    where p.q <> ''
      and lower(cg.title) like '%' || p.q || '%'
    order by relevance_score desc, lower(cg.title), cg.match_key
    limit 1000
  ), ranked as (
    select
      ck.*,
      row_number() over (
        partition by ck.group_key
        order by ck.type_priority, ck.completeness_score desc,
          (select release_date from public.catalog_games where match_key = ck.match_key) asc nulls last,
          ck.match_key
      ) as group_rank
    from candidate_keys ck
  ), groups as (
    select
      group_key,
      max(relevance_score) as relevance_score,
      max(match_key) filter (where group_rank = 1) as representative_key,
      count(*)::integer as variant_count
    from ranked
    group by group_key
    order by max(relevance_score) desc, group_key
    limit (select group_limit from params)
  )
  select coalesce(jsonb_agg(
    public.catalog_game_card_json(representative)
    || jsonb_build_object(
      'editorial_identity', groups.group_key,
      'variant_count', groups.variant_count,
      'variant_keys', coalesce((
        select jsonb_agg(r.match_key order by r.group_rank, r.match_key)
        from ranked r
        where r.group_key = groups.group_key
      ), '[]'::jsonb),
      'variants', coalesce((
        select jsonb_agg(public.catalog_game_card_json(variant_game)
          order by r.group_rank, lower(variant_game.title), variant_game.match_key)
        from ranked r
        join public.catalog_games variant_game on variant_game.match_key = r.match_key
        where r.group_key = groups.group_key
      ), '[]'::jsonb),
      'platforms', coalesce((
        select to_jsonb(array(
          select distinct platform
          from ranked r
          join public.catalog_games variant_game on variant_game.match_key = r.match_key
          cross join lateral unnest(variant_game.platforms) platform
          where r.group_key = groups.group_key
          order by platform
        ))
      ), '[]'::jsonb),
      'stores', coalesce((
        select to_jsonb(array(
          select distinct store_name
          from ranked r
          join public.catalog_games variant_game on variant_game.match_key = r.match_key
          cross join lateral unnest(variant_game.stores) store_name
          where r.group_key = groups.group_key
          order by store_name
        ))
      ), '[]'::jsonb)
    ) order by groups.relevance_score desc, lower(representative.title), representative.match_key
  ), '[]'::jsonb)
  into v_result
  from groups
  join public.catalog_games representative on representative.match_key = groups.representative_key;

  return coalesce(v_result, '[]'::jsonb);
end;
$$;

revoke all on function public.admin_search_franchise_candidates(text, integer) from public;
grant execute on function public.admin_search_franchise_candidates(text, integer) to authenticated;

create or replace function public.consolidate_franchise_variants_internal(p_franchise_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_duplicate record;
  v_merged integer := 0;
begin
  if not exists (select 1 from public.franchises where id = p_franchise_id) then
    raise exception 'Franchise non trovato';
  end if;

  for v_duplicate in
    with ranked as (
      select
        fg.game_key,
        public.catalog_editorial_identity(cg.title, cg.image_url) as identity_key,
        first_value(fg.game_key) over (
          partition by public.catalog_editorial_identity(cg.title, cg.image_url)
          order by public.catalog_game_type_priority(g.game_type),
            (case when cg.release_date is not null then 1 else 0 end
             + case when nullif(cg.developer, '') is not null then 1 else 0 end
             + case when cardinality(cg.platforms) > 0 then 1 else 0 end) desc,
            cg.release_date asc nulls last,
            fg.release_order asc,
            fg.game_key
        ) as keeper_key,
        row_number() over (
          partition by public.catalog_editorial_identity(cg.title, cg.image_url)
          order by public.catalog_game_type_priority(g.game_type),
            (case when cg.release_date is not null then 1 else 0 end
             + case when nullif(cg.developer, '') is not null then 1 else 0 end
             + case when cardinality(cg.platforms) > 0 then 1 else 0 end) desc,
            cg.release_date asc nulls last,
            fg.release_order asc,
            fg.game_key
        ) as duplicate_rank
      from public.franchise_games fg
      join public.catalog_games cg on cg.match_key = fg.game_key
      left join public.games g on g.id = cg.master_game_id
      where fg.franchise_id = p_franchise_id
        and public.catalog_editorial_identity(cg.title, cg.image_url) is not null
    )
    select game_key as duplicate_key, keeper_key
    from ranked
    where duplicate_rank > 1
  loop
    update public.franchise_games keeper
    set
      release_order = least(keeper.release_order, duplicate.release_order),
      narrative_order = coalesce(keeper.narrative_order, duplicate.narrative_order),
      note = coalesce(keeper.note, duplicate.note),
      updated_at = now()
    from public.franchise_games duplicate
    where keeper.franchise_id = p_franchise_id
      and keeper.game_key = v_duplicate.keeper_key
      and duplicate.franchise_id = p_franchise_id
      and duplicate.game_key = v_duplicate.duplicate_key;

    insert into public.franchise_game_tracks(
      track_id, franchise_id, game_key, game_id,
      narrative_order, release_order, canon_status, note
    )
    select
      track_id,
      franchise_id,
      v_duplicate.keeper_key,
      public.resolve_master_game_id(v_duplicate.keeper_key),
      narrative_order,
      release_order,
      canon_status,
      note
    from public.franchise_game_tracks
    where franchise_id = p_franchise_id
      and game_key = v_duplicate.duplicate_key
    on conflict (track_id, game_key) do update set
      narrative_order = coalesce(public.franchise_game_tracks.narrative_order, excluded.narrative_order),
      release_order = coalesce(public.franchise_game_tracks.release_order, excluded.release_order),
      canon_status = case
        when public.franchise_game_tracks.canon_status = 'unknown' then excluded.canon_status
        else public.franchise_game_tracks.canon_status
      end,
      note = coalesce(public.franchise_game_tracks.note, excluded.note),
      updated_at = now();

    delete from public.franchise_game_tracks
    where franchise_id = p_franchise_id
      and game_key = v_duplicate.duplicate_key;

    insert into public.franchise_game_relations(
      franchise_id, source_game_key, target_game_key, relation_type, note
    )
    select
      franchise_id,
      case when source_game_key = v_duplicate.duplicate_key then v_duplicate.keeper_key else source_game_key end,
      case when target_game_key = v_duplicate.duplicate_key then v_duplicate.keeper_key else target_game_key end,
      relation_type,
      note
    from public.franchise_game_relations
    where franchise_id = p_franchise_id
      and (source_game_key = v_duplicate.duplicate_key or target_game_key = v_duplicate.duplicate_key)
      and (case when source_game_key = v_duplicate.duplicate_key then v_duplicate.keeper_key else source_game_key end)
        <> (case when target_game_key = v_duplicate.duplicate_key then v_duplicate.keeper_key else target_game_key end)
    on conflict (franchise_id, source_game_key, target_game_key, relation_type) do update set
      note = coalesce(public.franchise_game_relations.note, excluded.note),
      updated_at = now();

    delete from public.franchise_game_relations
    where franchise_id = p_franchise_id
      and (source_game_key = v_duplicate.duplicate_key or target_game_key = v_duplicate.duplicate_key);

    delete from public.franchise_games
    where franchise_id = p_franchise_id
      and game_key = v_duplicate.duplicate_key;

    v_merged := v_merged + 1;
  end loop;

  return jsonb_build_object('merged', v_merged, 'franchise_id', p_franchise_id);
end;
$$;

revoke all on function public.consolidate_franchise_variants_internal(uuid) from public;

create or replace function public.admin_consolidate_franchise_variants(p_franchise_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
  v_user uuid := (select auth.uid());
begin
  if not public.is_admin() then
    raise exception 'Accesso amministratore richiesto' using errcode = '42501';
  end if;

  v_result := public.consolidate_franchise_variants_internal(p_franchise_id);

  if coalesce((v_result ->> 'merged')::integer, 0) > 0 then
    insert into public.admin_audit_log(actor_id, action, target_type, target_id, metadata)
    values (
      v_user,
      'franchise_variants_consolidated',
      'franchise',
      p_franchise_id::text,
      v_result
    );
  end if;

  return v_result || jsonb_build_object('franchise', public.admin_get_franchise(p_franchise_id));
end;
$$;

revoke all on function public.admin_consolidate_franchise_variants(uuid) from public;
grant execute on function public.admin_consolidate_franchise_variants(uuid) to authenticated;

create or replace function public.admin_save_franchise_games_batch(
  p_franchise_id uuid,
  p_games jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_item jsonb;
  v_key text;
  v_relation_type text;
  v_release_order integer;
  v_narrative_order integer;
  v_note text;
  v_count integer := 0;
begin
  if not public.is_admin() then
    raise exception 'Accesso amministratore richiesto' using errcode = '42501';
  end if;

  if not exists (select 1 from public.franchises where id = p_franchise_id) then
    raise exception 'Franchise non trovato';
  end if;

  if p_games is null or jsonb_typeof(p_games) <> 'array' or jsonb_array_length(p_games) = 0 then
    raise exception 'Seleziona almeno un gioco';
  end if;

  if jsonb_array_length(p_games) > 100 then
    raise exception 'Puoi aggiungere al massimo 100 giochi per volta';
  end if;

  for v_item in select value from jsonb_array_elements(p_games)
  loop
    v_key := trim(coalesce(v_item ->> 'game_key', ''));
    v_relation_type := coalesce(nullif(trim(v_item ->> 'relation_type'), ''), 'main');
    v_release_order := nullif(v_item ->> 'release_order', '')::integer;
    v_narrative_order := nullif(v_item ->> 'narrative_order', '')::integer;
    v_note := nullif(trim(v_item ->> 'note'), '');

    if v_relation_type not in ('main', 'spin_off', 'remake', 'remaster', 'dlc', 'expansion', 'other') then
      raise exception 'Tipo relazione non valido per %', v_key;
    end if;
    if coalesce(v_release_order, 0) <= 0 then
      raise exception 'Ordine di uscita non valido per %', v_key;
    end if;
    if v_narrative_order is not null and v_narrative_order <= 0 then
      raise exception 'Ordine narrativo non valido per %', v_key;
    end if;
    if not exists (select 1 from public.catalog_games where match_key = v_key) then
      raise exception 'Gioco non trovato nel catalogo: %', v_key;
    end if;

    insert into public.franchise_games(
      franchise_id,
      game_key,
      relation_type,
      release_order,
      narrative_order,
      note
    ) values (
      p_franchise_id,
      v_key,
      v_relation_type,
      v_release_order,
      v_narrative_order,
      v_note
    )
    on conflict (franchise_id, game_key) do update set
      relation_type = excluded.relation_type,
      release_order = excluded.release_order,
      narrative_order = excluded.narrative_order,
      note = excluded.note,
      updated_at = now();

    v_count := v_count + 1;
  end loop;

  perform public.consolidate_franchise_variants_internal(p_franchise_id);

  insert into public.admin_audit_log(actor_id, action, target_type, target_id, metadata)
  values (
    v_user,
    'franchise_games_batch_saved',
    'franchise',
    p_franchise_id::text,
    jsonb_build_object('count', v_count, 'deduplication', 'title_and_cover')
  );

  return public.admin_get_franchise(p_franchise_id);
end;
$$;

revoke all on function public.admin_save_franchise_games_batch(uuid, jsonb) from public;
grant execute on function public.admin_save_franchise_games_batch(uuid, jsonb) to authenticated;

-- Consolidamento una tantum delle saghe già presenti.
do $$
declare
  v_franchise record;
begin
  for v_franchise in select id from public.franchises loop
    perform public.consolidate_franchise_variants_internal(v_franchise.id);
  end loop;
end;
$$;

comment on function public.catalog_editorial_identity(text, text) is
'Identità editoriale prudente: stesso titolo normalizzato e stessa copertina normalizzata.';
comment on function public.admin_search_franchise_candidates(text, integer) is
'Ricerca amministrativa raggruppata per opera editoriale, con varianti espandibili.';
comment on function public.admin_consolidate_franchise_variants(uuid) is
'Unisce nel franchise i record con stesso titolo e stessa copertina, preservando percorsi e relazioni.';

commit;

notify pgrst, 'reload schema';

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

  perform public.consolidate_franchise_variants_internal(p_franchise_id);

  insert into public.admin_audit_log(actor_id, action, target_type, target_id, metadata)
  values (
    v_user,
    'franchise_game_saved',
    'franchise',
    p_franchise_id::text,
    jsonb_build_object('game_key', v_key, 'deduplication', 'title_and_cover')
  );
  return public.admin_get_franchise(p_franchise_id);
end;
$$;

revoke all on function public.admin_save_franchise_game(uuid, text, text, integer, integer, text) from public;
grant execute on function public.admin_save_franchise_game(uuid, text, text, integer, integer, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Ludograph v5.3.2 — Canonical game works and resilient cloud sync
-- ---------------------------------------------------------------------------
-- Ludograph v5.3.2 — Canonical game works, subordinate ports and resilient cloud sync
--
-- 1. Treats ports/derived versions as subordinate records of one editorial work.
-- 2. Exposes variants inside franchise cards without deleting Master records.
-- 3. Removes the expensive per-row library resolver path that could time out.

begin;

-- ---------------------------------------------------------------------------
-- Cloud sync: fast key resolution and a bounded batch RPC
-- ---------------------------------------------------------------------------

create index if not exists catalog_games_canonical_id_idx
on public.catalog_games(canonical_id);

create index if not exists games_parent_game_metadata_idx
on public.games ((metadata ->> 'parent_game'))
where nullif(metadata ->> 'parent_game', '') is not null;

create index if not exists games_version_parent_metadata_idx
on public.games ((metadata ->> 'version_parent'))
where nullif(metadata ->> 'version_parent', '') is not null;

create or replace function public.resolve_master_game_id(p_key text)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_key text := nullif(trim(p_key), '');
  v_candidate text;
  v_result text;
begin
  if v_key is null then
    return null;
  end if;

  select a.game_id into v_result
  from public.game_key_aliases a
  where a.alias_key = v_key
  limit 1;
  if v_result is not null then return v_result; end if;

  if v_key like 'master:%' then
    v_candidate := substring(v_key from 8);
    select g.id into v_result from public.games g where g.id = v_candidate limit 1;
    if v_result is not null then return v_result; end if;
  end if;

  select g.id into v_result
  from public.games g
  where g.id = v_key
  limit 1;
  if v_result is not null then return v_result; end if;

  select cg.master_game_id into v_result
  from public.catalog_games cg
  where cg.match_key = v_key
  limit 1;
  if v_result is not null then return v_result; end if;

  select cg.master_game_id into v_result
  from public.catalog_games cg
  where cg.canonical_id = v_key
    and cg.master_game_id is not null
  order by cg.match_key
  limit 1;

  return v_result;
end;
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
  -- An UPSERT may list game_key in the SET clause even when the value did not
  -- change. Do not resolve it again for every sign-in synchronization.
  if tg_op = 'UPDATE' and new.game_key is not distinct from old.game_key then
    return new;
  end if;

  if new.game_id is null and nullif(trim(new.game_key), '') is not null then
    new.game_id := public.resolve_master_game_id(new.game_key);
  end if;
  return new;
end;
$$;

revoke all on function public.attach_master_game_id_from_key() from public;

create or replace function public.sync_user_library_batch(p_rows jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
set statement_timeout = '20s'
as $$
declare
  v_user uuid := (select auth.uid());
  v_count integer := 0;
begin
  if v_user is null then
    raise exception 'Sessione richiesta' using errcode = '42501';
  end if;
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then
    raise exception 'p_rows deve essere un array JSON';
  end if;
  if jsonb_array_length(p_rows) > 250 then
    raise exception 'Massimo 250 elementi per batch';
  end if;

  insert into public.user_library(user_id, game_key, game_id, data, updated_at)
  select
    v_user,
    trim(r.game_key),
    public.resolve_master_game_id(trim(r.game_key)),
    coalesce(r.data, '{}'::jsonb),
    coalesce(r.updated_at, now())
  from jsonb_to_recordset(p_rows) as r(
    game_key text,
    data jsonb,
    updated_at timestamptz
  )
  where nullif(trim(r.game_key), '') is not null
  on conflict (user_id, game_key) do update set
    data = excluded.data,
    updated_at = excluded.updated_at,
    game_id = coalesce(public.user_library.game_id, excluded.game_id);

  get diagnostics v_count = row_count;
  return jsonb_build_object('status', 'ok', 'count', v_count);
end;
$$;

revoke all on function public.sync_user_library_batch(jsonb) from public;
grant execute on function public.sync_user_library_batch(jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- Canonical editorial works
-- ---------------------------------------------------------------------------

create or replace function public.catalog_normalized_title(p_title text)
returns text
language sql
immutable
set search_path = ''
as $$
  select lower(regexp_replace(
    replace(replace(replace(coalesce(trim(p_title), ''), '™', ''), '®', ''), '©', ''),
    '[^[:alnum:]]+',
    '',
    'g'
  ));
$$;

create or replace function public.catalog_cover_identity(p_image_url text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_cover text;
  v_filename text;
  v_token text;
begin
  v_cover := lower(split_part(coalesce(trim(p_image_url), ''), '?', 1));
  v_cover := regexp_replace(v_cover, '^https?://', '', 'i');
  v_cover := regexp_replace(v_cover, '/t_[^/]+/', '/', 'g');
  if v_cover = '' then return null; end if;

  v_filename := regexp_replace(v_cover, '^.*/', '');
  v_token := regexp_replace(v_filename, '\.(avif|gif|jpe?g|png|webp)$', '', 'i');

  -- IGDB keeps the same image_id while changing only host/preset/extension.
  if v_cover like '%images.igdb.com/%' and v_token ~ '^co[[:alnum:]_-]{3,}$' then
    return v_token;
  end if;
  if char_length(v_token) >= 12 then
    return v_token;
  end if;
  return md5(v_cover);
end;
$$;

create or replace function public.catalog_editorial_identity(
  p_title text,
  p_image_url text
)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when public.catalog_normalized_title(p_title) = ''
      or public.catalog_cover_identity(p_image_url) is null
      then null
    else md5(
      public.catalog_normalized_title(p_title)
      || '|'
      || public.catalog_cover_identity(p_image_url)
    )
  end;
$$;

create or replace function public.catalog_is_subordinate_game_type(p_game_type text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select lower(coalesce(p_game_type, 'unknown')) in ('port', 'fork', 'expanded_game');
$$;

create or replace function public.catalog_is_separate_game_type(p_game_type text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select lower(coalesce(p_game_type, 'unknown')) in (
    'remake', 'remaster', 'bundle', 'dlc_addon', 'expansion',
    'standalone_expansion', 'episode', 'pack', 'update'
  );
$$;

create index if not exists catalog_games_normalized_title_idx
on public.catalog_games (public.catalog_normalized_title(title));

create or replace function public.catalog_game_work_key(p_match_key text)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_base record;
  v_title text;
  v_parent text;
  v_master text;
  v_external text;
  v_primary_count integer := 0;
  v_primary_master text;
  v_has_subordinates boolean := false;
  v_identity text;
begin
  select
    cg.match_key,
    cg.title,
    cg.image_url,
    cg.master_game_id,
    coalesce(g.game_type, 'unknown') as game_type,
    nullif(g.metadata ->> 'parent_game', '') as parent_game,
    nullif(g.metadata ->> 'version_parent', '') as version_parent
  into v_base
  from public.catalog_games cg
  left join public.games g on g.id = cg.master_game_id
  where cg.match_key = trim(p_match_key)
  limit 1;

  if not found then return null; end if;

  v_title := public.catalog_normalized_title(v_base.title);
  v_master := nullif(v_base.master_game_id, '');
  v_parent := coalesce(v_base.parent_game, v_base.version_parent);

  if v_parent is not null then
    if position(':' in v_parent) = 0 then v_parent := 'igdb:' || v_parent; end if;
    return 'work:' || v_parent;
  end if;

  -- The original record must resolve to the same work as children that point to it.
  if v_master like 'igdb:%' then
    v_external := substring(v_master from 6);
    if exists (
      select 1
      from public.games child
      where child.metadata ->> 'parent_game' = v_external
         or child.metadata ->> 'version_parent' = v_external
    ) then
      return 'work:' || v_master;
    end if;
  end if;

  if v_title <> '' and not public.catalog_is_separate_game_type(v_base.game_type) then
    select
      count(*)::integer,
      min(cg.master_game_id)
    into v_primary_count, v_primary_master
    from public.catalog_games cg
    join public.games g on g.id = cg.master_game_id
    where cg.source_kind = 'master'
      and public.catalog_normalized_title(cg.title) = v_title
      and not public.catalog_is_subordinate_game_type(g.game_type)
      and not public.catalog_is_separate_game_type(g.game_type);

    select exists (
      select 1
      from public.catalog_games cg
      join public.games g on g.id = cg.master_game_id
      where cg.source_kind = 'master'
        and public.catalog_normalized_title(cg.title) = v_title
        and public.catalog_is_subordinate_game_type(g.game_type)
    ) into v_has_subordinates;

    if v_primary_count = 1
      and v_primary_master is not null
      and (
        public.catalog_is_subordinate_game_type(v_base.game_type)
        or v_master = v_primary_master
        or v_has_subordinates
      )
    then
      return 'work:' || v_primary_master;
    end if;
  end if;

  v_identity := public.catalog_editorial_identity(v_base.title, v_base.image_url);
  return coalesce('cover:' || v_identity, 'game:' || v_base.match_key);
end;
$$;

revoke all on function public.catalog_normalized_title(text) from public;
revoke all on function public.catalog_cover_identity(text) from public;
revoke all on function public.catalog_is_subordinate_game_type(text) from public;
revoke all on function public.catalog_is_separate_game_type(text) from public;
revoke all on function public.catalog_game_work_key(text) from public;
grant execute on function public.catalog_normalized_title(text) to anon, authenticated, service_role;
grant execute on function public.catalog_cover_identity(text) to anon, authenticated, service_role;
grant execute on function public.catalog_is_subordinate_game_type(text) to anon, authenticated, service_role;
grant execute on function public.catalog_is_separate_game_type(text) to anon, authenticated, service_role;
grant execute on function public.catalog_game_work_key(text) to anon, authenticated, service_role;

create or replace function public.catalog_game_work_members(p_match_key text)
returns table(match_key text)
language sql
stable
security definer
set search_path = ''
set statement_timeout = '8s'
as $$
  with base as materialized (
    select
      cg.match_key,
      public.catalog_normalized_title(cg.title) as normalized_title,
      public.catalog_game_work_key(cg.match_key) as work_key,
      case
        when public.catalog_game_work_key(cg.match_key) like 'work:%'
          then substring(public.catalog_game_work_key(cg.match_key) from 6)
        else null
      end as root_master_id
    from public.catalog_games cg
    where cg.match_key = trim(p_match_key)
    limit 1
  ), candidates as materialized (
    select cg.match_key
    from public.catalog_games cg
    cross join base b
    where public.catalog_normalized_title(cg.title) = b.normalized_title

    union

    select cg.match_key
    from public.catalog_games cg
    cross join base b
    where b.root_master_id is not null
      and cg.master_game_id = b.root_master_id

    union

    select cg.match_key
    from public.catalog_games cg
    join public.games g on g.id = cg.master_game_id
    cross join base b
    where b.root_master_id like 'igdb:%'
      and (
        g.metadata ->> 'parent_game' = substring(b.root_master_id from 6)
        or g.metadata ->> 'version_parent' = substring(b.root_master_id from 6)
      )
  )
  select distinct c.match_key
  from candidates c
  cross join base b
  where public.catalog_game_work_key(c.match_key) = b.work_key
  order by c.match_key;
$$;

revoke all on function public.catalog_game_work_members(text) from public;
grant execute on function public.catalog_game_work_members(text) to anon, authenticated, service_role;

create or replace function public.catalog_game_work_json(p_match_key text)
returns jsonb
language sql
stable
security definer
set search_path = ''
set statement_timeout = '8s'
as $$
  with members as materialized (
    select
      cg.match_key,
      coalesce(g.game_type, 'unknown') as resolved_game_type,
      public.catalog_game_type_priority(g.game_type) as type_priority,
      (
        case when cg.release_date is not null then 1 else 0 end
        + case when nullif(cg.developer, '') is not null then 1 else 0 end
        + case when cardinality(cg.platforms) > 0 then 1 else 0 end
        + case when nullif(cg.description, '') is not null then 1 else 0 end
      ) as completeness_score,
      cg.release_date
    from public.catalog_game_work_members(p_match_key) member
    join public.catalog_games cg on cg.match_key = member.match_key
    left join public.games g on g.id = cg.master_game_id
  ), ranked as (
    select
      members.*,
      row_number() over (
        order by type_priority, completeness_score desc,
          release_date asc nulls last, match_key
      ) as variant_rank
    from members
  )
  select jsonb_build_object(
    'editorial_work_key', public.catalog_game_work_key(p_match_key),
    'variant_count', count(*)::integer,
    'variant_keys', coalesce(jsonb_agg(ranked.match_key order by ranked.variant_rank), '[]'::jsonb),
    'variants', coalesce(jsonb_agg(
      public.catalog_game_card_json(variant_game)
      || jsonb_build_object(
        'variant_role', case
          when public.catalog_is_subordinate_game_type(ranked.resolved_game_type) then 'subordinate'
          else 'primary'
        end
      )
      order by ranked.variant_rank
    ), '[]'::jsonb),
    'platforms', to_jsonb(array(
      select distinct platform
      from ranked r
      join public.catalog_games member_game on member_game.match_key = r.match_key
      cross join lateral unnest(member_game.platforms) platform
      order by platform
    )),
    'stores', to_jsonb(array(
      select distinct store_name
      from ranked r
      join public.catalog_games member_game on member_game.match_key = r.match_key
      cross join lateral unnest(member_game.stores) store_name
      order by store_name
    ))
  )
  from ranked
  join public.catalog_games variant_game on variant_game.match_key = ranked.match_key;
$$;

revoke all on function public.catalog_game_work_json(text) from public;
grant execute on function public.catalog_game_work_json(text) to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Grouped admin search
-- ---------------------------------------------------------------------------

create or replace function public.admin_search_franchise_candidates(
  p_query text,
  p_limit integer default 50
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
set statement_timeout = '20s'
as $$
declare
  v_result jsonb;
begin
  if not public.is_admin() then
    raise exception 'Accesso amministratore richiesto' using errcode = '42501';
  end if;

  with params as (
    select
      lower(trim(coalesce(p_query, ''))) as q,
      greatest(1, least(coalesce(p_limit, 50), 50)) as group_limit
  ), candidate_keys as materialized (
    select
      cg.match_key,
      public.catalog_game_work_key(cg.match_key) as group_key,
      case
        when lower(cg.title) = p.q then 100
        when lower(cg.canonical_title) = p.q then 95
        when lower(cg.title) like p.q || '%' then 80
        when lower(cg.canonical_title) like p.q || '%' then 75
        else 50
      end as relevance_score,
      public.catalog_game_type_priority(g.game_type) as type_priority,
      (
        case when cg.release_date is not null then 1 else 0 end
        + case when nullif(cg.developer, '') is not null then 1 else 0 end
        + case when cardinality(cg.platforms) > 0 then 1 else 0 end
        + case when nullif(cg.description, '') is not null then 1 else 0 end
      ) as completeness_score
    from public.catalog_games cg
    cross join params p
    left join public.games g on g.id = cg.master_game_id
    where p.q <> ''
      and lower(cg.title) like '%' || p.q || '%'
    order by relevance_score desc, lower(cg.title), cg.match_key
    limit 1000
  ), ranked as (
    select
      ck.*,
      row_number() over (
        partition by ck.group_key
        order by ck.type_priority, ck.completeness_score desc,
          (select release_date from public.catalog_games where match_key = ck.match_key) asc nulls last,
          ck.match_key
      ) as group_rank
    from candidate_keys ck
  ), groups as (
    select
      group_key,
      max(relevance_score) as relevance_score,
      max(match_key) filter (where group_rank = 1) as representative_key,
      count(*)::integer as variant_count
    from ranked
    group by group_key
    order by max(relevance_score) desc, group_key
    limit (select group_limit from params)
  )
  select coalesce(jsonb_agg(
    public.catalog_game_card_json(representative)
    || public.catalog_game_work_json(representative.match_key)
    || jsonb_build_object(
      'editorial_identity', groups.group_key,
      'editorial_work_key', groups.group_key
    )
    order by groups.relevance_score desc, lower(representative.title), representative.match_key
  ), '[]'::jsonb)
  into v_result
  from groups
  join public.catalog_games representative on representative.match_key = groups.representative_key;

  return coalesce(v_result, '[]'::jsonb);
end;
$$;

revoke all on function public.admin_search_franchise_candidates(text, integer) from public;
grant execute on function public.admin_search_franchise_candidates(text, integer) to authenticated;

-- ---------------------------------------------------------------------------
-- Franchise payloads now expose subordinate versions under one work
-- ---------------------------------------------------------------------------

create or replace function public.franchise_detail(p_slug text)
returns jsonb
language sql
stable
security definer
set search_path = ''
set statement_timeout = '15s'
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
    'tracks', coalesce((select public.franchise_tracks_json(f.id) from selected f), '[]'::jsonb),
    'relations', coalesce((select public.franchise_game_relations_json(f.id) from selected f), '[]'::jsonb),
    'games', coalesce((
      select jsonb_agg(
        public.catalog_game_card_json(cg)
        || public.catalog_game_work_json(fg.game_key)
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
            where fgt.franchise_id = fg.franchise_id and fgt.game_key = fg.game_key
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
    'tracks', public.franchise_tracks_json(f.id),
    'relations', public.franchise_game_relations_json(f.id),
    'games', coalesce((
      select jsonb_agg(
        public.catalog_game_card_json(cg)
        || public.catalog_game_work_json(fg.game_key)
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
            where fgt.franchise_id = fg.franchise_id and fgt.game_key = fg.game_key
          ), '[]'::jsonb)
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

-- ---------------------------------------------------------------------------
-- Consolidate duplicate links using the new work key
-- ---------------------------------------------------------------------------

create or replace function public.consolidate_franchise_variants_internal(p_franchise_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_duplicate record;
  v_merged integer := 0;
begin
  if not exists (select 1 from public.franchises where id = p_franchise_id) then
    raise exception 'Franchise non trovato';
  end if;

  for v_duplicate in
    with ranked as (
      select
        fg.game_key,
        public.catalog_game_work_key(fg.game_key) as work_key,
        first_value(fg.game_key) over (
          partition by public.catalog_game_work_key(fg.game_key)
          order by public.catalog_game_type_priority(g.game_type),
            (case when cg.release_date is not null then 1 else 0 end
             + case when nullif(cg.developer, '') is not null then 1 else 0 end
             + case when cardinality(cg.platforms) > 0 then 1 else 0 end) desc,
            cg.release_date asc nulls last,
            fg.release_order asc,
            fg.game_key
        ) as keeper_key,
        row_number() over (
          partition by public.catalog_game_work_key(fg.game_key)
          order by public.catalog_game_type_priority(g.game_type),
            (case when cg.release_date is not null then 1 else 0 end
             + case when nullif(cg.developer, '') is not null then 1 else 0 end
             + case when cardinality(cg.platforms) > 0 then 1 else 0 end) desc,
            cg.release_date asc nulls last,
            fg.release_order asc,
            fg.game_key
        ) as duplicate_rank
      from public.franchise_games fg
      join public.catalog_games cg on cg.match_key = fg.game_key
      left join public.games g on g.id = cg.master_game_id
      where fg.franchise_id = p_franchise_id
        and public.catalog_game_work_key(fg.game_key) is not null
    )
    select game_key as duplicate_key, keeper_key
    from ranked
    where duplicate_rank > 1
  loop
    update public.franchise_games keeper
    set
      release_order = least(keeper.release_order, duplicate.release_order),
      narrative_order = coalesce(keeper.narrative_order, duplicate.narrative_order),
      note = coalesce(keeper.note, duplicate.note),
      updated_at = now()
    from public.franchise_games duplicate
    where keeper.franchise_id = p_franchise_id
      and keeper.game_key = v_duplicate.keeper_key
      and duplicate.franchise_id = p_franchise_id
      and duplicate.game_key = v_duplicate.duplicate_key;

    insert into public.franchise_game_tracks(
      track_id, franchise_id, game_key, game_id,
      narrative_order, release_order, canon_status, note
    )
    select
      track_id,
      franchise_id,
      v_duplicate.keeper_key,
      public.resolve_master_game_id(v_duplicate.keeper_key),
      narrative_order,
      release_order,
      canon_status,
      note
    from public.franchise_game_tracks
    where franchise_id = p_franchise_id
      and game_key = v_duplicate.duplicate_key
    on conflict (track_id, game_key) do update set
      narrative_order = coalesce(public.franchise_game_tracks.narrative_order, excluded.narrative_order),
      release_order = coalesce(public.franchise_game_tracks.release_order, excluded.release_order),
      canon_status = case
        when public.franchise_game_tracks.canon_status = 'unknown' then excluded.canon_status
        else public.franchise_game_tracks.canon_status
      end,
      note = coalesce(public.franchise_game_tracks.note, excluded.note),
      updated_at = now();

    delete from public.franchise_game_tracks
    where franchise_id = p_franchise_id
      and game_key = v_duplicate.duplicate_key;

    insert into public.franchise_game_relations(
      franchise_id, source_game_key, target_game_key, relation_type, note
    )
    select
      franchise_id,
      case when source_game_key = v_duplicate.duplicate_key then v_duplicate.keeper_key else source_game_key end,
      case when target_game_key = v_duplicate.duplicate_key then v_duplicate.keeper_key else target_game_key end,
      relation_type,
      note
    from public.franchise_game_relations
    where franchise_id = p_franchise_id
      and (source_game_key = v_duplicate.duplicate_key or target_game_key = v_duplicate.duplicate_key)
      and (case when source_game_key = v_duplicate.duplicate_key then v_duplicate.keeper_key else source_game_key end)
        <> (case when target_game_key = v_duplicate.duplicate_key then v_duplicate.keeper_key else target_game_key end)
    on conflict (franchise_id, source_game_key, target_game_key, relation_type) do update set
      note = coalesce(public.franchise_game_relations.note, excluded.note),
      updated_at = now();

    delete from public.franchise_game_relations
    where franchise_id = p_franchise_id
      and (source_game_key = v_duplicate.duplicate_key or target_game_key = v_duplicate.duplicate_key);

    delete from public.franchise_games
    where franchise_id = p_franchise_id
      and game_key = v_duplicate.duplicate_key;

    v_merged := v_merged + 1;
  end loop;

  return jsonb_build_object(
    'merged', v_merged,
    'franchise_id', p_franchise_id,
    'deduplication', 'canonical_work'
  );
end;
$$;

revoke all on function public.consolidate_franchise_variants_internal(uuid) from public;

-- Consolidate existing franchise links once. Master records are never deleted.
do $$
declare
  v_franchise record;
begin
  for v_franchise in select id from public.franchises loop
    perform public.consolidate_franchise_variants_internal(v_franchise.id);
  end loop;
end;
$$;

comment on function public.catalog_game_work_key(text) is
'Canonical editorial work key. Ports/forks/expanded versions are subordinate to one primary work; remakes and remasters remain separate.';
comment on function public.catalog_game_work_json(text) is
'Returns the primary work with its subordinate variants, platforms and stores.';
comment on function public.sync_user_library_batch(jsonb) is
'Bounded authenticated user-library UPSERT that avoids repeated game-key resolution during sign-in.';

commit;

notify pgrst, 'reload schema';

-- Ludograph v5.3.3 — catalog search scalability hotfix.
-- Migrazione sorgente: supabase/migrations/20260616_v533_catalog_search_scalability.sql

create index if not exists catalog_games_canonical_title_trgm_idx
on public.catalog_games using gin(lower(canonical_title) extensions.gin_trgm_ops);

create index if not exists catalog_games_lower_canonical_title_idx
on public.catalog_games(lower(canonical_title), match_key);

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
set statement_timeout = '15s'
as $$
with params as materialized (
  select
    lower(trim(coalesce(p_query, ''))) as q,
    greatest(1, least(coalesce(p_limit, 36), 100)) as page_limit,
    greatest(0, coalesce(p_offset, 0)) as page_offset,
    least(5000, greatest(500,
      (greatest(0, coalesce(p_offset, 0)) + greatest(1, least(coalesce(p_limit, 36), 100))) * 20
    )) as candidate_limit
),
substring_candidates as materialized (
  select ranked.match_key, ranked.relevance_score
  from (
    select cg.match_key,
      case
        when lower(cg.title) = p.q then 100::real
        when lower(cg.canonical_title) = p.q then 98::real
        when lower(cg.title) like p.q || '%' then 90::real
        when lower(cg.canonical_title) like p.q || '%' then 88::real
        when lower(cg.title) like '%' || p.q || '%' then 72::real
        else 68::real
      end as relevance_score,
      cg.release_date, cg.title
    from public.catalog_games cg
    cross join params p
    where p.q <> '' and (
      lower(cg.title) like '%' || p.q || '%'
      or lower(cg.canonical_title) like '%' || p.q || '%'
    )
    order by relevance_score desc, lower(cg.title), cg.release_date asc nulls last, cg.match_key
    limit (select candidate_limit from params)
  ) ranked
),
fuzzy_candidates as materialized (
  select ranked.match_key, ranked.relevance_score
  from (
    select cg.match_key,
      greatest(
        extensions.similarity(lower(cg.title), p.q),
        extensions.similarity(lower(cg.canonical_title), p.q)
      )::real * 25 + 35 as relevance_score,
      cg.release_date, cg.title
    from public.catalog_games cg
    cross join params p
    where p.q <> ''
      and char_length(p.q) >= 4
      and not exists (select 1 from substring_candidates)
      and (
        lower(cg.title) operator(extensions.%) p.q
        or lower(cg.canonical_title) operator(extensions.%) p.q
      )
    order by relevance_score desc, lower(cg.title), cg.release_date asc nulls last, cg.match_key
    limit (select least(candidate_limit, 1000) from params)
  ) ranked
),
search_candidates as materialized (
  select candidate.match_key, max(candidate.relevance_score)::real as relevance_score
  from (
    select * from substring_candidates
    union all
    select * from fuzzy_candidates
  ) candidate
  group by candidate.match_key
),
source_rows as not materialized (
  select cg.match_key, cg.title, cg.release_date, cg.sort_price, sc.relevance_score
  from search_candidates sc
  join public.catalog_games cg on cg.match_key = sc.match_key
  union all
  select cg.match_key, cg.title, cg.release_date, cg.sort_price, 0::real
  from public.catalog_games cg cross join params p where p.q = ''
),
eligible as not materialized (
  select sr.*
  from source_rows sr
  join public.catalog_games cg on cg.match_key = sr.match_key
  where
    (p_stores is null or cardinality(p_stores) = 0 or cg.stores && p_stores)
    and (p_category is null or p_category = '' or p_category = 'all' or cg.category_group = p_category)
    and (p_segment is null or p_segment = '' or p_segment = 'all' or cg.market_segment = p_segment)
    and (p_year is null or cg.release_year = p_year)
    and (
      p_price is null or p_price = '' or p_price = 'all'
      or (p_price = 'free' and exists (
        select 1 from jsonb_array_elements(cg.store_listings) listing
        where coalesce((listing ->> 'discount_price')::bigint, (listing ->> 'original_price')::bigint, 1) = 0
      ))
      or (p_price = 'discounted' and exists (
        select 1 from jsonb_array_elements(cg.store_listings) listing
        where (listing ->> 'original_price') is not null
          and (listing ->> 'discount_price') is not null
          and (listing ->> 'discount_price')::bigint < (listing ->> 'original_price')::bigint
      ))
      or (p_price = 'paid' and cg.sort_price > 0)
    )
    and (
      p_personal_filter is null or p_personal_filter = '' or p_personal_filter = 'all'
      or (p_personal_filter = 'saved' and (
        cg.match_key = any(coalesce(p_library_keys, '{}'::text[]))
        or cg.canonical_id = any(coalesce(p_library_keys, '{}'::text[]))
      ))
      or (p_personal_filter = 'favorite' and (
        cg.match_key = any(coalesce(p_favorite_keys, '{}'::text[]))
        or cg.canonical_id = any(coalesce(p_favorite_keys, '{}'::text[]))
      ))
    )
),
counted as materialized (
  select case
    when ((select q from params) = ''
      and (p_stores is null or cardinality(p_stores) = 0)
      and (p_category is null or p_category in ('', 'all'))
      and (p_segment is null or p_segment in ('', 'all'))
      and (p_price is null or p_price in ('', 'all'))
      and p_year is null
      and (p_personal_filter is null or p_personal_filter in ('', 'all')))
    then coalesce((select total_games from public.catalog_stats_cache where singleton), 0)
    else (select count(*) from eligible)
  end::bigint as total_count
),
paged_keys as materialized (
  select e.* from eligible e cross join params p
  order by
    case when p_sort = 'title' or (p_sort = 'relevance' and p.q = '') then lower(e.title) end asc nulls last,
    case when p_sort = 'date' then e.release_date end desc nulls last,
    case when p_sort = 'value' then e.sort_price end desc nulls last,
    case when p_sort = 'relevance' and p.q <> '' then e.relevance_score end desc nulls last,
    lower(e.title), e.match_key
  limit (select page_limit from params) offset (select page_offset from params)
),
page_rows as materialized (
  select cg, pk.relevance_score, pk.title as sort_title,
    pk.release_date as sort_release_date, pk.sort_price as sort_value,
    pk.match_key as sort_match_key
  from paged_keys pk join public.catalog_games cg on cg.match_key = pk.match_key
)
select jsonb_build_object(
  'items', coalesce(jsonb_agg(public.catalog_game_card_json(cg)
    order by
      case when p_sort = 'title' or (p_sort = 'relevance' and (select q from params) = '') then lower(sort_title) end asc nulls last,
      case when p_sort = 'date' then sort_release_date end desc nulls last,
      case when p_sort = 'value' then sort_value end desc nulls last,
      case when p_sort = 'relevance' and (select q from params) <> '' then relevance_score end desc nulls last,
      lower(sort_title), sort_match_key
  ), '[]'::jsonb),
  'total', (select total_count from counted),
  'limit', (select page_limit from params),
  'offset', (select page_offset from params),
  'has_more', ((select page_offset + page_limit from params) < (select total_count from counted)),
  'candidate_limited', ((select q from params) <> ''
    and (select count(*) from search_candidates) >= (select candidate_limit from params))
)
from page_rows;
$$;

revoke all on function public.search_catalog(text, text[], text, text, text, integer, text[], text[], text, text, integer, integer) from public;
grant execute on function public.search_catalog(text, text[], text, text, text, integer, text[], text[], text, text, integer, integer) to anon, authenticated;
-- Ludograph v5.3.4 — deterministic bounded catalog search execution plan
--
-- v5.3.3 added the correct trigram indexes, but the single SQL function still
-- allowed PostgreSQL to choose a pathological generic plan. In production the
-- raw indexed title lookup completed in milliseconds while search_catalog kept
-- running for minutes. This replacement performs candidate discovery first,
-- stores at most 5,000 ordered keys in a local array, and only then evaluates
-- filters, counts and JSON payloads over that bounded set.

begin;

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
language plpgsql
stable
security definer
set search_path = ''
set statement_timeout = '15s'
as $$
declare
  v_q text := lower(trim(coalesce(p_query, '')));
  v_limit integer := greatest(1, least(coalesce(p_limit, 36), 100));
  v_offset integer := greatest(0, coalesce(p_offset, 0));
  v_candidate_limit integer;
  v_candidate_keys text[] := '{}'::text[];
  v_candidate_limited boolean := false;
  v_total bigint := 0;
  v_result jsonb;
  v_has_filters boolean;
begin
  v_candidate_limit := least(
    5000,
    greatest(500, (v_offset + v_limit) * 20)
  );

  v_has_filters :=
    (p_stores is not null and cardinality(p_stores) > 0)
    or (p_category is not null and p_category not in ('', 'all'))
    or (p_segment is not null and p_segment not in ('', 'all'))
    or (p_price is not null and p_price not in ('', 'all'))
    or p_year is not null
    or (p_personal_filter is not null and p_personal_filter not in ('', 'all'));

  if v_q <> '' then
    -- Phase 1: indexed substring candidates. Each branch can use its own GIN
    -- trigram index; the bounded array becomes the hard boundary for all later
    -- work, independently of the generic plan chosen for the RPC.
    select coalesce(array_agg(limited.match_key order by limited.relevance_score desc, limited.sort_title, limited.release_date asc nulls last, limited.match_key), '{}'::text[])
    into v_candidate_keys
    from (
      select
        deduped.match_key,
        deduped.relevance_score,
        deduped.sort_title,
        deduped.release_date
      from (
        select
          raw.match_key,
          max(raw.relevance_score)::real as relevance_score,
          min(raw.sort_title) as sort_title,
          min(raw.release_date) as release_date
        from (
          select
            cg.match_key,
            case
              when lower(cg.title) = v_q then 100::real
              when lower(cg.title) like v_q || '%' then 90::real
              else 72::real
            end as relevance_score,
            lower(cg.title) as sort_title,
            cg.release_date
          from public.catalog_games cg
          where lower(cg.title) like '%' || v_q || '%'

          union all

          select
            cg.match_key,
            case
              when lower(cg.canonical_title) = v_q then 98::real
              when lower(cg.canonical_title) like v_q || '%' then 88::real
              else 68::real
            end as relevance_score,
            lower(cg.title) as sort_title,
            cg.release_date
          from public.catalog_games cg
          where lower(cg.canonical_title) like '%' || v_q || '%'
        ) raw
        group by raw.match_key
      ) deduped
      order by deduped.relevance_score desc, deduped.sort_title,
        deduped.release_date asc nulls last, deduped.match_key
      limit v_candidate_limit
    ) limited;

    -- Phase 2: fuzzy matching only when substring lookup found nothing.
    if cardinality(v_candidate_keys) = 0 and char_length(v_q) >= 4 then
      select coalesce(array_agg(limited.match_key order by limited.relevance_score desc, limited.sort_title, limited.release_date asc nulls last, limited.match_key), '{}'::text[])
      into v_candidate_keys
      from (
        select
          deduped.match_key,
          deduped.relevance_score,
          deduped.sort_title,
          deduped.release_date
        from (
          select
            raw.match_key,
            max(raw.relevance_score)::real as relevance_score,
            min(raw.sort_title) as sort_title,
            min(raw.release_date) as release_date
          from (
            select
              cg.match_key,
              (35 + extensions.similarity(lower(cg.title), v_q) * 25)::real as relevance_score,
              lower(cg.title) as sort_title,
              cg.release_date
            from public.catalog_games cg
            where lower(cg.title) operator(extensions.%) v_q

            union all

            select
              cg.match_key,
              (35 + extensions.similarity(lower(cg.canonical_title), v_q) * 25)::real as relevance_score,
              lower(cg.title) as sort_title,
              cg.release_date
            from public.catalog_games cg
            where lower(cg.canonical_title) operator(extensions.%) v_q
          ) raw
          group by raw.match_key
        ) deduped
        order by deduped.relevance_score desc, deduped.sort_title,
          deduped.release_date asc nulls last, deduped.match_key
        limit least(v_candidate_limit, 1000)
      ) limited;
    end if;

    v_candidate_limited := cardinality(v_candidate_keys) >= v_candidate_limit;

    with candidate_keys as materialized (
      select keys.match_key, keys.relevance_rank
      from unnest(v_candidate_keys) with ordinality as keys(match_key, relevance_rank)
    ), eligible as materialized (
      select
        cg.match_key,
        cg.title,
        cg.release_date,
        cg.sort_price,
        ck.relevance_rank
      from candidate_keys ck
      join public.catalog_games cg on cg.match_key = ck.match_key
      where
        (p_stores is null or cardinality(p_stores) = 0 or cg.stores && p_stores)
        and (p_category is null or p_category = '' or p_category = 'all' or cg.category_group = p_category)
        and (p_segment is null or p_segment = '' or p_segment = 'all' or cg.market_segment = p_segment)
        and (p_year is null or cg.release_year = p_year)
        and (
          p_price is null or p_price = '' or p_price = 'all'
          or (p_price = 'free' and exists (
            select 1
            from jsonb_array_elements(cg.store_listings) listing
            where coalesce(
              (listing ->> 'discount_price')::bigint,
              (listing ->> 'original_price')::bigint,
              1
            ) = 0
          ))
          or (p_price = 'discounted' and exists (
            select 1
            from jsonb_array_elements(cg.store_listings) listing
            where (listing ->> 'original_price') is not null
              and (listing ->> 'discount_price') is not null
              and (listing ->> 'discount_price')::bigint < (listing ->> 'original_price')::bigint
          ))
          or (p_price = 'paid' and cg.sort_price > 0)
        )
        and (
          p_personal_filter is null or p_personal_filter = '' or p_personal_filter = 'all'
          or (p_personal_filter = 'saved' and (
            cg.match_key = any(coalesce(p_library_keys, '{}'::text[]))
            or cg.canonical_id = any(coalesce(p_library_keys, '{}'::text[]))
          ))
          or (p_personal_filter = 'favorite' and (
            cg.match_key = any(coalesce(p_favorite_keys, '{}'::text[]))
            or cg.canonical_id = any(coalesce(p_favorite_keys, '{}'::text[]))
          ))
        )
    ), page_keys as materialized (
      select e.*
      from eligible e
      order by
        case when p_sort = 'title' then lower(e.title) end asc nulls last,
        case when p_sort = 'date' then e.release_date end desc nulls last,
        case when p_sort = 'value' then e.sort_price end desc nulls last,
        case when p_sort = 'relevance' or p_sort is null or p_sort = '' then e.relevance_rank end asc nulls last,
        lower(e.title) asc,
        e.match_key asc
      limit v_limit
      offset v_offset
    ), page_payload as (
      select coalesce(jsonb_agg(
        public.catalog_game_card_json(cg)
        order by
          case when p_sort = 'title' then lower(pk.title) end asc nulls last,
          case when p_sort = 'date' then pk.release_date end desc nulls last,
          case when p_sort = 'value' then pk.sort_price end desc nulls last,
          case when p_sort = 'relevance' or p_sort is null or p_sort = '' then pk.relevance_rank end asc nulls last,
          lower(pk.title) asc,
          pk.match_key asc
      ), '[]'::jsonb) as items
      from page_keys pk
      join public.catalog_games cg on cg.match_key = pk.match_key
    )
    select
      (select count(*) from eligible),
      jsonb_build_object(
        'items', page_payload.items,
        'total', (select count(*) from eligible),
        'limit', v_limit,
        'offset', v_offset,
        'has_more', v_offset + v_limit < (select count(*) from eligible),
        'candidate_limited', v_candidate_limited
      )
    into v_total, v_result
    from page_payload;

    return coalesce(v_result, jsonb_build_object(
      'items', '[]'::jsonb,
      'total', 0,
      'limit', v_limit,
      'offset', v_offset,
      'has_more', false,
      'candidate_limited', false
    ));
  end if;

  -- Empty-query fast path. With no filters, use the cached catalog total and
  -- page directly from indexed sort columns. This is the normal catalog home.
  if not v_has_filters then
    select coalesce(total_games, 0)
    into v_total
    from public.catalog_stats_cache
    where singleton;

    v_total := coalesce(v_total, 0);

    if p_sort = 'date' then
      select jsonb_build_object(
        'items', coalesce(jsonb_agg(public.catalog_game_card_json(page.game)
          order by page.release_date desc nulls last, lower(page.title), page.match_key), '[]'::jsonb),
        'total', v_total,
        'limit', v_limit,
        'offset', v_offset,
        'has_more', v_offset + v_limit < v_total,
        'candidate_limited', false
      )
      into v_result
      from (
        select cg as game, cg.release_date, cg.title, cg.match_key
        from public.catalog_games cg
        order by cg.release_date desc nulls last, lower(cg.title), cg.match_key
        limit v_limit offset v_offset
      ) page;
    elsif p_sort = 'value' then
      select jsonb_build_object(
        'items', coalesce(jsonb_agg(public.catalog_game_card_json(page.game)
          order by page.sort_price desc nulls last, lower(page.title), page.match_key), '[]'::jsonb),
        'total', v_total,
        'limit', v_limit,
        'offset', v_offset,
        'has_more', v_offset + v_limit < v_total,
        'candidate_limited', false
      )
      into v_result
      from (
        select cg as game, cg.sort_price, cg.title, cg.match_key
        from public.catalog_games cg
        order by cg.sort_price desc nulls last, lower(cg.title), cg.match_key
        limit v_limit offset v_offset
      ) page;
    else
      select jsonb_build_object(
        'items', coalesce(jsonb_agg(public.catalog_game_card_json(page.game)
          order by lower(page.title), page.match_key), '[]'::jsonb),
        'total', v_total,
        'limit', v_limit,
        'offset', v_offset,
        'has_more', v_offset + v_limit < v_total,
        'candidate_limited', false
      )
      into v_result
      from (
        select cg as game, cg.title, cg.match_key
        from public.catalog_games cg
        order by lower(cg.title), cg.match_key
        limit v_limit offset v_offset
      ) page;
    end if;

    return v_result;
  end if;

  -- Filtered browsing without a text query. It may inspect the catalog, but it
  -- is isolated from the normal text-search path and keeps the previous API.
  with eligible as materialized (
    select
      cg.match_key,
      cg.title,
      cg.release_date,
      cg.sort_price
    from public.catalog_games cg
    where
      (p_stores is null or cardinality(p_stores) = 0 or cg.stores && p_stores)
      and (p_category is null or p_category = '' or p_category = 'all' or cg.category_group = p_category)
      and (p_segment is null or p_segment = '' or p_segment = 'all' or cg.market_segment = p_segment)
      and (p_year is null or cg.release_year = p_year)
      and (
        p_price is null or p_price = '' or p_price = 'all'
        or (p_price = 'free' and exists (
          select 1
          from jsonb_array_elements(cg.store_listings) listing
          where coalesce(
            (listing ->> 'discount_price')::bigint,
            (listing ->> 'original_price')::bigint,
            1
          ) = 0
        ))
        or (p_price = 'discounted' and exists (
          select 1
          from jsonb_array_elements(cg.store_listings) listing
          where (listing ->> 'original_price') is not null
            and (listing ->> 'discount_price') is not null
            and (listing ->> 'discount_price')::bigint < (listing ->> 'original_price')::bigint
        ))
        or (p_price = 'paid' and cg.sort_price > 0)
      )
      and (
        p_personal_filter is null or p_personal_filter = '' or p_personal_filter = 'all'
        or (p_personal_filter = 'saved' and (
          cg.match_key = any(coalesce(p_library_keys, '{}'::text[]))
          or cg.canonical_id = any(coalesce(p_library_keys, '{}'::text[]))
        ))
        or (p_personal_filter = 'favorite' and (
          cg.match_key = any(coalesce(p_favorite_keys, '{}'::text[]))
          or cg.canonical_id = any(coalesce(p_favorite_keys, '{}'::text[]))
        ))
      )
  ), page_keys as materialized (
    select e.*
    from eligible e
    order by
      case when p_sort = 'date' then e.release_date end desc nulls last,
      case when p_sort = 'value' then e.sort_price end desc nulls last,
      lower(e.title) asc,
      e.match_key asc
    limit v_limit offset v_offset
  ), page_payload as (
    select coalesce(jsonb_agg(
      public.catalog_game_card_json(cg)
      order by
        case when p_sort = 'date' then pk.release_date end desc nulls last,
        case when p_sort = 'value' then pk.sort_price end desc nulls last,
        lower(pk.title), pk.match_key
    ), '[]'::jsonb) as items
    from page_keys pk
    join public.catalog_games cg on cg.match_key = pk.match_key
  )
  select
    (select count(*) from eligible),
    jsonb_build_object(
      'items', page_payload.items,
      'total', (select count(*) from eligible),
      'limit', v_limit,
      'offset', v_offset,
      'has_more', v_offset + v_limit < (select count(*) from eligible),
      'candidate_limited', false
    )
  into v_total, v_result
  from page_payload;

  return coalesce(v_result, jsonb_build_object(
    'items', '[]'::jsonb,
    'total', 0,
    'limit', v_limit,
    'offset', v_offset,
    'has_more', false,
    'candidate_limited', false
  ));
end;
$$;

revoke all on function public.search_catalog(text, text[], text, text, text, integer, text[], text[], text, text, integer, integer) from public;
grant execute on function public.search_catalog(text, text[], text, text, text, integer, text[], text[], text, text, integer, integer) to anon, authenticated;

comment on function public.search_catalog(text, text[], text, text, text, integer, text[], text[], text, text, integer, integer) is
'Ludograph v5.3.4: two-phase bounded search; indexed candidate keys are materialized before filtering and JSON generation.';

commit;

notify pgrst, 'reload schema';

-- Ludograph v5.3.5 — scalable editorial/franchise candidate search
--
-- The universal catalog search was fixed in v5.3.4, but the admin franchise
-- picker still evaluated catalog_game_work_key() and catalog_game_work_json()
-- repeatedly over a catalog with hundreds of thousands of rows. This replaces
-- that path with the same hard candidate boundary used by search_catalog:
-- indexed discovery first, then grouping and JSON construction only over the
-- bounded candidate set.

begin;

create or replace function public.admin_search_franchise_candidates(
  p_query text,
  p_limit integer default 50
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
set statement_timeout = '12s'
as $$
declare
  v_q text := lower(trim(coalesce(p_query, '')));
  v_group_limit integer := greatest(1, least(coalesce(p_limit, 50), 50));
  v_candidate_limit integer;
  v_candidate_keys text[] := '{}'::text[];
  v_result jsonb;
begin
  if not public.is_admin() then
    raise exception 'Accesso amministratore richiesto' using errcode = '42501';
  end if;

  if v_q = '' then
    return '[]'::jsonb;
  end if;

  v_candidate_limit := least(1500, greatest(300, v_group_limit * 20));

  select coalesce(
    array_agg(
      limited.match_key
      order by limited.relevance_score desc,
        limited.sort_title,
        limited.release_date asc nulls last,
        limited.match_key
    ),
    '{}'::text[]
  )
  into v_candidate_keys
  from (
    select
      deduped.match_key,
      deduped.relevance_score,
      deduped.sort_title,
      deduped.release_date
    from (
      select
        raw.match_key,
        max(raw.relevance_score)::real as relevance_score,
        min(raw.sort_title) as sort_title,
        min(raw.release_date) as release_date
      from (
        select
          cg.match_key,
          case
            when lower(cg.title) = v_q then 100::real
            when lower(cg.title) like v_q || '%' then 90::real
            else 72::real
          end as relevance_score,
          lower(cg.title) as sort_title,
          cg.release_date
        from public.catalog_games cg
        where lower(cg.title) like '%' || v_q || '%'

        union all

        select
          cg.match_key,
          case
            when lower(cg.canonical_title) = v_q then 98::real
            when lower(cg.canonical_title) like v_q || '%' then 88::real
            else 68::real
          end as relevance_score,
          lower(cg.title) as sort_title,
          cg.release_date
        from public.catalog_games cg
        where lower(cg.canonical_title) like '%' || v_q || '%'
      ) raw
      group by raw.match_key
    ) deduped
    order by deduped.relevance_score desc,
      deduped.sort_title,
      deduped.release_date asc nulls last,
      deduped.match_key
    limit v_candidate_limit
  ) limited;

  if cardinality(v_candidate_keys) = 0 and char_length(v_q) >= 4 then
    select coalesce(
      array_agg(
        limited.match_key
        order by limited.relevance_score desc,
          limited.sort_title,
          limited.release_date asc nulls last,
          limited.match_key
      ),
      '{}'::text[]
    )
    into v_candidate_keys
    from (
      select
        deduped.match_key,
        deduped.relevance_score,
        deduped.sort_title,
        deduped.release_date
      from (
        select
          raw.match_key,
          max(raw.relevance_score)::real as relevance_score,
          min(raw.sort_title) as sort_title,
          min(raw.release_date) as release_date
        from (
          select
            cg.match_key,
            (35 + extensions.similarity(lower(cg.title), v_q) * 25)::real as relevance_score,
            lower(cg.title) as sort_title,
            cg.release_date
          from public.catalog_games cg
          where lower(cg.title) operator(extensions.%) v_q

          union all

          select
            cg.match_key,
            (35 + extensions.similarity(lower(cg.canonical_title), v_q) * 25)::real as relevance_score,
            lower(cg.title) as sort_title,
            cg.release_date
          from public.catalog_games cg
          where lower(cg.canonical_title) operator(extensions.%) v_q
        ) raw
        group by raw.match_key
      ) deduped
      order by deduped.relevance_score desc,
        deduped.sort_title,
        deduped.release_date asc nulls last,
        deduped.match_key
      limit least(v_candidate_limit, 750)
    ) limited;
  end if;

  if cardinality(v_candidate_keys) = 0 then
    return '[]'::jsonb;
  end if;

  with candidate_keys as materialized (
    select keys.match_key, keys.relevance_rank
    from unnest(v_candidate_keys) with ordinality
      as keys(match_key, relevance_rank)
  ), candidate_data as materialized (
    select
      cg.match_key,
      cg.master_game_id,
      cg.title,
      cg.canonical_title,
      cg.image_url,
      cg.release_date,
      cg.platforms,
      cg.stores,
      ck.relevance_rank,
      public.catalog_normalized_title(cg.title) as normalized_title,
      public.catalog_editorial_identity(cg.title, cg.image_url) as cover_identity,
      coalesce(g.game_type, 'unknown') as game_type,
      public.catalog_game_type_priority(g.game_type) as type_priority,
      case
        when nullif(g.metadata ->> 'parent_game', '') is not null then
          case
            when position(':' in (g.metadata ->> 'parent_game')) = 0
              then 'igdb:' || (g.metadata ->> 'parent_game')
            else g.metadata ->> 'parent_game'
          end
        when nullif(g.metadata ->> 'version_parent', '') is not null then
          case
            when position(':' in (g.metadata ->> 'version_parent')) = 0
              then 'igdb:' || (g.metadata ->> 'version_parent')
            else g.metadata ->> 'version_parent'
          end
        else null
      end as explicit_parent_id,
      (
        case when cg.release_date is not null then 1 else 0 end
        + case when nullif(cg.developer, '') is not null then 1 else 0 end
        + case when cardinality(cg.platforms) > 0 then 1 else 0 end
        + case when nullif(cg.description, '') is not null then 1 else 0 end
      ) as completeness_score
    from candidate_keys ck
    join public.catalog_games cg on cg.match_key = ck.match_key
    left join public.games g on g.id = cg.master_game_id
  ), title_stats as materialized (
    select
      cd.normalized_title,
      count(*) filter (
        where not public.catalog_is_subordinate_game_type(cd.game_type)
          and not public.catalog_is_separate_game_type(cd.game_type)
      )::integer as primary_count,
      min(cd.master_game_id) filter (
        where cd.master_game_id is not null
          and not public.catalog_is_subordinate_game_type(cd.game_type)
          and not public.catalog_is_separate_game_type(cd.game_type)
      ) as primary_master_id,
      bool_or(public.catalog_is_subordinate_game_type(cd.game_type)) as has_subordinates
    from candidate_data cd
    where cd.normalized_title <> ''
    group by cd.normalized_title
  ), keyed as materialized (
    select
      cd.*,
      case
        when cd.explicit_parent_id is not null
          then 'work:' || cd.explicit_parent_id
        when cd.master_game_id is not null
          and exists (
            select 1
            from candidate_data child
            where child.explicit_parent_id = cd.master_game_id
          )
          then 'work:' || cd.master_game_id
        when public.catalog_is_separate_game_type(cd.game_type)
          then coalesce(
            case when cd.cover_identity is not null then 'cover:' || cd.cover_identity end,
            'game:' || cd.match_key
          )
        when public.catalog_is_subordinate_game_type(cd.game_type)
          and ts.primary_count = 1
          and ts.primary_master_id is not null
          then 'work:' || ts.primary_master_id
        when not public.catalog_is_subordinate_game_type(cd.game_type)
          and not public.catalog_is_separate_game_type(cd.game_type)
          and ts.primary_count = 1
          and ts.has_subordinates
          and cd.master_game_id = ts.primary_master_id
          then 'work:' || ts.primary_master_id
        when cd.cover_identity is not null
          then 'cover:' || cd.cover_identity
        else 'game:' || cd.match_key
      end as group_key
    from candidate_data cd
    left join title_stats ts on ts.normalized_title = cd.normalized_title
  ), ranked as materialized (
    select
      k.*,
      row_number() over (
        partition by k.group_key
        order by
          k.type_priority,
          k.completeness_score desc,
          k.release_date asc nulls last,
          k.relevance_rank,
          k.match_key
      ) as variant_rank
    from keyed k
  ), group_summary as materialized (
    select
      r.group_key,
      min(r.relevance_rank) as relevance_rank,
      max(r.match_key) filter (where r.variant_rank = 1) as representative_key,
      count(*)::integer as variant_count
    from ranked r
    group by r.group_key
    order by min(r.relevance_rank), r.group_key
    limit v_group_limit
  ), selected_variants as materialized (
    select r.*
    from ranked r
    join group_summary gs on gs.group_key = r.group_key
  )
  select coalesce(
    jsonb_agg(
      public.catalog_game_card_json(representative)
      || jsonb_build_object(
        'editorial_identity', gs.group_key,
        'editorial_work_key', gs.group_key,
        'variant_count', gs.variant_count,
        'variant_keys', coalesce((
          select jsonb_agg(sv.match_key order by sv.variant_rank)
          from selected_variants sv
          where sv.group_key = gs.group_key
        ), '[]'::jsonb),
        'variants', coalesce((
          select jsonb_agg(
            public.catalog_game_card_json(variant_game)
            || jsonb_build_object(
              'variant_role', case
                when public.catalog_is_subordinate_game_type(sv.game_type)
                  then 'subordinate'
                else 'primary'
              end
            )
            order by sv.variant_rank
          )
          from selected_variants sv
          join public.catalog_games variant_game
            on variant_game.match_key = sv.match_key
          where sv.group_key = gs.group_key
        ), '[]'::jsonb),
        'platforms', to_jsonb(array(
          select distinct platform_name
          from selected_variants sv
          cross join lateral unnest(sv.platforms) as platform_name
          where sv.group_key = gs.group_key
          order by platform_name
        )),
        'stores', to_jsonb(array(
          select distinct store_name
          from selected_variants sv
          cross join lateral unnest(sv.stores) as store_name
          where sv.group_key = gs.group_key
          order by store_name
        ))
      )
      order by gs.relevance_rank, lower(representative.title), representative.match_key
    ),
    '[]'::jsonb
  )
  into v_result
  from group_summary gs
  join public.catalog_games representative
    on representative.match_key = gs.representative_key;

  return coalesce(v_result, '[]'::jsonb);
end;
$$;

revoke all on function public.admin_search_franchise_candidates(text, integer) from public;
grant execute on function public.admin_search_franchise_candidates(text, integer) to authenticated;

comment on function public.admin_search_franchise_candidates(text, integer) is
  'Ludograph v5.3.5: bounded candidate-first franchise/editorial search; groups ports and duplicate covers without catalog-wide work resolution.';

commit;

notify pgrst, 'reload schema';

-- ---------------------------------------------------------------------------
-- Ludograph v5.3.7 — fast set-based franchise writes
-- Source migration: supabase/migrations/20260616_v537_franchise_batch_write_performance.sql
-- ---------------------------------------------------------------------------

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
  if v_requested = 0 then raise exception 'Seleziona almeno un gioco'; end if;
  if v_requested > 250 then raise exception 'Puoi salvare al massimo 250 giochi per batch'; end if;

  with parsed as materialized (
    select
      nullif(trim(game_key), '') as game_key,
      coalesce(nullif(trim(relation_type), ''), 'main') as relation_type,
      release_order,
      narrative_order,
      nullif(trim(note), '') as note
    from jsonb_to_recordset(p_games) as row_data(
      game_key text, relation_type text, release_order integer,
      narrative_order integer, note text
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
    franchise_id, game_key, relation_type, release_order, narrative_order, note
  )
  select
    p_franchise_id, parsed.game_key, parsed.relation_type,
    parsed.release_order, parsed.narrative_order, parsed.note
  from (
    select distinct on (nullif(trim(game_key), ''))
      nullif(trim(game_key), '') as game_key,
      coalesce(nullif(trim(relation_type), ''), 'main') as relation_type,
      release_order,
      narrative_order,
      nullif(trim(note), '') as note
    from jsonb_to_recordset(p_games) as row_data(
      game_key text, relation_type text, release_order integer,
      narrative_order integer, note text
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

notify pgrst, 'reload schema';
-- Ludograph v5.3.8 — set-based editorial JSON import.
-- Replaces the row-by-row franchise importer and avoids the expensive
-- canonical consolidation request after every JSON application.

begin;

create or replace function public.admin_import_franchise_editorial(
  p_franchise_id uuid,
  p_payload jsonb,
  p_dry_run boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = ''
set statement_timeout = '30s'
as $$
declare
  v_user uuid := (select auth.uid());
  v_schema text := coalesce(p_payload ->> 'schema_version', '');
  v_payload_franchise uuid;
  v_games integer := 0;
  v_tracks integer := 0;
  v_memberships integer := 0;
  v_relations integer := 0;
  v_invalid text;
begin
  if not public.is_admin() then
    raise exception 'Accesso amministratore richiesto' using errcode = '42501';
  end if;

  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'JSON editoriale non valido';
  end if;

  if v_schema <> 'tfv-franchise-editorial-v2' then
    raise exception 'schema_version non supportata: %', v_schema;
  end if;

  if not exists (select 1 from public.franchises where id = p_franchise_id) then
    raise exception 'Franchise non trovato';
  end if;

  if nullif(p_payload #>> '{franchise,id}', '') is not null then
    v_payload_franchise := (p_payload #>> '{franchise,id}')::uuid;
    if v_payload_franchise <> p_franchise_id then
      raise exception 'Il JSON appartiene a un altro franchise';
    end if;
  end if;

  if jsonb_typeof(coalesce(p_payload -> 'games', '[]'::jsonb)) <> 'array' then
    raise exception 'games deve essere un array';
  end if;
  if jsonb_typeof(coalesce(p_payload -> 'tracks', '[]'::jsonb)) <> 'array' then
    raise exception 'tracks deve essere un array';
  end if;
  if jsonb_typeof(coalesce(p_payload -> 'relations', '[]'::jsonb)) <> 'array' then
    raise exception 'relations deve essere un array';
  end if;

  v_games := jsonb_array_length(coalesce(p_payload -> 'games', '[]'::jsonb));
  v_tracks := jsonb_array_length(coalesce(p_payload -> 'tracks', '[]'::jsonb));
  v_relations := jsonb_array_length(coalesce(p_payload -> 'relations', '[]'::jsonb));

  select coalesce(sum(jsonb_array_length(coalesce(game.value -> 'track_memberships', '[]'::jsonb))), 0)::integer
  into v_memberships
  from jsonb_array_elements(coalesce(p_payload -> 'games', '[]'::jsonb)) game(value);

  -- Validate game keys, duplicates, membership in the franchise and entry types.
  with parsed as materialized (
    select
      trim(coalesce(game.value ->> 'game_key', game.value ->> 'match_key', '')) as game_key,
      coalesce(
        nullif(game.value #>> '{editorial,entry_type}', ''),
        nullif(game.value ->> 'relation_type', '')
      ) as entry_type
    from jsonb_array_elements(coalesce(p_payload -> 'games', '[]'::jsonb)) game(value)
  )
  select string_agg(coalesce(parsed.game_key, '<vuoto>'), ', ' order by coalesce(parsed.game_key, ''))
  into v_invalid
  from parsed
  left join public.franchise_games fg
    on fg.franchise_id = p_franchise_id
   and fg.game_key = parsed.game_key
  where parsed.game_key = ''
     or fg.game_key is null
     or (parsed.entry_type is not null and parsed.entry_type not in (
       'main', 'spin_off', 'remake', 'remaster', 'dlc', 'expansion', 'other'
     ));

  if v_invalid is not null then
    raise exception 'Giochi non validi o esterni al franchise: %', v_invalid;
  end if;

  with parsed as materialized (
    select trim(coalesce(game.value ->> 'game_key', game.value ->> 'match_key', '')) as game_key
    from jsonb_array_elements(coalesce(p_payload -> 'games', '[]'::jsonb)) game(value)
  )
  select string_agg(game_key, ', ' order by game_key)
  into v_invalid
  from parsed
  group by game_key
  having count(*) > 1
  limit 1;

  if v_invalid is not null then
    raise exception 'game_key duplicato nel JSON: %', v_invalid;
  end if;

  -- Validate tracks and parent references without row-by-row lookups.
  with parsed as materialized (
    select
      trim(coalesce(track.value ->> 'track_key', '')) as track_key,
      trim(coalesce(track.value ->> 'parent_track_key', '')) as parent_track_key,
      coalesce(nullif(track.value ->> 'track_type', ''), 'continuity') as track_type
    from jsonb_array_elements(coalesce(p_payload -> 'tracks', '[]'::jsonb)) track(value)
  )
  select string_agg(coalesce(track_key, '<vuoto>'), ', ' order by coalesce(track_key, ''))
  into v_invalid
  from parsed
  where track_key = ''
     or track_key !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'
     or track_type not in (
       'continuity', 'timeline', 'subseries', 'story_arc',
       'anthology', 'remake_line', 'collection', 'other'
     );

  if v_invalid is not null then
    raise exception 'Percorsi editoriali non validi: %', v_invalid;
  end if;

  with parsed as materialized (
    select
      trim(coalesce(track.value ->> 'track_key', '')) as track_key,
      trim(coalesce(track.value ->> 'parent_track_key', '')) as parent_track_key
    from jsonb_array_elements(coalesce(p_payload -> 'tracks', '[]'::jsonb)) track(value)
  )
  select string_agg(child.parent_track_key, ', ' order by child.parent_track_key)
  into v_invalid
  from parsed child
  left join parsed parent on parent.track_key = child.parent_track_key
  where child.parent_track_key <> ''
    and (parent.track_key is null or child.parent_track_key = child.track_key);

  if v_invalid is not null then
    raise exception 'parent_track_key non trovato o circolare: %', v_invalid;
  end if;

  with parsed as materialized (
    select trim(coalesce(track.value ->> 'track_key', '')) as track_key
    from jsonb_array_elements(coalesce(p_payload -> 'tracks', '[]'::jsonb)) track(value)
  )
  select string_agg(track_key, ', ' order by track_key)
  into v_invalid
  from parsed
  group by track_key
  having count(*) > 1
  limit 1;

  if v_invalid is not null then
    raise exception 'track_key duplicato nel JSON: %', v_invalid;
  end if;

  -- Validate memberships. The global editorial canon_status is the fallback
  -- when ChatGPT omits canon_status from a specific track membership.
  with track_keys as materialized (
    select trim(coalesce(track.value ->> 'track_key', '')) as track_key
    from jsonb_array_elements(coalesce(p_payload -> 'tracks', '[]'::jsonb)) track(value)
  ), memberships as materialized (
    select
      trim(coalesce(game.value ->> 'game_key', game.value ->> 'match_key', '')) as game_key,
      trim(coalesce(membership.value ->> 'track_key', '')) as track_key,
      coalesce(
        nullif(membership.value ->> 'canon_status', ''),
        nullif(game.value #>> '{editorial,canon_status}', ''),
        'unknown'
      ) as canon_status
    from jsonb_array_elements(coalesce(p_payload -> 'games', '[]'::jsonb)) game(value)
    cross join lateral jsonb_array_elements(coalesce(game.value -> 'track_memberships', '[]'::jsonb)) membership(value)
  )
  select string_agg(memberships.game_key || ':' || coalesce(memberships.track_key, '<vuoto>'), ', ' order by memberships.game_key, memberships.track_key)
  into v_invalid
  from memberships
  left join track_keys on track_keys.track_key = memberships.track_key
  where memberships.track_key = ''
     or track_keys.track_key is null
     or memberships.canon_status not in (
       'canon', 'alternate_canon', 'reimagining',
       'non_canon', 'unknown', 'editorial_only'
     );

  if v_invalid is not null then
    raise exception 'Membership editoriali non valide: %', v_invalid;
  end if;

  with memberships as materialized (
    select
      trim(coalesce(game.value ->> 'game_key', game.value ->> 'match_key', '')) as game_key,
      trim(coalesce(membership.value ->> 'track_key', '')) as track_key
    from jsonb_array_elements(coalesce(p_payload -> 'games', '[]'::jsonb)) game(value)
    cross join lateral jsonb_array_elements(coalesce(game.value -> 'track_memberships', '[]'::jsonb)) membership(value)
  )
  select string_agg(game_key || ':' || track_key, ', ' order by game_key, track_key)
  into v_invalid
  from memberships
  group by game_key, track_key
  having count(*) > 1
  limit 1;

  if v_invalid is not null then
    raise exception 'Membership duplicata nel JSON: %', v_invalid;
  end if;

  -- Validate relations in one indexed pass.
  with relations as materialized (
    select
      trim(coalesce(relation.value ->> 'source_game_key', '')) as source_game_key,
      trim(coalesce(relation.value ->> 'target_game_key', '')) as target_game_key,
      trim(coalesce(relation.value ->> 'relation_type', '')) as relation_type
    from jsonb_array_elements(coalesce(p_payload -> 'relations', '[]'::jsonb)) relation(value)
  )
  select string_agg(
    coalesce(source_game_key, '<vuoto>') || '→' || coalesce(target_game_key, '<vuoto>'),
    ', ' order by source_game_key, target_game_key
  )
  into v_invalid
  from relations
  left join public.franchise_games source_game
    on source_game.franchise_id = p_franchise_id
   and source_game.game_key = relations.source_game_key
  left join public.franchise_games target_game
    on target_game.franchise_id = p_franchise_id
   and target_game.game_key = relations.target_game_key
  where relations.source_game_key = ''
     or relations.target_game_key = ''
     or relations.source_game_key = relations.target_game_key
     or source_game.game_key is null
     or target_game.game_key is null
     or relations.relation_type not in (
       'sequel_to', 'prequel_to', 'remake_of', 'remaster_of',
       'reimagines', 'alternate_version_of', 'parallel_to',
       'expansion_of', 'collection_of', 'contains',
       'spiritual_successor_to', 'related_to'
     );

  if v_invalid is not null then
    raise exception 'Relazioni editoriali non valide: %', v_invalid;
  end if;

  if not p_dry_run then
    -- Replacing tracks cascades the previous memberships. All writes below are
    -- set-based and remain part of the same transaction.
    delete from public.franchise_game_relations
    where franchise_id = p_franchise_id;

    delete from public.franchise_tracks
    where franchise_id = p_franchise_id;

    insert into public.franchise_tracks(
      franchise_id, track_key, name, track_type,
      description, sort_order, is_primary
    )
    select
      p_franchise_id,
      trim(track.value ->> 'track_key'),
      left(trim(coalesce(track.value ->> 'name', track.value ->> 'track_key')), 160),
      coalesce(nullif(track.value ->> 'track_type', ''), 'continuity'),
      nullif(track.value ->> 'description', ''),
      greatest(1, coalesce(nullif(track.value ->> 'sort_order', '')::integer, 1)),
      coalesce(nullif(track.value ->> 'is_primary', '')::boolean, false)
    from jsonb_array_elements(coalesce(p_payload -> 'tracks', '[]'::jsonb)) track(value);

    with parsed as materialized (
      select
        trim(track.value ->> 'track_key') as track_key,
        trim(coalesce(track.value ->> 'parent_track_key', '')) as parent_track_key
      from jsonb_array_elements(coalesce(p_payload -> 'tracks', '[]'::jsonb)) track(value)
    )
    update public.franchise_tracks child
    set parent_id = parent.id,
        updated_at = now()
    from parsed
    join public.franchise_tracks parent
      on parent.franchise_id = p_franchise_id
     and parent.track_key = parsed.parent_track_key
    where child.franchise_id = p_franchise_id
      and child.track_key = parsed.track_key
      and parsed.parent_track_key <> '';

    with parsed as materialized (
      select
        trim(coalesce(game.value ->> 'game_key', game.value ->> 'match_key', '')) as game_key,
        coalesce(
          nullif(game.value #>> '{editorial,entry_type}', ''),
          nullif(game.value ->> 'relation_type', '')
        ) as entry_type,
        nullif(coalesce(
          game.value #>> '{editorial,release_order}',
          game.value ->> 'release_order',
          ''
        ), '')::integer as release_order,
        nullif(coalesce(
          game.value #>> '{editorial,narrative_order}',
          game.value ->> 'narrative_order',
          ''
        ), '')::integer as narrative_order,
        coalesce(
          nullif(game.value #>> '{editorial,notes}', ''),
          nullif(game.value #>> '{editorial,note}', ''),
          nullif(game.value ->> 'note', '')
        ) as note
      from jsonb_array_elements(coalesce(p_payload -> 'games', '[]'::jsonb)) game(value)
    )
    update public.franchise_games fg
    set relation_type = coalesce(parsed.entry_type, fg.relation_type),
        release_order = coalesce(parsed.release_order, fg.release_order),
        narrative_order = parsed.narrative_order,
        note = coalesce(parsed.note, fg.note),
        updated_at = now()
    from parsed
    where fg.franchise_id = p_franchise_id
      and fg.game_key = parsed.game_key;

    with memberships as materialized (
      select
        trim(coalesce(game.value ->> 'game_key', game.value ->> 'match_key', '')) as game_key,
        trim(membership.value ->> 'track_key') as track_key,
        nullif(membership.value ->> 'narrative_order', '')::integer as narrative_order,
        nullif(membership.value ->> 'release_order', '')::integer as release_order,
        coalesce(
          nullif(membership.value ->> 'canon_status', ''),
          nullif(game.value #>> '{editorial,canon_status}', ''),
          'unknown'
        ) as canon_status,
        nullif(membership.value ->> 'note', '') as note
      from jsonb_array_elements(coalesce(p_payload -> 'games', '[]'::jsonb)) game(value)
      cross join lateral jsonb_array_elements(coalesce(game.value -> 'track_memberships', '[]'::jsonb)) membership(value)
    )
    insert into public.franchise_game_tracks(
      track_id, franchise_id, game_key, game_id,
      narrative_order, release_order, canon_status, note
    )
    select
      track.id,
      p_franchise_id,
      memberships.game_key,
      fg.game_id,
      memberships.narrative_order,
      memberships.release_order,
      memberships.canon_status,
      memberships.note
    from memberships
    join public.franchise_tracks track
      on track.franchise_id = p_franchise_id
     and track.track_key = memberships.track_key
    join public.franchise_games fg
      on fg.franchise_id = p_franchise_id
     and fg.game_key = memberships.game_key
    on conflict (track_id, game_key) do update set
      game_id = excluded.game_id,
      narrative_order = excluded.narrative_order,
      release_order = excluded.release_order,
      canon_status = excluded.canon_status,
      note = excluded.note,
      updated_at = now();

    with relations as materialized (
      select
        trim(relation.value ->> 'source_game_key') as source_game_key,
        trim(relation.value ->> 'target_game_key') as target_game_key,
        trim(relation.value ->> 'relation_type') as relation_type,
        nullif(relation.value ->> 'note', '') as note
      from jsonb_array_elements(coalesce(p_payload -> 'relations', '[]'::jsonb)) relation(value)
    )
    insert into public.franchise_game_relations(
      franchise_id,
      source_game_key,
      target_game_key,
      source_game_id,
      target_game_id,
      relation_type,
      note
    )
    select
      p_franchise_id,
      relations.source_game_key,
      relations.target_game_key,
      source_game.game_id,
      target_game.game_id,
      relations.relation_type,
      relations.note
    from relations
    join public.franchise_games source_game
      on source_game.franchise_id = p_franchise_id
     and source_game.game_key = relations.source_game_key
    join public.franchise_games target_game
      on target_game.franchise_id = p_franchise_id
     and target_game.game_key = relations.target_game_key
    on conflict (franchise_id, source_game_key, target_game_key, relation_type) do update set
      source_game_id = excluded.source_game_id,
      target_game_id = excluded.target_game_id,
      note = excluded.note,
      updated_at = now();

    insert into public.admin_audit_log(actor_id, action, target_type, target_id, metadata)
    values (
      v_user,
      'franchise_editorial_json_imported',
      'franchise',
      p_franchise_id::text,
      jsonb_build_object(
        'games', v_games,
        'tracks', v_tracks,
        'track_memberships', v_memberships,
        'relations', v_relations,
        'write_strategy', 'set_based',
        'canonical_consolidation', 'not_required'
      )
    );
  end if;

  return jsonb_build_object(
    'status', case when p_dry_run then 'validated' else 'applied' end,
    'schema_version', v_schema,
    'counts', jsonb_build_object(
      'games', v_games,
      'tracks', v_tracks,
      'track_memberships', v_memberships,
      'relations', v_relations
    ),
    'write_strategy', 'set_based',
    'franchise', (
      select jsonb_build_object('id', id, 'slug', slug, 'name', name)
      from public.franchises
      where id = p_franchise_id
    )
  );
end;
$$;

revoke all on function public.admin_import_franchise_editorial(uuid, jsonb, boolean) from public;
grant execute on function public.admin_import_franchise_editorial(uuid, jsonb, boolean) to authenticated;

comment on function public.admin_import_franchise_editorial(uuid, jsonb, boolean) is
'Ludograph v5.3.8: set-based transactional franchise editorial JSON validation/import with compact acknowledgement.';

commit;

notify pgrst, 'reload schema';

-- Ludograph v5.3.9 — franchise page stability and lazy variant loading

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
    'tracks', coalesce((select public.franchise_tracks_json(f.id) from selected f), '[]'::jsonb),
    'relations', coalesce((select public.franchise_game_relations_json(f.id) from selected f), '[]'::jsonb),
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

create or replace function public.franchise_game_variants(p_slug text, p_game_key text)
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
  if v_slug = '' or v_key = '' then return null; end if;
  if not exists (
    select 1
    from public.franchises f
    join public.franchise_games fg on fg.franchise_id = f.id
    where f.slug = v_slug and f.status = 'published' and fg.game_key = v_key
  ) then return null; end if;
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
-- Ludograph v5.5.8 — Screenshot e video nelle schede gioco.
-- I media restano nel metadata Master IGDB e vengono esposti dal read model
-- senza duplicare file o introdurre una seconda copia del catalogo.

begin;

create or replace function public.catalog_game_card_json(p_game public.catalog_games)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
with master as (
  select coalesce(g.metadata, '{}'::jsonb) as metadata
  from public.games g
  where g.id = (p_game).master_game_id
  limit 1
), media as (
  select
    case when jsonb_typeof(metadata -> 'screenshots') = 'array'
      then metadata -> 'screenshots' else '[]'::jsonb end as screenshots,
    case when jsonb_typeof(metadata -> 'artworks') = 'array'
      then metadata -> 'artworks' else '[]'::jsonb end as artworks,
    case when jsonb_typeof(metadata -> 'videos') = 'array'
      then metadata -> 'videos' else '[]'::jsonb end as videos
  from master
), normalized_media as (
  select
    coalesce((select screenshots from media), '[]'::jsonb) as screenshots,
    coalesce((select artworks from media), '[]'::jsonb) as artworks,
    coalesce((select videos from media), '[]'::jsonb) as videos
)
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
  'hero_image_url', coalesce(
    normalized_media.artworks -> 0 ->> 'url',
    normalized_media.screenshots -> 0 ->> 'url'
  ),
  'screenshots', normalized_media.screenshots,
  'artworks', normalized_media.artworks,
  'videos', normalized_media.videos,
  'media_count', jsonb_array_length(normalized_media.screenshots)
    + jsonb_array_length(normalized_media.artworks)
    + jsonb_array_length(normalized_media.videos),
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
)
from normalized_media;
$$;

revoke all on function public.catalog_game_card_json(public.catalog_games) from public;

comment on function public.catalog_game_card_json(public.catalog_games) is
'Read model pubblico del gioco, inclusi screenshot, artwork e video importati da IGDB.';

commit;

notify pgrst, 'reload schema';

-- ---------------------------------------------------------------------------
-- Ludograph v5.5.12 — stabilità schede gioco e RPC catalogo
-- ---------------------------------------------------------------------------

create index if not exists catalog_games_store_listings_gin_idx
on public.catalog_games using gin (store_listings jsonb_path_ops);

create index if not exists catalog_games_canonical_id_idx
on public.catalog_games(canonical_id);

create index if not exists catalog_games_master_game_id_idx
on public.catalog_games(master_game_id);

create or replace function public.catalog_game_card_json(p_game public.catalog_games)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
with master as (
  select coalesce(g.metadata, '{}'::jsonb) as metadata
  from public.games g
  where g.id = (p_game).master_game_id
  limit 1
), raw_media as (
  select
    case when jsonb_typeof(metadata -> 'screenshots') = 'array'
      then metadata -> 'screenshots' else '[]'::jsonb end as raw_screenshots,
    case when jsonb_typeof(metadata -> 'artworks') = 'array'
      then metadata -> 'artworks' else '[]'::jsonb end as raw_artworks,
    case when jsonb_typeof(metadata -> 'videos') = 'array'
      then metadata -> 'videos' else '[]'::jsonb end as raw_videos
  from master
), normalized_media as (
  select
    coalesce((
      select jsonb_agg(value order by ord)
      from jsonb_array_elements(coalesce(raw_screenshots, '[]'::jsonb)) with ordinality as item(value, ord)
      where ord <= 24
    ), '[]'::jsonb) as screenshots,
    coalesce((
      select jsonb_agg(value order by ord)
      from jsonb_array_elements(coalesce(raw_artworks, '[]'::jsonb)) with ordinality as item(value, ord)
      where ord <= 12
    ), '[]'::jsonb) as artworks,
    coalesce((
      select jsonb_agg(value order by ord)
      from jsonb_array_elements(coalesce(raw_videos, '[]'::jsonb)) with ordinality as item(value, ord)
      where ord <= 8
    ), '[]'::jsonb) as videos,
    jsonb_array_length(coalesce(raw_screenshots, '[]'::jsonb))
      + jsonb_array_length(coalesce(raw_artworks, '[]'::jsonb))
      + jsonb_array_length(coalesce(raw_videos, '[]'::jsonb)) as full_media_count
  from raw_media
), media as (
  select
    coalesce((select screenshots from normalized_media), '[]'::jsonb) as screenshots,
    coalesce((select artworks from normalized_media), '[]'::jsonb) as artworks,
    coalesce((select videos from normalized_media), '[]'::jsonb) as videos,
    coalesce((select full_media_count from normalized_media), 0) as full_media_count
)
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
  'hero_image_url', coalesce(media.artworks -> 0 ->> 'url', media.screenshots -> 0 ->> 'url'),
  'screenshots', media.screenshots,
  'artworks', media.artworks,
  'videos', media.videos,
  'media_count', media.full_media_count,
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
)
from media;
$$;

revoke all on function public.catalog_game_card_json(public.catalog_games) from public;

create or replace function public.get_catalog_game(p_key text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
set statement_timeout = '8s'
as $$
declare
  v_key text := nullif(trim(p_key), '');
  v_master_game_id text;
  v_game public.catalog_games%rowtype;
begin
  if v_key is null then
    return null;
  end if;

  select * into v_game from public.catalog_games cg
  where cg.match_key = v_key
  order by case cg.source_kind when 'hybrid' then 0 when 'master' then 1 else 2 end
  limit 1;
  if found then return public.catalog_game_card_json(v_game); end if;

  select * into v_game from public.catalog_games cg
  where cg.canonical_id = v_key
  order by case cg.source_kind when 'hybrid' then 0 when 'master' then 1 else 2 end, cg.match_key
  limit 1;
  if found then return public.catalog_game_card_json(v_game); end if;

  v_master_game_id := public.resolve_master_game_id(v_key);
  if v_master_game_id is not null then
    select * into v_game from public.catalog_games cg
    where cg.master_game_id = v_master_game_id
    order by case cg.source_kind when 'hybrid' then 0 when 'master' then 1 else 2 end, cg.match_key
    limit 1;
    if found then return public.catalog_game_card_json(v_game); end if;
  end if;

  select * into v_game from public.catalog_games cg
  where cg.store_listings @> jsonb_build_array(jsonb_build_object('listing_id', v_key))
  order by case cg.source_kind when 'hybrid' then 0 when 'master' then 1 else 2 end, cg.match_key
  limit 1;
  if found then return public.catalog_game_card_json(v_game); end if;

  return null;
end;
$$;

create or replace function public.get_catalog_games(p_keys text[])
returns jsonb
language sql
stable
security definer
set search_path = ''
set statement_timeout = '10s'
as $$
with requested as (
  select min(ord) as ord, key as requested_key
  from unnest(coalesce(p_keys, '{}'::text[])) with ordinality as keys(key, ord)
  where nullif(trim(key), '') is not null
  group by key
), resolved as (
  select r.ord, public.get_catalog_game(r.requested_key) as item
  from requested r
)
select coalesce(jsonb_agg(item order by ord) filter (where item is not null), '[]'::jsonb)
from resolved;
$$;

revoke all on function public.get_catalog_game(text) from public;
revoke all on function public.get_catalog_games(text[]) from public;
grant execute on function public.get_catalog_game(text) to anon, authenticated;
grant execute on function public.get_catalog_games(text[]) to anon, authenticated;

comment on function public.get_catalog_game(text) is
'Ludograph v5.5.12: lookup scheda gioco per passi indicizzati; evita OR ampi e jsonb_array_elements su tutto catalog_games.';
-- Ludograph v5.5.13 — pagine gioco canoniche per duplicati tecnici.
--
-- v5.5.12 stabilizza get_catalog_game. Questa migrazione aggiunge un
-- ulteriore passaggio: chiavi diverse che rappresentano la stessa opera
-- editoriale tecnica (stesso titolo normalizzato, stesso autore/publisher e
-- anno vicino) devono risolvere alla stessa scheda canonica, evitando due URL
-- e due pagine separate per casi come Red Dead Redemption 2 IGDB vs Steam/Epic.

begin;

create index if not exists catalog_games_normalized_title_idx
on public.catalog_games (public.catalog_normalized_title(title));

create index if not exists catalog_games_release_year_idx
on public.catalog_games(release_year desc);

create or replace function public.catalog_canonical_detail_match_key(p_key text)
returns text
language plpgsql
stable
security definer
set search_path = ''
set statement_timeout = '6s'
as $$
declare
  v_key text := nullif(trim(p_key), '');
  v_seed public.catalog_games%rowtype;
  v_master_game_id text;
  v_seed_game_type text := 'unknown';
  v_title_key text;
  v_maker_key text;
  v_year integer;
  v_cover_key text;
  v_result text;
begin
  if v_key is null then
    return null;
  end if;

  select * into v_seed
  from public.catalog_games cg
  where cg.match_key = v_key
  order by case cg.source_kind when 'hybrid' then 0 when 'catalog' then 1 when 'master' then 2 else 3 end,
    cg.match_key
  limit 1;

  if not found then
    select * into v_seed
    from public.catalog_games cg
    where cg.canonical_id = v_key
    order by case cg.source_kind when 'hybrid' then 0 when 'catalog' then 1 when 'master' then 2 else 3 end,
      cg.match_key
    limit 1;
  end if;

  if not found then
    v_master_game_id := public.resolve_master_game_id(v_key);
    if v_master_game_id is not null then
      select * into v_seed
      from public.catalog_games cg
      where cg.master_game_id = v_master_game_id
      order by case cg.source_kind when 'hybrid' then 0 when 'catalog' then 1 when 'master' then 2 else 3 end,
        cg.match_key
      limit 1;
    end if;
  end if;

  if not found then
    select * into v_seed
    from public.catalog_games cg
    where cg.store_listings @> jsonb_build_array(jsonb_build_object('listing_id', v_key))
    order by case cg.source_kind when 'hybrid' then 0 when 'catalog' then 1 when 'master' then 2 else 3 end,
      cg.match_key
    limit 1;
  end if;

  if not found then
    return null;
  end if;

  select coalesce(g.game_type, 'unknown') into v_seed_game_type
  from public.games g
  where g.id = v_seed.master_game_id
  limit 1;
  v_seed_game_type := coalesce(v_seed_game_type, 'unknown');

  -- Remake, remaster, bundle, DLC e collection non vanno fusi con la base.
  if public.catalog_is_separate_game_type(v_seed_game_type) then
    return v_seed.match_key;
  end if;

  v_title_key := public.catalog_normalized_title(v_seed.title);
  v_maker_key := public.catalog_normalized_title(coalesce(nullif(v_seed.developer, ''), nullif(v_seed.publisher, ''), ''));
  v_year := coalesce(v_seed.release_year, extract(year from v_seed.release_date)::integer);
  v_cover_key := public.catalog_cover_identity(v_seed.image_url);

  if v_title_key = '' then
    return v_seed.match_key;
  end if;

  with candidates as materialized (
    select
      cg.match_key,
      cg.source_kind,
      cg.release_year,
      cg.release_date,
      cg.master_game_id,
      cg.description,
      cg.image_url,
      cg.stores,
      cg.store_listings,
      coalesce(g.game_type, 'unknown') as game_type,
      public.catalog_normalized_title(coalesce(nullif(cg.developer, ''), nullif(cg.publisher, ''), '')) as maker_key,
      public.catalog_cover_identity(cg.image_url) as cover_key
    from public.catalog_games cg
    left join public.games g on g.id = cg.master_game_id
    where public.catalog_normalized_title(cg.title) = v_title_key
      and not public.catalog_is_separate_game_type(coalesce(g.game_type, 'unknown'))
  ), filtered as (
    select c.*
    from candidates c
    where (
        v_year is null
        or coalesce(c.release_year, extract(year from c.release_date)::integer) is null
        or abs(coalesce(c.release_year, extract(year from c.release_date)::integer) - v_year) <= 2
        or (v_seed.master_game_id is not null and c.master_game_id = v_seed.master_game_id)
      )
      and (
        v_maker_key = ''
        or c.maker_key = ''
        or c.maker_key = v_maker_key
        or (v_seed.master_game_id is not null and c.master_game_id = v_seed.master_game_id)
        or (v_cover_key is not null and c.cover_key = v_cover_key)
      )
  )
  select f.match_key into v_result
  from filtered f
  order by
    case f.source_kind when 'hybrid' then 0 when 'catalog' then 1 when 'master' then 2 else 3 end,
    greatest(cardinality(coalesce(f.stores, '{}'::text[])), jsonb_array_length(coalesce(f.store_listings, '[]'::jsonb))) desc,
    case when nullif(f.description, '') is not null then 0 else 1 end,
    case when nullif(f.image_url, '') is not null then 0 else 1 end,
    coalesce(f.release_year, extract(year from f.release_date)::integer) asc nulls last,
    f.match_key
  limit 1;

  return coalesce(v_result, v_seed.match_key);
end;
$$;

revoke all on function public.catalog_canonical_detail_match_key(text) from public;
grant execute on function public.catalog_canonical_detail_match_key(text) to anon, authenticated, service_role;

create or replace function public.get_catalog_game(p_key text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
set statement_timeout = '8s'
as $$
declare
  v_key text := nullif(trim(p_key), '');
  v_match_key text;
  v_master_game_id text;
  v_game public.catalog_games%rowtype;
begin
  if v_key is null then
    return null;
  end if;

  v_match_key := public.catalog_canonical_detail_match_key(v_key);
  if v_match_key is not null then
    select * into v_game
    from public.catalog_games cg
    where cg.match_key = v_match_key
    limit 1;
    if found then
      return public.catalog_game_card_json(v_game)
        || jsonb_build_object(
          'requested_key', v_key,
          'canonical_route_key', v_game.match_key
        );
    end if;
  end if;

  -- Fallback difensivo: conserva il lookup indicizzato di v5.5.12 se il
  -- risolutore canonico non trova nulla.
  select * into v_game
  from public.catalog_games cg
  where cg.match_key = v_key
  order by case cg.source_kind when 'hybrid' then 0 when 'master' then 1 else 2 end
  limit 1;
  if found then
    return public.catalog_game_card_json(v_game)
      || jsonb_build_object('requested_key', v_key, 'canonical_route_key', v_game.match_key);
  end if;

  select * into v_game
  from public.catalog_games cg
  where cg.canonical_id = v_key
  order by case cg.source_kind when 'hybrid' then 0 when 'master' then 1 else 2 end, cg.match_key
  limit 1;
  if found then
    return public.catalog_game_card_json(v_game)
      || jsonb_build_object('requested_key', v_key, 'canonical_route_key', v_game.match_key);
  end if;

  v_master_game_id := public.resolve_master_game_id(v_key);
  if v_master_game_id is not null then
    select * into v_game
    from public.catalog_games cg
    where cg.master_game_id = v_master_game_id
    order by case cg.source_kind when 'hybrid' then 0 when 'master' then 1 else 2 end, cg.match_key
    limit 1;
    if found then
      return public.catalog_game_card_json(v_game)
        || jsonb_build_object('requested_key', v_key, 'canonical_route_key', v_game.match_key);
    end if;
  end if;

  select * into v_game
  from public.catalog_games cg
  where cg.store_listings @> jsonb_build_array(jsonb_build_object('listing_id', v_key))
  order by case cg.source_kind when 'hybrid' then 0 when 'master' then 1 else 2 end, cg.match_key
  limit 1;
  if found then
    return public.catalog_game_card_json(v_game)
      || jsonb_build_object('requested_key', v_key, 'canonical_route_key', v_game.match_key);
  end if;

  return null;
end;
$$;

revoke all on function public.get_catalog_game(text) from public;
grant execute on function public.get_catalog_game(text) to anon, authenticated;

comment on function public.catalog_canonical_detail_match_key(text) is
'Ludograph v5.5.13: risolve duplicati tecnici del catalogo verso una sola scheda gioco canonica.';

comment on function public.get_catalog_game(text) is
'Ludograph v5.5.13: lookup scheda gioco stabile più canonicalizzazione dei duplicati tecnici.';

commit;

notify pgrst, 'reload schema';
-- Ludograph v5.5.15 — selezione canonica nell'editor franchise.
--
-- L'editor amministrativo dei franchise non deve selezionare record catalogo
-- grezzi: PC, Saturn, Steam/Epic e varianti tecniche della stessa opera devono
-- essere mostrati come una sola opera canonica, con le varianti espandibili.
-- La v5.5.15 mantiene la ricerca bounded candidate-first ma aggiunge un livello
-- di raggruppamento title+anno vicino per i casi senza parent IGDB esplicito.

begin;


-- Helper difensivi: rendono la migrazione applicabile anche se la v5.5.14
-- non è stata ancora eseguita sul database locale.
create or replace function public.catalog_detail_media_count(p_master_game_id text)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    case when jsonb_typeof(coalesce(g.metadata, '{}'::jsonb) -> 'screenshots') = 'array'
      then jsonb_array_length(coalesce(g.metadata, '{}'::jsonb) -> 'screenshots') else 0 end,
    0
  )
  + coalesce(
    case when jsonb_typeof(coalesce(g.metadata, '{}'::jsonb) -> 'artworks') = 'array'
      then jsonb_array_length(coalesce(g.metadata, '{}'::jsonb) -> 'artworks') else 0 end,
    0
  )
  + coalesce(
    case when jsonb_typeof(coalesce(g.metadata, '{}'::jsonb) -> 'videos') = 'array'
      then jsonb_array_length(coalesce(g.metadata, '{}'::jsonb) -> 'videos') else 0 end,
    0
  )
  from public.games g
  where g.id = nullif(p_master_game_id, '')
  limit 1;
$$;

create or replace function public.catalog_review_anchor_count(p_match_key text, p_canonical_id text, p_master_game_id text)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select count(*)::integer
  from public.game_reviews gr
  where gr.game_key in (nullif(p_match_key, ''), nullif(p_canonical_id, ''))
     or (nullif(p_master_game_id, '') is not null and gr.game_id = p_master_game_id);
$$;

create or replace function public.catalog_library_anchor_count(p_match_key text, p_canonical_id text, p_master_game_id text)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select count(*)::integer
  from public.user_library ul
  where ul.game_key in (nullif(p_match_key, ''), nullif(p_canonical_id, ''))
     or (nullif(p_master_game_id, '') is not null and ul.game_id = p_master_game_id);
$$;

grant execute on function public.catalog_detail_media_count(text) to anon, authenticated, service_role;
grant execute on function public.catalog_review_anchor_count(text, text, text) to anon, authenticated, service_role;
grant execute on function public.catalog_library_anchor_count(text, text, text) to anon, authenticated, service_role;

create or replace function public.admin_search_franchise_candidates(
  p_query text,
  p_limit integer default 50
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
set statement_timeout = '12s'
as $$
declare
  v_q text := lower(trim(coalesce(p_query, '')));
  v_group_limit integer := greatest(1, least(coalesce(p_limit, 50), 50));
  v_candidate_limit integer;
  v_candidate_keys text[] := '{}'::text[];
  v_result jsonb;
begin
  if not public.is_admin() then
    raise exception 'Accesso amministratore richiesto' using errcode = '42501';
  end if;

  if v_q = '' then
    return '[]'::jsonb;
  end if;

  v_candidate_limit := least(1500, greatest(300, v_group_limit * 24));

  select coalesce(
    array_agg(
      limited.match_key
      order by limited.relevance_score desc,
        limited.sort_title,
        limited.release_date asc nulls last,
        limited.match_key
    ),
    '{}'::text[]
  )
  into v_candidate_keys
  from (
    select
      deduped.match_key,
      deduped.relevance_score,
      deduped.sort_title,
      deduped.release_date
    from (
      select
        raw.match_key,
        max(raw.relevance_score)::real as relevance_score,
        min(raw.sort_title) as sort_title,
        min(raw.release_date) as release_date
      from (
        select
          cg.match_key,
          case
            when lower(cg.title) = v_q then 100::real
            when lower(cg.title) like v_q || '%' then 90::real
            else 72::real
          end as relevance_score,
          lower(cg.title) as sort_title,
          cg.release_date
        from public.catalog_games cg
        where lower(cg.title) like '%' || v_q || '%'

        union all

        select
          cg.match_key,
          case
            when lower(cg.canonical_title) = v_q then 98::real
            when lower(cg.canonical_title) like v_q || '%' then 88::real
            else 68::real
          end as relevance_score,
          lower(cg.title) as sort_title,
          cg.release_date
        from public.catalog_games cg
        where lower(cg.canonical_title) like '%' || v_q || '%'
      ) raw
      group by raw.match_key
    ) deduped
    order by deduped.relevance_score desc,
      deduped.sort_title,
      deduped.release_date asc nulls last,
      deduped.match_key
    limit v_candidate_limit
  ) limited;

  if cardinality(v_candidate_keys) = 0 and char_length(v_q) >= 4 then
    select coalesce(
      array_agg(
        limited.match_key
        order by limited.relevance_score desc,
          limited.sort_title,
          limited.release_date asc nulls last,
          limited.match_key
      ),
      '{}'::text[]
    )
    into v_candidate_keys
    from (
      select
        deduped.match_key,
        deduped.relevance_score,
        deduped.sort_title,
        deduped.release_date
      from (
        select
          raw.match_key,
          max(raw.relevance_score)::real as relevance_score,
          min(raw.sort_title) as sort_title,
          min(raw.release_date) as release_date
        from (
          select
            cg.match_key,
            (35 + extensions.similarity(lower(cg.title), v_q) * 25)::real as relevance_score,
            lower(cg.title) as sort_title,
            cg.release_date
          from public.catalog_games cg
          where lower(cg.title) operator(extensions.%) v_q

          union all

          select
            cg.match_key,
            (35 + extensions.similarity(lower(cg.canonical_title), v_q) * 25)::real as relevance_score,
            lower(cg.title) as sort_title,
            cg.release_date
          from public.catalog_games cg
          where lower(cg.canonical_title) operator(extensions.%) v_q
        ) raw
        group by raw.match_key
      ) deduped
      order by deduped.relevance_score desc,
        deduped.sort_title,
        deduped.release_date asc nulls last,
        deduped.match_key
      limit least(v_candidate_limit, 750)
    ) limited;
  end if;

  if cardinality(v_candidate_keys) = 0 then
    return '[]'::jsonb;
  end if;

  with candidate_keys as materialized (
    select keys.match_key, keys.relevance_rank
    from unnest(v_candidate_keys) with ordinality
      as keys(match_key, relevance_rank)
  ), candidate_data as materialized (
    select
      cg.match_key,
      cg.canonical_id,
      cg.master_game_id,
      cg.title,
      cg.canonical_title,
      cg.image_url,
      cg.release_date,
      coalesce(cg.release_year, extract(year from cg.release_date)::integer) as release_year_value,
      cg.platforms,
      cg.stores,
      cg.source_kind,
      cg.developer,
      cg.publisher,
      ck.relevance_rank,
      public.catalog_normalized_title(cg.title) as normalized_title,
      public.catalog_editorial_identity(cg.title, cg.image_url) as cover_identity,
      public.catalog_cover_identity(cg.image_url) as cover_key,
      public.catalog_normalized_title(coalesce(nullif(cg.developer, ''), nullif(cg.publisher, ''), '')) as maker_key,
      coalesce(g.game_type, 'unknown') as game_type,
      public.catalog_game_type_priority(g.game_type) as type_priority,
      case
        when nullif(g.metadata ->> 'parent_game', '') is not null then
          case
            when position(':' in (g.metadata ->> 'parent_game')) = 0
              then 'igdb:' || (g.metadata ->> 'parent_game')
            else g.metadata ->> 'parent_game'
          end
        when nullif(g.metadata ->> 'version_parent', '') is not null then
          case
            when position(':' in (g.metadata ->> 'version_parent')) = 0
              then 'igdb:' || (g.metadata ->> 'version_parent')
            else g.metadata ->> 'version_parent'
          end
        else null
      end as explicit_parent_id,
      (
        case when cg.release_date is not null then 1 else 0 end
        + case when nullif(cg.developer, '') is not null then 1 else 0 end
        + case when cardinality(cg.platforms) > 0 then 1 else 0 end
        + case when nullif(cg.description, '') is not null then 1 else 0 end
      ) as completeness_score,
      coalesce(public.catalog_detail_media_count(cg.master_game_id), 0) as media_count,
      public.catalog_review_anchor_count(cg.match_key, cg.canonical_id, cg.master_game_id) as review_count,
      public.catalog_library_anchor_count(cg.match_key, cg.canonical_id, cg.master_game_id) as library_count
    from candidate_keys ck
    join public.catalog_games cg on cg.match_key = ck.match_key
    left join public.games g on g.id = cg.master_game_id
  ), title_stats as materialized (
    select
      cd.normalized_title,
      count(*) filter (
        where not public.catalog_is_subordinate_game_type(cd.game_type)
          and not public.catalog_is_separate_game_type(cd.game_type)
      )::integer as primary_count,
      min(cd.master_game_id) filter (
        where cd.master_game_id is not null
          and not public.catalog_is_subordinate_game_type(cd.game_type)
          and not public.catalog_is_separate_game_type(cd.game_type)
      ) as primary_master_id,
      bool_or(public.catalog_is_subordinate_game_type(cd.game_type)) as has_subordinates
    from candidate_data cd
    where cd.normalized_title <> ''
    group by cd.normalized_title
  ), clustered as materialized (
    select
      cd.*,
      (
        select min(peer.release_year_value)::integer
        from candidate_data peer
        where peer.normalized_title = cd.normalized_title
          and peer.normalized_title <> ''
          and not public.catalog_is_separate_game_type(peer.game_type)
          and not public.catalog_is_separate_game_type(cd.game_type)
          and peer.release_year_value is not null
          and cd.release_year_value is not null
          and abs(peer.release_year_value - cd.release_year_value) <= 2
      ) as canonical_year_anchor
    from candidate_data cd
  ), keyed as materialized (
    select
      cd.*,
      case
        when cd.explicit_parent_id is not null
          then 'work:' || cd.explicit_parent_id
        when cd.master_game_id is not null
          and exists (
            select 1
            from clustered child
            where child.explicit_parent_id = cd.master_game_id
          )
          then 'work:' || cd.master_game_id
        when public.catalog_is_separate_game_type(cd.game_type)
          then coalesce(
            case when cd.cover_identity is not null then 'cover:' || cd.cover_identity end,
            'game:' || cd.match_key
          )
        -- v5.5.15: stesso titolo normalizzato + anno vicino = stessa opera
        -- canonica nell'editor franchise. Questo collassa port/piattaforme e
        -- duplicati IGDB/store senza cancellare le varianti catalogo.
        when cd.normalized_title <> ''
          and cd.canonical_year_anchor is not null
          and not public.catalog_is_separate_game_type(cd.game_type)
          then 'canonical:' || cd.normalized_title || ':' || cd.canonical_year_anchor::text
        when public.catalog_is_subordinate_game_type(cd.game_type)
          and ts.primary_count = 1
          and ts.primary_master_id is not null
          then 'work:' || ts.primary_master_id
        when not public.catalog_is_subordinate_game_type(cd.game_type)
          and not public.catalog_is_separate_game_type(cd.game_type)
          and ts.primary_count = 1
          and ts.has_subordinates
          and cd.master_game_id = ts.primary_master_id
          then 'work:' || ts.primary_master_id
        when cd.cover_identity is not null
          then 'cover:' || cd.cover_identity
        else 'game:' || cd.match_key
      end as group_key
    from clustered cd
    left join title_stats ts on ts.normalized_title = cd.normalized_title
  ), ranked as materialized (
    select
      k.*,
      row_number() over (
        partition by k.group_key
        order by
          k.review_count desc,
          k.library_count desc,
          k.media_count desc,
          k.type_priority,
          case k.source_kind when 'master' then 0 when 'hybrid' then 1 when 'catalog' then 2 else 3 end,
          k.completeness_score desc,
          k.release_date asc nulls last,
          k.relevance_rank,
          k.match_key
      ) as variant_rank
    from keyed k
  ), group_summary as materialized (
    select
      r.group_key,
      min(r.relevance_rank) as relevance_rank,
      max(r.match_key) filter (where r.variant_rank = 1) as representative_key,
      count(*)::integer as variant_count
    from ranked r
    group by r.group_key
    order by min(r.relevance_rank), r.group_key
    limit v_group_limit
  ), selected_variants as materialized (
    select r.*
    from ranked r
    join group_summary gs on gs.group_key = r.group_key
  )
  select coalesce(
    jsonb_agg(
      public.catalog_game_card_json(representative)
      || jsonb_build_object(
        'editorial_identity', gs.group_key,
        'editorial_work_key', gs.group_key,
        'canonical_route_key', representative.match_key,
        'variant_count', gs.variant_count,
        'variant_keys', coalesce((
          select jsonb_agg(sv.match_key order by sv.variant_rank)
          from selected_variants sv
          where sv.group_key = gs.group_key
        ), '[]'::jsonb),
        'variants', coalesce((
          select jsonb_agg(
            public.catalog_game_card_json(variant_game)
            || jsonb_build_object(
              'editorial_identity', gs.group_key,
              'editorial_work_key', gs.group_key,
              'canonical_route_key', representative.match_key,
              'variant_role', case
                when public.catalog_is_subordinate_game_type(sv.game_type)
                  then 'subordinate'
                when public.catalog_is_separate_game_type(sv.game_type)
                  then 'separate'
                else 'primary'
              end
            )
            order by sv.variant_rank
          )
          from selected_variants sv
          join public.catalog_games variant_game
            on variant_game.match_key = sv.match_key
          where sv.group_key = gs.group_key
        ), '[]'::jsonb),
        'platforms', to_jsonb(array(
          select distinct platform_name
          from selected_variants sv
          cross join lateral unnest(sv.platforms) as platform_name
          where sv.group_key = gs.group_key
          order by platform_name
        )),
        'stores', to_jsonb(array(
          select distinct store_name
          from selected_variants sv
          cross join lateral unnest(sv.stores) as store_name
          where sv.group_key = gs.group_key
          order by store_name
        ))
      )
      order by gs.relevance_rank, lower(representative.title), representative.match_key
    ),
    '[]'::jsonb
  )
  into v_result
  from group_summary gs
  join public.catalog_games representative
    on representative.match_key = gs.representative_key;

  return coalesce(v_result, '[]'::jsonb);
end;
$$;

revoke all on function public.admin_search_franchise_candidates(text, integer) from public;
grant execute on function public.admin_search_franchise_candidates(text, integer) to authenticated;

comment on function public.admin_search_franchise_candidates(text, integer) is
  'Ludograph v5.5.15: ricerca admin franchise su opere canoniche; collassa port, piattaforme e duplicati tecnici in varianti espandibili.';

commit;

notify pgrst, 'reload schema';
