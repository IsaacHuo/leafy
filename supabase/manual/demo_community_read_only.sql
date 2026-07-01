-- Demo community read-only guard.
-- Run this manually in Supabase SQL Editor after the existing community migrations.
-- The iOS demo mode uses profiles.edu_id = 'review-demo'.

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
grant usage on schema private to authenticated, service_role;

create or replace function public.is_demo_community_user()
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select auth.uid() is not null
    and exists (
      select 1
      from public.profiles
      where profiles.id = coalesce(public.current_profile_id(), auth.uid())
        and lower(btrim(profiles.edu_id)) = 'review-demo'
    );
$$;

create or replace function public.raise_if_demo_community_user()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.is_demo_community_user() then
    raise exception 'COMMUNITY_DEMO_READ_ONLY'
      using errcode = '42501';
  end if;
end;
$$;

comment on function public.is_demo_community_user() is
  'Returns true when the current authenticated community profile is the review demo profile.';

comment on function public.raise_if_demo_community_user() is
  'Raises COMMUNITY_DEMO_READ_ONLY for write paths attempted by the review demo profile.';

revoke all on function public.is_demo_community_user() from public, anon;
revoke all on function public.raise_if_demo_community_user() from public, anon;
grant execute on function public.is_demo_community_user() to authenticated, service_role;
grant execute on function public.raise_if_demo_community_user() to authenticated, service_role;

create or replace function private.ensure_demo_community_terms_acceptance()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if lower(btrim(coalesce(new.edu_id, ''))) = 'review-demo' then
    insert into public.community_terms_acceptances (user_id, terms_version, accepted_at, created_at)
    values (new.id, public.community_latest_terms_version(), now(), now())
    on conflict (user_id, terms_version)
    do update set accepted_at = excluded.accepted_at;
  end if;

  return new;
end;
$$;

comment on function private.ensure_demo_community_terms_acceptance() is
  'Keeps the review demo profile able to enter read-only community screens when the profile is created after this guard is installed.';

revoke all on function private.ensure_demo_community_terms_acceptance() from public, anon, authenticated;

drop trigger if exists profiles_ensure_demo_community_terms_acceptance on public.profiles;
create trigger profiles_ensure_demo_community_terms_acceptance
after insert or update of edu_id on public.profiles
for each row
execute function private.ensure_demo_community_terms_acceptance();

-- Keep existing demo profiles able to enter community read views before write guards are installed.
insert into public.community_terms_acceptances (user_id, terms_version, accepted_at, created_at)
select profiles.id, public.community_latest_terms_version(), now(), now()
from public.profiles
where lower(btrim(profiles.edu_id)) = 'review-demo'
on conflict (user_id, terms_version)
do update set accepted_at = excluded.accepted_at;

create or replace function private.guard_demo_community_write()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.raise_if_demo_community_user();

  if tg_op = 'DELETE' then
    return old;
  end if;

  return new;
end;
$$;

comment on function private.guard_demo_community_write() is
  'Shared trigger guard that blocks demo profile writes to community tables, including security definer RPC writes.';

revoke all on function private.guard_demo_community_write() from public, anon, authenticated;

-- Recreate write policies with the demo read-only guard. SELECT policies intentionally stay unchanged.

drop policy if exists "profiles_insert_self" on public.profiles;
create policy "profiles_insert_self"
on public.profiles
for insert
to authenticated
with check (
  not public.is_demo_community_user()
  and lower(btrim(coalesce(edu_id, ''))) <> 'review-demo'
  and auth.uid() = id
  and campus_id = coalesce(public.current_profile_campus_id(), campus_id)
);

drop policy if exists "profiles_update_self" on public.profiles;
create policy "profiles_update_self"
on public.profiles
for update
to authenticated
using (
  public.can_use_profile(id)
  and not public.is_demo_community_user()
)
with check (
  public.can_use_profile(id)
  and not public.is_demo_community_user()
  and lower(btrim(coalesce(edu_id, ''))) <> 'review-demo'
);

drop policy if exists "posts_insert_self" on public.posts;
create policy "posts_insert_self"
on public.posts
for insert
to authenticated
with check (
  not public.is_demo_community_user()
  and campus_id = public.current_profile_campus_id()
  and public.can_use_profile(author_id)
  and exists (
    select 1
    from public.profiles
    where profiles.id = posts.author_id
      and profiles.campus_id = posts.campus_id
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
  not public.is_demo_community_user()
  and campus_id = public.current_profile_campus_id()
  and public.can_use_profile(author_id)
)
with check (
  not public.is_demo_community_user()
  and campus_id = public.current_profile_campus_id()
  and public.can_use_profile(author_id)
  and status in ('published', 'pending_review', 'hidden', 'deleted')
);

drop policy if exists "comments_insert_self" on public.comments;
create policy "comments_insert_self"
on public.comments
for insert
to authenticated
with check (
  not public.is_demo_community_user()
  and public.can_use_profile(author_id)
  and exists (
    select 1
    from public.posts
    join public.profiles on profiles.id = comments.author_id
    where posts.id = comments.post_id
      and posts.campus_id = public.current_profile_campus_id()
      and posts.campus_id = profiles.campus_id
      and posts.status = 'published'
      and profiles.is_profile_complete = true
      and nullif(btrim(profiles.nickname), '') is not null
  )
);

drop policy if exists "comments_update_self" on public.comments;
create policy "comments_update_self"
on public.comments
for update
to authenticated
using (
  not public.is_demo_community_user()
  and public.can_use_profile(author_id)
)
with check (
  not public.is_demo_community_user()
  and public.can_use_profile(author_id)
);

drop policy if exists "post_images_insert_owner" on public.post_images;
create policy "post_images_insert_owner"
on public.post_images
for insert
to authenticated
with check (
  not public.is_demo_community_user()
  and exists (
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
  not public.is_demo_community_user()
  and exists (
    select 1
    from public.posts
    where posts.id = post_images.post_id
      and public.can_use_profile(posts.author_id)
  )
);

drop policy if exists "post_likes_insert_self" on public.post_likes;
create policy "post_likes_insert_self"
on public.post_likes
for insert
to authenticated
with check (
  not public.is_demo_community_user()
  and public.can_use_profile(user_id)
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
using (
  not public.is_demo_community_user()
  and public.can_use_profile(user_id)
);

drop policy if exists "post_favorites_insert_self" on public.post_favorites;
create policy "post_favorites_insert_self"
on public.post_favorites
for insert
to authenticated
with check (
  not public.is_demo_community_user()
  and public.can_use_profile(user_id)
  and exists (
    select 1
    from public.profiles
    where profiles.id = post_favorites.user_id
      and profiles.is_profile_complete = true
      and nullif(btrim(profiles.nickname), '') is not null
  )
  and exists (
    select 1
    from public.posts
    where posts.id = post_favorites.post_id
      and posts.status = 'published'
  )
);

drop policy if exists "post_favorites_delete_self" on public.post_favorites;
create policy "post_favorites_delete_self"
on public.post_favorites
for delete
to authenticated
using (
  not public.is_demo_community_user()
  and public.can_use_profile(user_id)
);

drop policy if exists "community_terms_acceptances_insert_self" on public.community_terms_acceptances;
create policy "community_terms_acceptances_insert_self"
on public.community_terms_acceptances
for insert
to authenticated
with check (
  not public.is_demo_community_user()
  and public.can_use_profile(user_id)
);

drop policy if exists "community_terms_acceptances_update_self" on public.community_terms_acceptances;
create policy "community_terms_acceptances_update_self"
on public.community_terms_acceptances
for update
to authenticated
using (
  not public.is_demo_community_user()
  and public.can_use_profile(user_id)
)
with check (
  not public.is_demo_community_user()
  and public.can_use_profile(user_id)
);

drop policy if exists "community_blocks_insert_self" on public.community_blocks;
create policy "community_blocks_insert_self"
on public.community_blocks
for insert
to authenticated
with check (
  not public.is_demo_community_user()
  and public.can_use_profile(blocker_id)
);

drop policy if exists "community_blocks_delete_self" on public.community_blocks;
create policy "community_blocks_delete_self"
on public.community_blocks
for delete
to authenticated
using (
  not public.is_demo_community_user()
  and public.can_use_profile(blocker_id)
);

drop policy if exists "community_reports_insert_self" on public.community_reports;
create policy "community_reports_insert_self"
on public.community_reports
for insert
to authenticated
with check (
  not public.is_demo_community_user()
  and public.can_use_profile(reporter_id)
);

drop policy if exists "community_notifications_insert_actor" on public.community_notifications;
create policy "community_notifications_insert_actor"
on public.community_notifications
for insert
to authenticated
with check (
  not public.is_demo_community_user()
  and public.can_use_profile(actor_id)
  and recipient_id <> actor_id
  and exists (
    select 1
    from public.posts
    where posts.id = community_notifications.post_id
      and posts.author_id = community_notifications.recipient_id
      and posts.status = 'published'
  )
);

drop policy if exists "community_notifications_update_recipient" on public.community_notifications;
create policy "community_notifications_update_recipient"
on public.community_notifications
for update
to authenticated
using (
  not public.is_demo_community_user()
  and public.can_use_profile(recipient_id)
)
with check (
  not public.is_demo_community_user()
  and public.can_use_profile(recipient_id)
);

drop policy if exists "community_notification_settings_insert_self" on public.community_notification_settings;
create policy "community_notification_settings_insert_self"
on public.community_notification_settings
for insert
to authenticated
with check (
  not public.is_demo_community_user()
  and public.can_use_profile(user_id)
);

drop policy if exists "community_notification_settings_update_self" on public.community_notification_settings;
create policy "community_notification_settings_update_self"
on public.community_notification_settings
for update
to authenticated
using (
  not public.is_demo_community_user()
  and public.can_use_profile(user_id)
)
with check (
  not public.is_demo_community_user()
  and public.can_use_profile(user_id)
);

drop policy if exists "community_polls_insert_self" on public.community_polls;
create policy "community_polls_insert_self"
on public.community_polls
for insert
to authenticated
with check (
  not public.is_demo_community_user()
  and campus_id = public.current_profile_campus_id()
  and public.can_use_profile(author_id)
);

drop policy if exists "community_polls_update_self" on public.community_polls;
create policy "community_polls_update_self"
on public.community_polls
for update
to authenticated
using (
  not public.is_demo_community_user()
  and campus_id = public.current_profile_campus_id()
  and public.can_use_profile(author_id)
)
with check (
  not public.is_demo_community_user()
  and campus_id = public.current_profile_campus_id()
  and public.can_use_profile(author_id)
);

drop policy if exists "community_poll_options_insert_owner" on public.community_poll_options;
create policy "community_poll_options_insert_owner"
on public.community_poll_options
for insert
to authenticated
with check (
  not public.is_demo_community_user()
  and exists (
    select 1
    from public.community_polls polls
    where polls.id = community_poll_options.poll_id
      and public.can_use_profile(polls.author_id)
  )
);

drop policy if exists "community_poll_votes_insert_self" on public.community_poll_votes;
create policy "community_poll_votes_insert_self"
on public.community_poll_votes
for insert
to authenticated
with check (
  not public.is_demo_community_user()
  and public.can_use_profile(user_id)
  and exists (
    select 1
    from public.community_polls polls
    join public.community_poll_options options on options.poll_id = polls.id
    where polls.id = community_poll_votes.poll_id
      and options.id = community_poll_votes.option_id
      and polls.status = 'published'
      and (polls.closes_at is null or polls.closes_at > now())
  )
);

drop policy if exists "community_poll_votes_update_self" on public.community_poll_votes;
create policy "community_poll_votes_update_self"
on public.community_poll_votes
for update
to authenticated
using (
  not public.is_demo_community_user()
  and public.can_use_profile(user_id)
)
with check (
  not public.is_demo_community_user()
  and public.can_use_profile(user_id)
);

-- Storage policies for the community-images bucket.

drop policy if exists "community_images_insert_own_namespace" on storage.objects;
create policy "community_images_insert_own_namespace"
on storage.objects
for insert
to authenticated
with check (
  not public.is_demo_community_user()
  and bucket_id = 'community-images'
  and (storage.foldername(name))[1] = 'posts'
  and public.can_use_profile_path((storage.foldername(name))[2])
);

drop policy if exists "community_images_delete_own_namespace" on storage.objects;
create policy "community_images_delete_own_namespace"
on storage.objects
for delete
to authenticated
using (
  not public.is_demo_community_user()
  and bucket_id = 'community-images'
  and (storage.foldername(name))[1] = 'posts'
  and public.can_use_profile_path((storage.foldername(name))[2])
);

drop policy if exists "community_images_insert_avatar_namespace" on storage.objects;
create policy "community_images_insert_avatar_namespace"
on storage.objects
for insert
to authenticated
with check (
  not public.is_demo_community_user()
  and bucket_id = 'community-images'
  and (storage.foldername(name))[1] = 'avatars'
  and public.can_use_profile_path((storage.foldername(name))[2])
);

drop policy if exists "community_images_delete_avatar_namespace" on storage.objects;
create policy "community_images_delete_avatar_namespace"
on storage.objects
for delete
to authenticated
using (
  not public.is_demo_community_user()
  and bucket_id = 'community-images'
  and (storage.foldername(name))[1] = 'avatars'
  and public.can_use_profile_path((storage.foldername(name))[2])
);

drop policy if exists "community_images_update_avatar_namespace" on storage.objects;
create policy "community_images_update_avatar_namespace"
on storage.objects
for update
to authenticated
using (
  not public.is_demo_community_user()
  and bucket_id = 'community-images'
  and (storage.foldername(name))[1] = 'avatars'
  and public.can_use_profile_path((storage.foldername(name))[2])
)
with check (
  not public.is_demo_community_user()
  and bucket_id = 'community-images'
  and (storage.foldername(name))[1] = 'avatars'
  and public.can_use_profile_path((storage.foldername(name))[2])
);

drop policy if exists "community_images_insert_profile_cover_namespace" on storage.objects;
create policy "community_images_insert_profile_cover_namespace"
on storage.objects
for insert
to authenticated
with check (
  not public.is_demo_community_user()
  and bucket_id = 'community-images'
  and (storage.foldername(name))[1] = 'profile-covers'
  and public.can_use_profile_path((storage.foldername(name))[2])
);

drop policy if exists "community_images_update_profile_cover_namespace" on storage.objects;
create policy "community_images_update_profile_cover_namespace"
on storage.objects
for update
to authenticated
using (
  not public.is_demo_community_user()
  and bucket_id = 'community-images'
  and (storage.foldername(name))[1] = 'profile-covers'
  and public.can_use_profile_path((storage.foldername(name))[2])
)
with check (
  not public.is_demo_community_user()
  and bucket_id = 'community-images'
  and (storage.foldername(name))[1] = 'profile-covers'
  and public.can_use_profile_path((storage.foldername(name))[2])
);

drop policy if exists "community_images_delete_profile_cover_namespace" on storage.objects;
create policy "community_images_delete_profile_cover_namespace"
on storage.objects
for delete
to authenticated
using (
  not public.is_demo_community_user()
  and bucket_id = 'community-images'
  and (storage.foldername(name))[1] = 'profile-covers'
  and public.can_use_profile_path((storage.foldername(name))[2])
);

-- Trigger guards catch security definer RPC writes that bypass table RLS.

do $$
declare
  guarded_table regclass;
  table_name text;
begin
  foreach table_name in array array[
    'public.profiles',
    'public.posts',
    'public.post_images',
    'public.comments',
    'public.post_likes',
    'public.post_favorites',
    'public.community_terms_acceptances',
    'public.community_blocks',
    'public.community_reports',
    'public.community_notifications',
    'public.community_notification_settings',
    'public.community_polls',
    'public.community_poll_options',
    'public.community_poll_votes'
  ] loop
    guarded_table := to_regclass(table_name);

    if guarded_table is not null then
      execute format('drop trigger if exists demo_community_read_only_guard on %s', guarded_table);
      execute format(
        'create trigger demo_community_read_only_guard before insert or update or delete on %s for each row execute function private.guard_demo_community_write()',
        guarded_table
      );
    else
      raise notice 'Skipping missing community table: %', table_name;
    end if;
  end loop;
end;
$$;

select pg_notify('pgrst', 'reload schema');

-- Optional verification snippets:
-- select public.is_demo_community_user(); -- meaningful only when executed with the demo user's JWT.
-- select id, edu_id from public.profiles where lower(btrim(edu_id)) = 'review-demo';
-- select user_id, terms_version from public.community_terms_acceptances
-- where user_id in (select id from public.profiles where lower(btrim(edu_id)) = 'review-demo');
