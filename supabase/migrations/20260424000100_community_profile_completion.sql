alter table public.profiles
  add column if not exists major text,
  add column if not exists grade text,
  add column if not exists bound_email text,
  add column if not exists pending_bound_email text,
  add column if not exists email_verification_sent_at timestamptz,
  add column if not exists profile_edited_at timestamptz;

create unique index if not exists profiles_bound_email_unique
on public.profiles (lower(bound_email))
where nullif(btrim(bound_email), '') is not null;

alter table public.profiles
  drop constraint if exists profiles_completed_nickname_required;

alter table public.profiles
  add constraint profiles_completed_nickname_required
  check (
    is_profile_complete = false
    or nullif(btrim(nickname), '') is not null
  )
  not valid;

drop trigger if exists profiles_enforce_profile_edit_lock on public.profiles;
drop function if exists public.enforce_profile_edit_lock();

create or replace function public.enforce_verified_bound_email()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  auth_email text;
  auth_email_confirmed_at timestamptz;
begin
  if new.bound_email is distinct from old.bound_email then
    select email, email_confirmed_at
    into auth_email, auth_email_confirmed_at
    from auth.users
    where id = new.id;

    if new.bound_email is not null
      and (
        auth_email_confirmed_at is null
        or lower(new.bound_email) <> lower(auth_email)
      )
    then
      raise exception 'EMAIL_NOT_VERIFIED';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists profiles_enforce_verified_bound_email on public.profiles;
create trigger profiles_enforce_verified_bound_email
before update on public.profiles
for each row
execute function public.enforce_verified_bound_email();

update public.profiles
set is_profile_complete = false
where coalesce(nickname, '') = ''
   or (
     nickname = coalesce(display_name, '')
     and coalesce(avatar_path, '') = ''
     and coalesce(major, '') = ''
     and coalesce(grade, '') = ''
   );

create table if not exists public.post_likes (
  post_id uuid not null references public.posts (id) on delete cascade on update cascade,
  user_id uuid not null references public.profiles (id) on delete cascade on update cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);

create index if not exists idx_post_likes_post_id on public.post_likes (post_id);
create index if not exists idx_post_likes_user_id on public.post_likes (user_id);

alter table public.post_likes enable row level security;

drop policy if exists "post_likes_select_authenticated" on public.post_likes;
create policy "post_likes_select_authenticated"
on public.post_likes
for select
to authenticated
using (true);

drop policy if exists "post_likes_insert_self" on public.post_likes;
create policy "post_likes_insert_self"
on public.post_likes
for insert
to authenticated
with check (
  auth.uid() = user_id
  and exists (
    select 1
    from public.profiles
    where profiles.id = auth.uid()
      and profiles.is_profile_complete = true
      and nullif(btrim(profiles.nickname), '') is not null
  )
);

drop policy if exists "posts_insert_self" on public.posts;
create policy "posts_insert_self"
on public.posts
for insert
to authenticated
with check (
  auth.uid() = author_id
  and exists (
    select 1
    from public.profiles
    where profiles.id = auth.uid()
      and profiles.is_profile_complete = true
      and nullif(btrim(profiles.nickname), '') is not null
  )
);

drop policy if exists "comments_insert_self" on public.comments;
create policy "comments_insert_self"
on public.comments
for insert
to authenticated
with check (
  auth.uid() = author_id
  and exists (
    select 1
    from public.profiles
    where profiles.id = auth.uid()
      and profiles.is_profile_complete = true
      and nullif(btrim(profiles.nickname), '') is not null
  )
);

drop policy if exists "post_likes_delete_self" on public.post_likes;
create policy "post_likes_delete_self"
on public.post_likes
for delete
to authenticated
using (auth.uid() = user_id);

drop policy if exists "community_images_insert_avatar_namespace" on storage.objects;
create policy "community_images_insert_avatar_namespace"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'community-images'
  and (storage.foldername(name))[1] = 'avatars'
  and (storage.foldername(name))[2] = auth.uid()::text
);

select pg_notify('pgrst', 'reload schema');

drop policy if exists "community_images_delete_avatar_namespace" on storage.objects;
create policy "community_images_delete_avatar_namespace"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'community-images'
  and (storage.foldername(name))[1] = 'avatars'
  and (storage.foldername(name))[2] = auth.uid()::text
);

drop policy if exists "community_images_update_avatar_namespace" on storage.objects;
create policy "community_images_update_avatar_namespace"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'community-images'
  and (storage.foldername(name))[1] = 'avatars'
  and (storage.foldername(name))[2] = auth.uid()::text
)
with check (
  bucket_id = 'community-images'
  and (storage.foldername(name))[1] = 'avatars'
  and (storage.foldername(name))[2] = auth.uid()::text
);
