create extension if not exists pgcrypto;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade on update cascade,
  edu_id text not null unique,
  nickname text not null,
  display_name text,
  avatar_path text,
  bio text,
  is_profile_complete boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.posts (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references public.profiles (id) on delete cascade on update cascade,
  title text not null,
  body text not null,
  category text,
  is_anonymous boolean not null default false,
  comment_count integer not null default 0,
  status text not null default 'published' check (status in ('published', 'deleted')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.post_images (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts (id) on delete cascade on update cascade,
  path text not null,
  sort_order integer not null default 0,
  width integer,
  height integer,
  created_at timestamptz not null default now()
);

create table if not exists public.comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts (id) on delete cascade on update cascade,
  author_id uuid not null references public.profiles (id) on delete cascade on update cascade,
  body text not null,
  is_anonymous boolean not null default false,
  status text not null default 'published' check (status in ('published', 'deleted')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_profiles_edu_id on public.profiles (edu_id);
create index if not exists idx_posts_author_id on public.posts (author_id);
create index if not exists idx_posts_created_at on public.posts (created_at desc);
create index if not exists idx_post_images_post_id on public.post_images (post_id, sort_order);
create index if not exists idx_comments_post_id on public.comments (post_id, created_at asc);
create index if not exists idx_comments_author_id on public.comments (author_id);

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
before update on public.profiles
for each row
execute function public.set_updated_at();

drop trigger if exists posts_set_updated_at on public.posts;
create trigger posts_set_updated_at
before update on public.posts
for each row
execute function public.set_updated_at();

drop trigger if exists comments_set_updated_at on public.comments;
create trigger comments_set_updated_at
before update on public.comments
for each row
execute function public.set_updated_at();

create or replace function public.refresh_post_comment_count(target_post_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
  update public.posts
  set comment_count = (
    select count(*)
    from public.comments
    where post_id = target_post_id
      and status = 'published'
  )
  where id = target_post_id;
$$;

create or replace function public.handle_comment_count_sync()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    perform public.refresh_post_comment_count(old.post_id);
    return old;
  end if;

  if tg_op = 'UPDATE' and old.post_id <> new.post_id then
    perform public.refresh_post_comment_count(old.post_id);
  end if;

  perform public.refresh_post_comment_count(new.post_id);
  return new;
end;
$$;

drop trigger if exists comments_sync_post_count on public.comments;
create trigger comments_sync_post_count
after insert or update or delete on public.comments
for each row
execute function public.handle_comment_count_sync();

alter table public.profiles enable row level security;
alter table public.posts enable row level security;
alter table public.post_images enable row level security;
alter table public.comments enable row level security;

drop policy if exists "profiles_select_authenticated" on public.profiles;
create policy "profiles_select_authenticated"
on public.profiles
for select
to authenticated
using (true);

drop policy if exists "profiles_insert_self" on public.profiles;
create policy "profiles_insert_self"
on public.profiles
for insert
to authenticated
with check (auth.uid() = id);

drop policy if exists "profiles_update_self" on public.profiles;
create policy "profiles_update_self"
on public.profiles
for update
to authenticated
using (auth.uid() = id)
with check (auth.uid() = id);

drop policy if exists "posts_select_published" on public.posts;
create policy "posts_select_published"
on public.posts
for select
to authenticated
using (status = 'published');

drop policy if exists "posts_insert_self" on public.posts;
create policy "posts_insert_self"
on public.posts
for insert
to authenticated
with check (auth.uid() = author_id);

drop policy if exists "posts_update_self" on public.posts;
create policy "posts_update_self"
on public.posts
for update
to authenticated
using (auth.uid() = author_id)
with check (auth.uid() = author_id);

drop policy if exists "post_images_select_authenticated" on public.post_images;
create policy "post_images_select_authenticated"
on public.post_images
for select
to authenticated
using (true);

drop policy if exists "post_images_insert_owner" on public.post_images;
create policy "post_images_insert_owner"
on public.post_images
for insert
to authenticated
with check (
  exists (
    select 1
    from public.posts
    where posts.id = post_images.post_id
      and posts.author_id = auth.uid()
  )
);

drop policy if exists "post_images_delete_owner" on public.post_images;
create policy "post_images_delete_owner"
on public.post_images
for delete
to authenticated
using (
  exists (
    select 1
    from public.posts
    where posts.id = post_images.post_id
      and posts.author_id = auth.uid()
  )
);

drop policy if exists "comments_select_published" on public.comments;
create policy "comments_select_published"
on public.comments
for select
to authenticated
using (status = 'published');

drop policy if exists "comments_insert_self" on public.comments;
create policy "comments_insert_self"
on public.comments
for insert
to authenticated
with check (auth.uid() = author_id);

drop policy if exists "comments_update_self" on public.comments;
create policy "comments_update_self"
on public.comments
for update
to authenticated
using (auth.uid() = author_id)
with check (auth.uid() = author_id);

insert into storage.buckets (id, name, public)
values ('community-images', 'community-images', false)
on conflict (id) do nothing;

drop policy if exists "community_images_select_authenticated" on storage.objects;
create policy "community_images_select_authenticated"
on storage.objects
for select
to authenticated
using (bucket_id = 'community-images');

drop policy if exists "community_images_insert_own_namespace" on storage.objects;
create policy "community_images_insert_own_namespace"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'community-images'
  and (storage.foldername(name))[1] = 'posts'
  and (storage.foldername(name))[2] = auth.uid()::text
);

drop policy if exists "community_images_delete_own_namespace" on storage.objects;
create policy "community_images_delete_own_namespace"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'community-images'
  and (storage.foldername(name))[1] = 'posts'
  and (storage.foldername(name))[2] = auth.uid()::text
);
