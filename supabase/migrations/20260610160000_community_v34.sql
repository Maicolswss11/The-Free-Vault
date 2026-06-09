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
