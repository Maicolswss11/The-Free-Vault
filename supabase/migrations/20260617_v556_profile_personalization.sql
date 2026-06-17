-- Ludograph v5.5.6 — profile hero personalization

alter table public.profiles
  add column if not exists hero_image_url text;

alter table public.profiles
  drop constraint if exists profiles_hero_image_url_length_check;

alter table public.profiles
  add constraint profiles_hero_image_url_length_check
  check (hero_image_url is null or char_length(hero_image_url) <= 2048);

-- The existing public avatars bucket also stores the user's optional profile hero
-- under <user-id>/hero-*. Avatar uploads remain limited to 2 MB in the client;
-- profile hero uploads are accepted up to 5 MB.
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

notify pgrst, 'reload schema';
