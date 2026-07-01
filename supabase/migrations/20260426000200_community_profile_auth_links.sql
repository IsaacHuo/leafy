create table if not exists public.profile_auth_links (
  auth_user_id uuid primary key references auth.users (id) on delete cascade,
  profile_id uuid not null references public.profiles (id) on delete cascade on update cascade,
  edu_id text not null,
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  constraint profile_auth_links_edu_id_not_blank check (nullif(btrim(edu_id), '') is not null)
);

create index if not exists idx_profile_auth_links_profile_id
on public.profile_auth_links (profile_id);

create index if not exists idx_profile_auth_links_edu_id
on public.profile_auth_links (edu_id);

insert into public.profile_auth_links (auth_user_id, profile_id, edu_id)
select id, id, edu_id
from public.profiles
on conflict (auth_user_id) do update
set
  profile_id = excluded.profile_id,
  edu_id = excluded.edu_id,
  last_seen_at = now();

alter table public.profile_auth_links enable row level security;

drop policy if exists "profile_auth_links_select_self" on public.profile_auth_links;
create policy "profile_auth_links_select_self"
on public.profile_auth_links
for select
to authenticated
using (auth.uid() = auth_user_id);

create or replace function public.current_profile_id()
returns uuid
language sql
security definer
stable
set search_path = public
as $$
  select profile_id
  from public.profile_auth_links
  where auth_user_id = auth.uid()
  limit 1;
$$;

create or replace function public.can_use_profile(target_profile_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select target_profile_id is not null
    and exists (
      select 1
      from public.profile_auth_links
      where auth_user_id = auth.uid()
        and profile_id = target_profile_id
    );
$$;

create or replace function public.can_use_profile_path(target_profile_id text)
returns boolean
language plpgsql
security definer
stable
set search_path = public
as $$
declare
  parsed_profile_id uuid;
begin
  parsed_profile_id := target_profile_id::uuid;
  return public.can_use_profile(parsed_profile_id);
exception
  when invalid_text_representation then
    return false;
end;
$$;

grant execute on function public.current_profile_id() to authenticated;
grant execute on function public.can_use_profile(uuid) to authenticated;
grant execute on function public.can_use_profile_path(text) to authenticated;

drop policy if exists "profiles_update_self" on public.profiles;
create policy "profiles_update_self"
on public.profiles
for update
to authenticated
using (public.can_use_profile(id))
with check (public.can_use_profile(id));

create or replace function public.enforce_verified_bound_email()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  auth_email text;
  auth_email_confirmed_at timestamptz;
  target_auth_user_id uuid;
begin
  if new.bound_email is distinct from old.bound_email then
    target_auth_user_id := coalesce(auth.uid(), new.id);

    select email, email_confirmed_at
    into auth_email, auth_email_confirmed_at
    from auth.users
    where id = target_auth_user_id;

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

drop policy if exists "posts_insert_self" on public.posts;
create policy "posts_insert_self"
on public.posts
for insert
to authenticated
with check (
  public.can_use_profile(author_id)
  and exists (
    select 1
    from public.profiles
    where profiles.id = posts.author_id
      and profiles.is_profile_complete = true
      and nullif(btrim(profiles.nickname), '') is not null
  )
);

drop policy if exists "posts_update_self" on public.posts;
create policy "posts_update_self"
on public.posts
for update
to authenticated
using (
  public.can_use_profile(author_id)
  and status = 'published'
)
with check (
  public.can_use_profile(author_id)
  and status in ('published', 'deleted')
);

drop policy if exists "comments_insert_self" on public.comments;
create policy "comments_insert_self"
on public.comments
for insert
to authenticated
with check (
  public.can_use_profile(author_id)
  and exists (
    select 1
    from public.profiles
    where profiles.id = comments.author_id
      and profiles.is_profile_complete = true
      and nullif(btrim(profiles.nickname), '') is not null
  )
);

drop policy if exists "comments_update_self" on public.comments;
create policy "comments_update_self"
on public.comments
for update
to authenticated
using (public.can_use_profile(author_id))
with check (public.can_use_profile(author_id));

drop policy if exists "post_likes_insert_self" on public.post_likes;
create policy "post_likes_insert_self"
on public.post_likes
for insert
to authenticated
with check (
  public.can_use_profile(user_id)
  and exists (
    select 1
    from public.profiles
    where profiles.id = post_likes.user_id
      and profiles.is_profile_complete = true
      and nullif(btrim(profiles.nickname), '') is not null
  )
  and exists (
    select 1
    from public.posts
    where posts.id = post_likes.post_id
      and posts.status = 'published'
      and posts.author_id <> post_likes.user_id
  )
);

drop policy if exists "post_likes_delete_self" on public.post_likes;
create policy "post_likes_delete_self"
on public.post_likes
for delete
to authenticated
using (public.can_use_profile(user_id));

drop policy if exists "community_notifications_select_recipient" on public.community_notifications;
create policy "community_notifications_select_recipient"
on public.community_notifications
for select
to authenticated
using (public.can_use_profile(recipient_id));

drop policy if exists "community_notifications_update_recipient" on public.community_notifications;
create policy "community_notifications_update_recipient"
on public.community_notifications
for update
to authenticated
using (public.can_use_profile(recipient_id))
with check (public.can_use_profile(recipient_id));

drop policy if exists "community_notifications_insert_actor" on public.community_notifications;
create policy "community_notifications_insert_actor"
on public.community_notifications
for insert
to authenticated
with check (
  public.can_use_profile(actor_id)
  and recipient_id <> actor_id
  and exists (
    select 1
    from public.posts
    where posts.id = community_notifications.post_id
      and posts.author_id = community_notifications.recipient_id
      and posts.status = 'published'
  )
);

drop policy if exists "teacher_ratings_select_self" on public.teacher_ratings;
create policy "teacher_ratings_select_self"
on public.teacher_ratings
for select
to authenticated
using (public.can_use_profile(user_id));

drop policy if exists "teacher_ratings_insert_self" on public.teacher_ratings;
create policy "teacher_ratings_insert_self"
on public.teacher_ratings
for insert
to authenticated
with check (public.can_use_profile(user_id));

drop policy if exists "teacher_ratings_update_self" on public.teacher_ratings;
create policy "teacher_ratings_update_self"
on public.teacher_ratings
for update
to authenticated
using (public.can_use_profile(user_id))
with check (public.can_use_profile(user_id));

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
      and public.can_use_profile(posts.author_id)
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
      and public.can_use_profile(posts.author_id)
  )
);

drop policy if exists "community_images_insert_own_namespace" on storage.objects;
create policy "community_images_insert_own_namespace"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'community-images'
  and (storage.foldername(name))[1] = 'posts'
  and public.can_use_profile_path((storage.foldername(name))[2])
);

drop policy if exists "community_images_delete_own_namespace" on storage.objects;
create policy "community_images_delete_own_namespace"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'community-images'
  and (storage.foldername(name))[1] = 'posts'
  and public.can_use_profile_path((storage.foldername(name))[2])
);

drop policy if exists "community_images_insert_avatar_namespace" on storage.objects;
create policy "community_images_insert_avatar_namespace"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'community-images'
  and (storage.foldername(name))[1] = 'avatars'
  and public.can_use_profile_path((storage.foldername(name))[2])
);

drop policy if exists "community_images_delete_avatar_namespace" on storage.objects;
create policy "community_images_delete_avatar_namespace"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'community-images'
  and (storage.foldername(name))[1] = 'avatars'
  and public.can_use_profile_path((storage.foldername(name))[2])
);

drop policy if exists "community_images_update_avatar_namespace" on storage.objects;
create policy "community_images_update_avatar_namespace"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'community-images'
  and (storage.foldername(name))[1] = 'avatars'
  and public.can_use_profile_path((storage.foldername(name))[2])
)
with check (
  bucket_id = 'community-images'
  and (storage.foldername(name))[1] = 'avatars'
  and public.can_use_profile_path((storage.foldername(name))[2])
);

create or replace function public.soft_delete_own_post(target_post_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  affected_count integer;
begin
  if auth.uid() is null then
    raise exception 'missing authenticated user';
  end if;

  update public.posts
  set
    status = 'deleted',
    updated_at = now()
  where id = target_post_id
    and public.can_use_profile(author_id)
    and status = 'published';

  get diagnostics affected_count = row_count;

  if affected_count = 0 then
    if exists (
      select 1
      from public.posts
      where id = target_post_id
        and public.can_use_profile(author_id)
        and status = 'deleted'
    ) then
      return;
    end if;

    raise exception 'post not found or not owned by current user';
  end if;
end;
$$;

revoke all on function public.soft_delete_own_post(uuid) from public;
grant execute on function public.soft_delete_own_post(uuid) to authenticated;

select pg_notify('pgrst', 'reload schema');
