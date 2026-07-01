create extension if not exists pgcrypto;

create or replace function public.normalize_school_name(value text)
returns text
language sql
immutable
set search_path = public
as $$
  select lower(regexp_replace(btrim(coalesce(value, '')), '\s+', '', 'g'));
$$;

alter table public.campuses
  add column if not exists normalized_name text,
  add column if not exists is_community_enabled boolean not null default true,
  add column if not exists is_system boolean not null default false;

update public.campuses
set normalized_name = public.normalize_school_name(display_name)
where normalized_name is null or nullif(btrim(normalized_name), '') is null;

alter table public.campuses
  alter column normalized_name set not null;

create unique index if not exists idx_campuses_normalized_name_unique
on public.campuses (normalized_name);

insert into public.campuses (
  id,
  display_name,
  short_name,
  connector_kind,
  status,
  normalized_name,
  is_community_enabled,
  is_system
)
values (
  'bjfu',
  '北京林业大学',
  '北林',
  'bjfu',
  'active',
  public.normalize_school_name('北京林业大学'),
  true,
  true
)
on conflict (id) do update
set
  display_name = excluded.display_name,
  short_name = excluded.short_name,
  connector_kind = excluded.connector_kind,
  status = excluded.status,
  normalized_name = excluded.normalized_name,
  is_community_enabled = excluded.is_community_enabled,
  is_system = excluded.is_system,
  updated_at = now();

insert into public.campuses (
  id,
  display_name,
  short_name,
  connector_kind,
  status,
  normalized_name,
  is_community_enabled,
  is_system
)
values (
  'general',
  '通用模式',
  '通用',
  'custom',
  'disabled',
  public.normalize_school_name('通用模式'),
  false,
  true
)
on conflict (id) do update
set
  display_name = excluded.display_name,
  short_name = excluded.short_name,
  connector_kind = excluded.connector_kind,
  status = excluded.status,
  normalized_name = excluded.normalized_name,
  is_community_enabled = excluded.is_community_enabled,
  is_system = excluded.is_system,
  updated_at = now();

alter table public.profiles
  add column if not exists community_campus_id text references public.campuses(id) on update cascade,
  add column if not exists community_access_status text not null default 'general',
  add column if not exists community_school_name text,
  add column if not exists community_rejection_reason text,
  add column if not exists community_request_id uuid;

alter table public.profiles
  drop constraint if exists profiles_community_access_status_check;

alter table public.profiles
  add constraint profiles_community_access_status_check
  check (community_access_status in ('general', 'pending', 'approved', 'rejected'));

update public.profiles
set
  campus_id = 'bjfu',
  community_campus_id = 'bjfu',
  community_access_status = 'approved',
  community_school_name = '北京林业大学',
  community_rejection_reason = null
where campus_id is distinct from 'general';

update public.profile_auth_links links
set campus_id = profiles.campus_id
from public.profiles profiles
where links.profile_id = profiles.id
  and links.campus_id is distinct from profiles.campus_id;

create table if not exists public.campus_membership_requests (
  id uuid primary key default gen_random_uuid(),
  requester_profile_id uuid not null references public.profiles(id) on delete cascade on update cascade,
  requester_auth_user_id uuid references auth.users(id) on delete set null on update cascade,
  school_name text not null,
  normalized_school_name text not null,
  status text not null default 'pending',
  approved_campus_id text references public.campuses(id) on update cascade,
  admin_note text,
  reviewed_by uuid,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint campus_membership_requests_school_name_not_blank check (nullif(btrim(school_name), '') is not null),
  constraint campus_membership_requests_status_check check (status in ('pending', 'approved', 'rejected'))
);

alter table public.campus_membership_requests
  drop constraint if exists campus_membership_requests_profile_status_shape;

alter table public.campus_membership_requests
  add constraint campus_membership_requests_profile_status_shape
  check (
    (status = 'approved' and approved_campus_id is not null)
    or (status <> 'approved' and approved_campus_id is null)
  );

drop trigger if exists campus_membership_requests_set_updated_at on public.campus_membership_requests;
create trigger campus_membership_requests_set_updated_at
before update on public.campus_membership_requests
for each row
execute function public.set_updated_at();

create index if not exists idx_campus_membership_requests_status_created
on public.campus_membership_requests (status, created_at desc);

create index if not exists idx_campus_membership_requests_requester
on public.campus_membership_requests (requester_profile_id, created_at desc);

create index if not exists idx_campus_membership_requests_normalized_status
on public.campus_membership_requests (normalized_school_name, status);

alter table public.campus_membership_requests enable row level security;

drop policy if exists "campus_membership_requests_select_self" on public.campus_membership_requests;
create policy "campus_membership_requests_select_self"
on public.campus_membership_requests
for select
to authenticated
using (public.can_use_profile(requester_profile_id));

drop policy if exists "campus_membership_requests_insert_self" on public.campus_membership_requests;
create policy "campus_membership_requests_insert_self"
on public.campus_membership_requests
for insert
to authenticated
with check (
  status = 'pending'
  and approved_campus_id is null
  and public.can_use_profile(requester_profile_id)
  and requester_auth_user_id = auth.uid()
);

create or replace function public.current_profile_campus_id()
returns text
language sql
security definer
stable
set search_path = public
as $$
  select case
    when profiles.campus_id = 'bjfu' then 'bjfu'
    else profiles.community_campus_id
  end
  from public.profile_auth_links links
  join public.profiles profiles on profiles.id = links.profile_id
  join public.campuses campuses
    on campuses.id = case
      when profiles.campus_id = 'bjfu' then 'bjfu'
      else profiles.community_campus_id
    end
  where links.auth_user_id = auth.uid()
    and (
      profiles.campus_id = 'bjfu'
      or (
        profiles.community_access_status = 'approved'
        and profiles.community_campus_id is not null
      )
    )
    and campuses.status = 'active'
    and campuses.is_community_enabled = true
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
      from public.profile_auth_links links
      where links.auth_user_id = auth.uid()
        and links.profile_id = target_profile_id
    );
$$;

create or replace function public.prevent_profile_community_self_escalation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if coalesce(current_setting('app.community_membership_action', true), '') <> 'true'
    and auth.uid() is not null
    and (
      new.campus_id is distinct from old.campus_id
      or new.community_campus_id is distinct from old.community_campus_id
      or new.community_access_status is distinct from old.community_access_status
      or new.community_school_name is distinct from old.community_school_name
      or new.community_rejection_reason is distinct from old.community_rejection_reason
      or new.community_request_id is distinct from old.community_request_id
    )
  then
    raise exception 'COMMUNITY_CAMPUS_MANAGED_BY_ADMIN'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

drop trigger if exists profiles_prevent_community_self_escalation on public.profiles;
create trigger profiles_prevent_community_self_escalation
before update on public.profiles
for each row
execute function public.prevent_profile_community_self_escalation();

revoke all on function public.current_profile_campus_id() from public, anon;
revoke all on function public.can_use_profile(uuid) from public, anon;
revoke all on function public.prevent_profile_community_self_escalation() from public, anon, authenticated;
grant execute on function public.current_profile_campus_id() to authenticated, service_role;
grant execute on function public.can_use_profile(uuid) to authenticated, service_role;

alter table public.profiles
  drop constraint if exists profiles_community_request_id_fkey;

alter table public.profiles
  add constraint profiles_community_request_id_fkey
  foreign key (community_request_id)
  references public.campus_membership_requests(id)
  on delete set null
  on update cascade;

drop policy if exists "profiles_select_authenticated" on public.profiles;
create policy "profiles_select_authenticated"
on public.profiles
for select
to authenticated
using (
  public.can_use_profile(id)
  or (
    community_access_status = 'approved'
    and community_campus_id = public.current_profile_campus_id()
  )
);

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
using (public.can_use_profile(id))
with check (public.can_use_profile(id));

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'posts',
    'community_polls',
    'community_post_pins',
    'catalog_suggestions',
    'timetable_snapshots',
    'timetable_invites',
    'timetable_share_members'
  ] loop
    if to_regclass('public.' || table_name) is not null then
      execute format('alter table public.%I alter column campus_id set default public.current_profile_campus_id()', table_name);
    end if;
  end loop;
end $$;

drop policy if exists "posts_select_published_or_self" on public.posts;
create policy "posts_select_published_or_self"
on public.posts
for select
to authenticated
using (
  campus_id = public.current_profile_campus_id()
  and (status = 'published' or public.can_use_profile(author_id))
);

drop policy if exists "posts_insert_self" on public.posts;
create policy "posts_insert_self"
on public.posts
for insert
to authenticated
with check (
  campus_id = public.current_profile_campus_id()
  and public.can_use_profile(author_id)
  and exists (
    select 1
    from public.profiles
    where profiles.id = posts.author_id
      and profiles.community_access_status = 'approved'
      and profiles.community_campus_id = posts.campus_id
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
  campus_id = public.current_profile_campus_id()
  and public.can_use_profile(author_id)
)
with check (
  campus_id = public.current_profile_campus_id()
  and public.can_use_profile(author_id)
  and status in ('published', 'pending_review', 'hidden', 'deleted')
);

drop policy if exists "comments_select_published_or_self" on public.comments;
create policy "comments_select_published_or_self"
on public.comments
for select
to authenticated
using (
  exists (
    select 1
    from public.posts
    where posts.id = comments.post_id
      and posts.campus_id = public.current_profile_campus_id()
      and posts.status = 'published'
      and (comments.status = 'published' or public.can_use_profile(comments.author_id))
  )
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
    from public.posts
    join public.profiles on profiles.id = comments.author_id
    where posts.id = comments.post_id
      and posts.campus_id = public.current_profile_campus_id()
      and posts.campus_id = profiles.community_campus_id
      and profiles.community_access_status = 'approved'
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
  public.can_use_profile(author_id)
  and exists (
    select 1
    from public.posts
    where posts.id = comments.post_id
      and posts.campus_id = public.current_profile_campus_id()
  )
)
with check (
  public.can_use_profile(author_id)
  and exists (
    select 1
    from public.posts
    where posts.id = comments.post_id
      and posts.campus_id = public.current_profile_campus_id()
  )
);

drop policy if exists "community_polls_select_published" on public.community_polls;
create policy "community_polls_select_published"
on public.community_polls
for select
to authenticated
using (
  campus_id = public.current_profile_campus_id()
  and status <> 'deleted'
);

drop policy if exists "community_polls_insert_self" on public.community_polls;
create policy "community_polls_insert_self"
on public.community_polls
for insert
to authenticated
with check (
  campus_id = public.current_profile_campus_id()
  and public.can_use_profile(author_id)
  and exists (
    select 1
    from public.profiles
    where profiles.id = community_polls.author_id
      and profiles.community_access_status = 'approved'
      and profiles.community_campus_id = community_polls.campus_id
      and profiles.is_profile_complete = true
      and nullif(btrim(profiles.nickname), '') is not null
  )
);

drop policy if exists "community_polls_update_self" on public.community_polls;
create policy "community_polls_update_self"
on public.community_polls
for update
to authenticated
using (
  campus_id = public.current_profile_campus_id()
  and public.can_use_profile(author_id)
)
with check (
  campus_id = public.current_profile_campus_id()
  and public.can_use_profile(author_id)
);

drop policy if exists "community_poll_options_select_published_poll" on public.community_poll_options;
create policy "community_poll_options_select_published_poll"
on public.community_poll_options
for select
to authenticated
using (
  exists (
    select 1
    from public.community_polls polls
    where polls.id = community_poll_options.poll_id
      and polls.campus_id = public.current_profile_campus_id()
      and (polls.status = 'published' or public.can_use_profile(polls.author_id))
  )
);

drop policy if exists "community_poll_options_insert_owner" on public.community_poll_options;
create policy "community_poll_options_insert_owner"
on public.community_poll_options
for insert
to authenticated
with check (
  exists (
    select 1
    from public.community_polls polls
    where polls.id = community_poll_options.poll_id
      and polls.campus_id = public.current_profile_campus_id()
      and public.can_use_profile(polls.author_id)
  )
);

drop policy if exists "community_poll_votes_select_self" on public.community_poll_votes;
create policy "community_poll_votes_select_self"
on public.community_poll_votes
for select
to authenticated
using (
  public.can_use_profile(user_id)
  and exists (
    select 1
    from public.community_polls polls
    where polls.id = community_poll_votes.poll_id
      and polls.campus_id = public.current_profile_campus_id()
  )
);

drop policy if exists "community_poll_votes_insert_self" on public.community_poll_votes;
create policy "community_poll_votes_insert_self"
on public.community_poll_votes
for insert
to authenticated
with check (
  public.can_use_profile(user_id)
  and exists (
    select 1
    from public.community_polls polls
    join public.community_poll_options options on options.poll_id = polls.id
    where polls.id = community_poll_votes.poll_id
      and options.id = community_poll_votes.option_id
      and polls.campus_id = public.current_profile_campus_id()
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
  public.can_use_profile(user_id)
  and exists (
    select 1
    from public.community_polls polls
    where polls.id = community_poll_votes.poll_id
      and polls.campus_id = public.current_profile_campus_id()
  )
)
with check (
  public.can_use_profile(user_id)
  and exists (
    select 1
    from public.community_polls polls
    where polls.id = community_poll_votes.poll_id
      and polls.campus_id = public.current_profile_campus_id()
  )
);

drop policy if exists "post_likes_select_authenticated" on public.post_likes;
create policy "post_likes_select_authenticated"
on public.post_likes
for select
to authenticated
using (
  public.can_use_profile(user_id)
  and exists (
    select 1
    from public.posts
    where posts.id = post_likes.post_id
      and posts.campus_id = public.current_profile_campus_id()
  )
);

drop policy if exists "post_likes_insert_self" on public.post_likes;
create policy "post_likes_insert_self"
on public.post_likes
for insert
to authenticated
with check (
  public.can_use_profile(user_id)
  and exists (
    select 1
    from public.posts
    join public.profiles on profiles.id = post_likes.user_id
    where posts.id = post_likes.post_id
      and posts.campus_id = public.current_profile_campus_id()
      and posts.status = 'published'
      and posts.author_id <> post_likes.user_id
      and profiles.community_access_status = 'approved'
      and profiles.community_campus_id = posts.campus_id
  )
);

drop policy if exists "post_likes_delete_self" on public.post_likes;
create policy "post_likes_delete_self"
on public.post_likes
for delete
to authenticated
using (
  public.can_use_profile(user_id)
  and exists (
    select 1
    from public.posts
    where posts.id = post_likes.post_id
      and posts.campus_id = public.current_profile_campus_id()
  )
);

drop policy if exists "post_favorites_select_self" on public.post_favorites;
create policy "post_favorites_select_self"
on public.post_favorites
for select
to authenticated
using (
  public.can_use_profile(user_id)
  and exists (
    select 1
    from public.posts
    where posts.id = post_favorites.post_id
      and posts.campus_id = public.current_profile_campus_id()
  )
);

drop policy if exists "post_favorites_insert_self" on public.post_favorites;
create policy "post_favorites_insert_self"
on public.post_favorites
for insert
to authenticated
with check (
  public.can_use_profile(user_id)
  and exists (
    select 1
    from public.posts
    join public.profiles on profiles.id = post_favorites.user_id
    where posts.id = post_favorites.post_id
      and posts.campus_id = public.current_profile_campus_id()
      and posts.status = 'published'
      and profiles.community_access_status = 'approved'
      and profiles.community_campus_id = posts.campus_id
  )
);

drop policy if exists "post_favorites_delete_self" on public.post_favorites;
create policy "post_favorites_delete_self"
on public.post_favorites
for delete
to authenticated
using (
  public.can_use_profile(user_id)
  and exists (
    select 1
    from public.posts
    where posts.id = post_favorites.post_id
      and posts.campus_id = public.current_profile_campus_id()
  )
);

drop policy if exists "community_blocks_select_self" on public.community_blocks;
create policy "community_blocks_select_self"
on public.community_blocks
for select
to authenticated
using (
  public.can_use_profile(blocker_id)
  and exists (
    select 1
    from public.profiles blocked_profile
    where blocked_profile.id = community_blocks.blocked_id
      and blocked_profile.community_access_status = 'approved'
      and blocked_profile.community_campus_id = public.current_profile_campus_id()
  )
);

drop policy if exists "community_blocks_insert_self" on public.community_blocks;
create policy "community_blocks_insert_self"
on public.community_blocks
for insert
to authenticated
with check (
  public.can_use_profile(blocker_id)
  and exists (
    select 1
    from public.profiles blocker_profile
    join public.profiles blocked_profile on blocked_profile.id = community_blocks.blocked_id
    where blocker_profile.id = community_blocks.blocker_id
      and blocker_profile.community_access_status = 'approved'
      and blocker_profile.community_campus_id = public.current_profile_campus_id()
      and blocked_profile.community_access_status = 'approved'
      and blocked_profile.community_campus_id = blocker_profile.community_campus_id
  )
);

drop policy if exists "community_blocks_delete_self" on public.community_blocks;
create policy "community_blocks_delete_self"
on public.community_blocks
for delete
to authenticated
using (public.can_use_profile(blocker_id));

drop policy if exists "community_reports_select_self" on public.community_reports;
create policy "community_reports_select_self"
on public.community_reports
for select
to authenticated
using (
  public.can_use_profile(reporter_id)
  and exists (
    select 1
    from public.profiles reporter_profile
    where reporter_profile.id = community_reports.reporter_id
      and reporter_profile.community_access_status = 'approved'
      and reporter_profile.community_campus_id = public.current_profile_campus_id()
  )
);

drop policy if exists "community_reports_insert_self" on public.community_reports;
create policy "community_reports_insert_self"
on public.community_reports
for insert
to authenticated
with check (
  public.can_use_profile(reporter_id)
  and exists (
    select 1
    from public.profiles reporter_profile
    where reporter_profile.id = community_reports.reporter_id
      and reporter_profile.community_access_status = 'approved'
      and reporter_profile.community_campus_id = public.current_profile_campus_id()
  )
  and (
    (
      target_type = 'post'
      and exists (
        select 1
        from public.posts
        where posts.id = community_reports.post_id
          and posts.campus_id = public.current_profile_campus_id()
      )
    )
    or (
      target_type = 'comment'
      and exists (
        select 1
        from public.comments
        join public.posts on posts.id = comments.post_id
        where comments.id = community_reports.comment_id
          and posts.campus_id = public.current_profile_campus_id()
      )
    )
    or (
      target_type = 'user'
      and exists (
        select 1
        from public.profiles reported_profile
        where reported_profile.id = community_reports.reported_user_id
          and reported_profile.community_access_status = 'approved'
          and reported_profile.community_campus_id = public.current_profile_campus_id()
      )
    )
  )
);

drop policy if exists "community_notifications_select_recipient" on public.community_notifications;
create policy "community_notifications_select_recipient"
on public.community_notifications
for select
to authenticated
using (
  public.can_use_profile(recipient_id)
  and exists (
    select 1
    from public.profiles recipient_profile
    where recipient_profile.id = community_notifications.recipient_id
      and recipient_profile.community_access_status = 'approved'
      and recipient_profile.community_campus_id = public.current_profile_campus_id()
  )
);

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
  and exists (
    select 1
    from public.posts
    join public.profiles actor_profile on actor_profile.id = community_notifications.actor_id
    where posts.id = community_notifications.post_id
      and posts.author_id = community_notifications.recipient_id
      and posts.campus_id = public.current_profile_campus_id()
      and actor_profile.community_access_status = 'approved'
      and actor_profile.community_campus_id = posts.campus_id
  )
);

alter table public.teachers
  drop constraint if exists teachers_name_unit_unique;

drop index if exists public.teachers_name_unit_unique;

create unique index if not exists idx_teachers_campus_name_unit_unique
on public.teachers (campus_id, lower(btrim(name)), lower(btrim(unit)));

drop policy if exists "teachers_select_authenticated" on public.teachers;
create policy "teachers_select_authenticated"
on public.teachers
for select
to authenticated
using (
  status = 'published'
  and campus_id = public.current_profile_campus_id()
);

drop policy if exists "teacher_ratings_select_self" on public.teacher_ratings;
create policy "teacher_ratings_select_self"
on public.teacher_ratings
for select
to authenticated
using (
  public.can_use_profile(user_id)
  and exists (
    select 1
    from public.teachers
    where teachers.id = teacher_ratings.teacher_id
      and teachers.campus_id = public.current_profile_campus_id()
  )
);

drop policy if exists "teacher_ratings_insert_self" on public.teacher_ratings;
create policy "teacher_ratings_insert_self"
on public.teacher_ratings
for insert
to authenticated
with check (
  public.can_use_profile(user_id)
  and exists (
    select 1
    from public.teachers
    where teachers.id = teacher_ratings.teacher_id
      and teachers.campus_id = public.current_profile_campus_id()
      and teachers.status = 'published'
  )
);

drop policy if exists "teacher_ratings_update_self" on public.teacher_ratings;
create policy "teacher_ratings_update_self"
on public.teacher_ratings
for update
to authenticated
using (
  public.can_use_profile(user_id)
  and exists (
    select 1
    from public.teachers
    where teachers.id = teacher_ratings.teacher_id
      and teachers.campus_id = public.current_profile_campus_id()
  )
)
with check (
  public.can_use_profile(user_id)
  and exists (
    select 1
    from public.teachers
    where teachers.id = teacher_ratings.teacher_id
      and teachers.campus_id = public.current_profile_campus_id()
  )
);

alter table public.course_catalog
  drop constraint if exists course_catalog_name_unit_category_unique;

drop index if exists public.course_catalog_name_unit_category_unique;

create unique index if not exists idx_course_catalog_campus_name_unit_category_unique
on public.course_catalog (campus_id, lower(btrim(name)), lower(btrim(unit)), lower(btrim(category)));

drop policy if exists "course_catalog_select_published_authenticated" on public.course_catalog;
create policy "course_catalog_select_published_authenticated"
on public.course_catalog
for select
to authenticated
using (
  status = 'published'
  and campus_id = public.current_profile_campus_id()
);

drop policy if exists "course_ratings_select_self" on public.course_ratings;
create policy "course_ratings_select_self"
on public.course_ratings
for select
to authenticated
using (
  public.can_use_profile(user_id)
  and exists (
    select 1
    from public.course_catalog
    where course_catalog.id = course_ratings.course_id
      and course_catalog.campus_id = public.current_profile_campus_id()
  )
);

drop policy if exists "course_ratings_insert_self" on public.course_ratings;
create policy "course_ratings_insert_self"
on public.course_ratings
for insert
to authenticated
with check (
  public.can_use_profile(user_id)
  and exists (
    select 1
    from public.course_catalog
    where course_catalog.id = course_ratings.course_id
      and course_catalog.campus_id = public.current_profile_campus_id()
      and course_catalog.status = 'published'
  )
);

drop policy if exists "course_ratings_update_self" on public.course_ratings;
create policy "course_ratings_update_self"
on public.course_ratings
for update
to authenticated
using (
  public.can_use_profile(user_id)
  and exists (
    select 1
    from public.course_catalog
    where course_catalog.id = course_ratings.course_id
      and course_catalog.campus_id = public.current_profile_campus_id()
  )
)
with check (
  public.can_use_profile(user_id)
  and exists (
    select 1
    from public.course_catalog
    where course_catalog.id = course_ratings.course_id
      and course_catalog.campus_id = public.current_profile_campus_id()
  )
);

do $$
begin
  if to_regclass('public.dish_catalog') is not null then
    execute 'alter table public.dish_catalog drop constraint if exists dish_catalog_name_location_unique';
    execute 'drop index if exists public.dish_catalog_name_location_unique';
    execute 'create unique index if not exists idx_dish_catalog_campus_name_location_unique on public.dish_catalog (campus_id, lower(btrim(name)), lower(btrim(location)))';

    execute 'drop policy if exists "dish_catalog_select_published_authenticated" on public.dish_catalog';
    execute $policy$
      create policy "dish_catalog_select_published_authenticated"
      on public.dish_catalog
      for select
      to authenticated
      using (
        status = 'published'
        and campus_id = public.current_profile_campus_id()
      )
    $policy$;
  end if;

  if to_regclass('public.dish_ratings') is not null then
    execute 'drop policy if exists "dish_ratings_select_self" on public.dish_ratings';
    execute $policy$
      create policy "dish_ratings_select_self"
      on public.dish_ratings
      for select
      to authenticated
      using (
        public.can_use_profile(user_id)
        and exists (
          select 1
          from public.dish_catalog
          where dish_catalog.id = dish_ratings.dish_id
            and dish_catalog.campus_id = public.current_profile_campus_id()
        )
      )
    $policy$;

    execute 'drop policy if exists "dish_ratings_insert_self" on public.dish_ratings';
    execute $policy$
      create policy "dish_ratings_insert_self"
      on public.dish_ratings
      for insert
      to authenticated
      with check (
        public.can_use_profile(user_id)
        and exists (
          select 1
          from public.dish_catalog
          where dish_catalog.id = dish_ratings.dish_id
            and dish_catalog.campus_id = public.current_profile_campus_id()
            and dish_catalog.status = 'published'
        )
      )
    $policy$;

    execute 'drop policy if exists "dish_ratings_update_self" on public.dish_ratings';
    execute $policy$
      create policy "dish_ratings_update_self"
      on public.dish_ratings
      for update
      to authenticated
      using (
        public.can_use_profile(user_id)
        and exists (
          select 1
          from public.dish_catalog
          where dish_catalog.id = dish_ratings.dish_id
            and dish_catalog.campus_id = public.current_profile_campus_id()
        )
      )
      with check (
        public.can_use_profile(user_id)
        and exists (
          select 1
          from public.dish_catalog
          where dish_catalog.id = dish_ratings.dish_id
            and dish_catalog.campus_id = public.current_profile_campus_id()
        )
      )
    $policy$;
  end if;
end $$;

create or replace function public.submit_campus_membership_request(p_school_name text)
returns public.campus_membership_requests
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_profile_id uuid := public.current_profile_id();
  actor_auth_user_id uuid := auth.uid();
  normalized_school_name text := public.normalize_school_name(p_school_name);
  inserted_request public.campus_membership_requests;
begin
  perform set_config('app.community_membership_action', 'true', true);

  if actor_auth_user_id is null or actor_profile_id is null then
    raise exception 'COMMUNITY_AUTH_REQUIRED' using errcode = '42501';
  end if;

  if normalized_school_name is null or normalized_school_name = '' then
    raise exception 'COMMUNITY_SCHOOL_NAME_REQUIRED' using errcode = '22023';
  end if;

  insert into public.campus_membership_requests (
    requester_profile_id,
    requester_auth_user_id,
    school_name,
    normalized_school_name,
    status
  )
  values (
    actor_profile_id,
    actor_auth_user_id,
    btrim(p_school_name),
    normalized_school_name,
    'pending'
  )
  returning * into inserted_request;

  update public.profiles
  set
    campus_id = 'general',
    community_campus_id = null,
    community_access_status = 'pending',
    community_school_name = inserted_request.school_name,
    community_rejection_reason = null,
    community_request_id = inserted_request.id,
    updated_at = now()
  where id = actor_profile_id;

  update public.profile_auth_links
  set
    campus_id = 'general',
    last_seen_at = now()
  where profile_id = actor_profile_id
    and auth_user_id = actor_auth_user_id;

  return inserted_request;
end;
$$;

create or replace function public.approve_campus_membership_request(
  p_request_id uuid,
  p_campus_id text,
  p_admin_id uuid default null,
  p_admin_note text default null
)
returns public.campus_membership_requests
language plpgsql
security definer
set search_path = public
as $$
declare
  normalized_campus_id text := lower(btrim(coalesce(p_campus_id, '')));
  target_campus public.campuses;
  updated_request public.campus_membership_requests;
begin
  perform set_config('app.community_membership_action', 'true', true);

  if normalized_campus_id = '' then
    raise exception 'COMMUNITY_CAMPUS_REQUIRED' using errcode = '22023';
  end if;

  select *
  into target_campus
  from public.campuses
  where id = normalized_campus_id
    and status = 'active'
    and is_community_enabled = true;

  if target_campus.id is null then
    raise exception 'COMMUNITY_CAMPUS_NOT_FOUND' using errcode = '22023';
  end if;

  update public.campus_membership_requests
  set
    status = 'approved',
    approved_campus_id = normalized_campus_id,
    admin_note = nullif(btrim(coalesce(p_admin_note, '')), ''),
    reviewed_by = p_admin_id,
    reviewed_at = now(),
    updated_at = now()
  where id = p_request_id
  returning * into updated_request;

  if updated_request.id is null then
    raise exception 'COMMUNITY_REQUEST_NOT_FOUND' using errcode = '22023';
  end if;

  update public.profiles
  set
    campus_id = normalized_campus_id,
    community_campus_id = normalized_campus_id,
    community_access_status = 'approved',
    community_school_name = target_campus.display_name,
    community_rejection_reason = null,
    community_request_id = updated_request.id,
    updated_at = now()
  where id = updated_request.requester_profile_id;

  update public.profile_auth_links
  set
    campus_id = normalized_campus_id,
    last_seen_at = now()
  where profile_id = updated_request.requester_profile_id;

  return updated_request;
end;
$$;

create or replace function public.reject_campus_membership_request(
  p_request_id uuid,
  p_admin_id uuid default null,
  p_admin_note text default null
)
returns public.campus_membership_requests
language plpgsql
security definer
set search_path = public
as $$
declare
  updated_request public.campus_membership_requests;
begin
  perform set_config('app.community_membership_action', 'true', true);

  update public.campus_membership_requests
  set
    status = 'rejected',
    approved_campus_id = null,
    admin_note = nullif(btrim(coalesce(p_admin_note, '')), ''),
    reviewed_by = p_admin_id,
    reviewed_at = now(),
    updated_at = now()
  where id = p_request_id
  returning * into updated_request;

  if updated_request.id is null then
    raise exception 'COMMUNITY_REQUEST_NOT_FOUND' using errcode = '22023';
  end if;

  update public.profiles
  set
    campus_id = 'general',
    community_campus_id = null,
    community_access_status = 'rejected',
    community_school_name = updated_request.school_name,
    community_rejection_reason = coalesce(updated_request.admin_note, '学校申请未通过。'),
    community_request_id = updated_request.id,
    updated_at = now()
  where id = updated_request.requester_profile_id;

  update public.profile_auth_links
  set
    campus_id = 'general',
    last_seen_at = now()
  where profile_id = updated_request.requester_profile_id;

  return updated_request;
end;
$$;

revoke all on function public.submit_campus_membership_request(text) from public, anon;
grant execute on function public.submit_campus_membership_request(text) to authenticated, service_role;

revoke all on function public.approve_campus_membership_request(uuid, text, uuid, text) from public, anon, authenticated;
revoke all on function public.reject_campus_membership_request(uuid, uuid, text) from public, anon, authenticated;
grant execute on function public.approve_campus_membership_request(uuid, text, uuid, text) to service_role;
grant execute on function public.reject_campus_membership_request(uuid, uuid, text) to service_role;

create or replace function public.community_feed_v1(
  p_category text default null,
  p_search text default null,
  p_limit integer default 20,
  p_campus_id text default 'bjfu'
)
returns jsonb
language plpgsql
stable
set search_path = public
as $$
begin
  if auth.uid() is not null
    and public.current_profile_campus_id() is null
  then
    return jsonb_build_object('generated_at', now(), 'posts', '[]'::jsonb);
  end if;

  return private.community_feed_v1_impl(p_category, p_search, p_limit, p_campus_id);
end;
$$;

create or replace function public.community_hot_posts_v1(
  p_days integer default 7,
  p_limit integer default 10,
  p_campus_id text default 'bjfu'
)
returns jsonb
language plpgsql
stable
set search_path = public
as $$
begin
  if auth.uid() is not null
    and public.current_profile_campus_id() is null
  then
    return jsonb_build_object('generated_at', now(), 'posts', '[]'::jsonb);
  end if;

  return private.community_hot_posts_v1_impl(p_days, p_limit, p_campus_id);
end;
$$;

grant execute on function public.community_feed_v1(text, text, integer, text) to authenticated, service_role;
grant execute on function public.community_hot_posts_v1(integer, integer, text) to authenticated, service_role;

create or replace function public.admin_daily_counts(
  p_days integer default 30,
  p_timezone text default 'UTC',
  p_campus_id text default null
)
returns table (
  bucket_date date,
  profiles integer,
  posts integer,
  comments integer,
  feedback integer,
  ratings integer
)
language sql
security definer
stable
set search_path = public
as $$
  with bounds as (
    select
      least(greatest(coalesce(p_days, 30), 1), 90)::integer as days,
      coalesce(nullif(btrim(p_timezone), ''), 'UTC') as zone,
      lower(nullif(btrim(p_campus_id), '')) as campus_id
  ),
  buckets as (
    select generate_series(
      ((now() at time zone bounds.zone)::date - (bounds.days - 1)),
      (now() at time zone bounds.zone)::date,
      interval '1 day'
    )::date as bucket_date
    from bounds
  ),
  profile_counts as (
    select (profiles.created_at at time zone bounds.zone)::date as bucket_date, count(*)::integer as total
    from public.profiles, bounds
    where (profiles.created_at at time zone bounds.zone)::date >= ((now() at time zone bounds.zone)::date - (bounds.days - 1))
      and (bounds.campus_id is null or profiles.community_campus_id = bounds.campus_id)
    group by 1
  ),
  post_counts as (
    select (posts.created_at at time zone bounds.zone)::date as bucket_date, count(*)::integer as total
    from public.posts, bounds
    where (posts.created_at at time zone bounds.zone)::date >= ((now() at time zone bounds.zone)::date - (bounds.days - 1))
      and (bounds.campus_id is null or posts.campus_id = bounds.campus_id)
    group by 1
  ),
  comment_counts as (
    select (comments.created_at at time zone bounds.zone)::date as bucket_date, count(*)::integer as total
    from public.comments
    join public.posts on posts.id = comments.post_id,
    bounds
    where (comments.created_at at time zone bounds.zone)::date >= ((now() at time zone bounds.zone)::date - (bounds.days - 1))
      and (bounds.campus_id is null or posts.campus_id = bounds.campus_id)
    group by 1
  ),
  feedback_counts as (
    select (feedback_submissions.created_at at time zone bounds.zone)::date as bucket_date, count(*)::integer as total
    from public.feedback_submissions, bounds
    where (feedback_submissions.created_at at time zone bounds.zone)::date >= ((now() at time zone bounds.zone)::date - (bounds.days - 1))
      and (bounds.campus_id is null or feedback_submissions.campus_id = bounds.campus_id)
    group by 1
  ),
  rating_counts as (
    select (teacher_ratings.created_at at time zone bounds.zone)::date as bucket_date, count(*)::integer as total
    from public.teacher_ratings
    join public.teachers on teachers.id = teacher_ratings.teacher_id,
    bounds
    where (teacher_ratings.created_at at time zone bounds.zone)::date >= ((now() at time zone bounds.zone)::date - (bounds.days - 1))
      and (bounds.campus_id is null or teachers.campus_id = bounds.campus_id)
    group by 1
  )
  select
    buckets.bucket_date,
    coalesce(profile_counts.total, 0),
    coalesce(post_counts.total, 0),
    coalesce(comment_counts.total, 0),
    coalesce(feedback_counts.total, 0),
    coalesce(rating_counts.total, 0)
  from buckets
  left join profile_counts using (bucket_date)
  left join post_counts using (bucket_date)
  left join comment_counts using (bucket_date)
  left join feedback_counts using (bucket_date)
  left join rating_counts using (bucket_date)
  order by buckets.bucket_date asc;
$$;

create or replace function public.admin_activity_heatmap(
  p_days integer default 30,
  p_timezone text default 'UTC',
  p_campus_id text default null
)
returns table (
  weekday integer,
  hour integer,
  posts integer,
  comments integer,
  feedback integer
)
language sql
security definer
stable
set search_path = public
as $$
  with bounds as (
    select
      least(greatest(coalesce(p_days, 30), 1), 90)::integer as days,
      coalesce(nullif(btrim(p_timezone), ''), 'UTC') as zone,
      lower(nullif(btrim(p_campus_id), '')) as campus_id
  ),
  buckets as (
    select weekday, hour
    from generate_series(0, 6) as weekday
    cross join generate_series(0, 23) as hour
  ),
  events as (
    select
      extract(dow from posts.created_at at time zone bounds.zone)::integer as weekday,
      extract(hour from posts.created_at at time zone bounds.zone)::integer as hour,
      'posts'::text as kind
    from public.posts, bounds
    where (posts.created_at at time zone bounds.zone)::date >= ((now() at time zone bounds.zone)::date - (bounds.days - 1))
      and (bounds.campus_id is null or posts.campus_id = bounds.campus_id)
    union all
    select
      extract(dow from comments.created_at at time zone bounds.zone)::integer,
      extract(hour from comments.created_at at time zone bounds.zone)::integer,
      'comments'::text
    from public.comments
    join public.posts on posts.id = comments.post_id,
    bounds
    where (comments.created_at at time zone bounds.zone)::date >= ((now() at time zone bounds.zone)::date - (bounds.days - 1))
      and (bounds.campus_id is null or posts.campus_id = bounds.campus_id)
    union all
    select
      extract(dow from feedback_submissions.created_at at time zone bounds.zone)::integer,
      extract(hour from feedback_submissions.created_at at time zone bounds.zone)::integer,
      'feedback'::text
    from public.feedback_submissions, bounds
    where (feedback_submissions.created_at at time zone bounds.zone)::date >= ((now() at time zone bounds.zone)::date - (bounds.days - 1))
      and (bounds.campus_id is null or feedback_submissions.campus_id = bounds.campus_id)
  )
  select
    buckets.weekday,
    buckets.hour,
    count(*) filter (where events.kind = 'posts')::integer,
    count(*) filter (where events.kind = 'comments')::integer,
    count(*) filter (where events.kind = 'feedback')::integer
  from buckets
  left join events using (weekday, hour)
  group by buckets.weekday, buckets.hour
  order by buckets.weekday asc, buckets.hour asc;
$$;

create or replace function public.admin_category_mix(
  p_days integer default 30,
  p_timezone text default 'UTC',
  p_campus_id text default null
)
returns table (
  category text,
  posts integer,
  comments integer
)
language sql
security definer
stable
set search_path = public
as $$
  with bounds as (
    select
      least(greatest(coalesce(p_days, 30), 1), 90)::integer as days,
      coalesce(nullif(btrim(p_timezone), ''), 'UTC') as zone,
      lower(nullif(btrim(p_campus_id), '')) as campus_id
  ),
  filtered_posts as (
    select
      posts.id,
      coalesce(nullif(btrim(posts.category), ''), '未分类') as category
    from public.posts, bounds
    where (posts.created_at at time zone bounds.zone)::date >= ((now() at time zone bounds.zone)::date - (bounds.days - 1))
      and (bounds.campus_id is null or posts.campus_id = bounds.campus_id)
  )
  select
    filtered_posts.category,
    count(distinct filtered_posts.id)::integer as posts,
    count(comments.id)::integer as comments
  from filtered_posts
  left join public.comments on comments.post_id = filtered_posts.id
  group by filtered_posts.category
  order by posts desc, comments desc, filtered_posts.category asc
  limit 10;
$$;

create or replace function public.admin_top_content(
  p_days integer default 30,
  p_timezone text default 'UTC',
  p_limit integer default 8,
  p_campus_id text default null
)
returns table (
  id uuid,
  title text,
  category text,
  author_id uuid,
  status text,
  created_at timestamptz,
  comment_count integer,
  like_count integer,
  score integer
)
language sql
security definer
stable
set search_path = public
as $$
  with bounds as (
    select
      least(greatest(coalesce(p_days, 30), 1), 90)::integer as days,
      coalesce(nullif(btrim(p_timezone), ''), 'UTC') as zone,
      least(greatest(coalesce(p_limit, 8), 1), 20)::integer as row_limit,
      lower(nullif(btrim(p_campus_id), '')) as campus_id
  ),
  likes as (
    select post_id, count(*)::integer as like_count
    from public.post_likes
    group by post_id
  )
  select
    posts.id,
    posts.title,
    coalesce(nullif(btrim(posts.category), ''), '未分类') as category,
    posts.author_id,
    posts.status,
    posts.created_at,
    posts.comment_count,
    coalesce(likes.like_count, 0) as like_count,
    (posts.comment_count * 3 + coalesce(likes.like_count, 0))::integer as score
  from public.posts
  cross join bounds
  left join likes on likes.post_id = posts.id
  where (posts.created_at at time zone bounds.zone)::date >= ((now() at time zone bounds.zone)::date - (bounds.days - 1))
    and posts.status <> 'deleted'
    and (bounds.campus_id is null or posts.campus_id = bounds.campus_id)
  order by score desc, posts.created_at desc
  limit (select row_limit from bounds);
$$;

revoke all on function public.admin_daily_counts(integer, text, text) from public, authenticated;
revoke all on function public.admin_activity_heatmap(integer, text, text) from public, authenticated;
revoke all on function public.admin_category_mix(integer, text, text) from public, authenticated;
revoke all on function public.admin_top_content(integer, text, integer, text) from public, authenticated;

grant execute on function public.admin_daily_counts(integer, text, text) to service_role;
grant execute on function public.admin_activity_heatmap(integer, text, text) to service_role;
grant execute on function public.admin_category_mix(integer, text, text) to service_role;
grant execute on function public.admin_top_content(integer, text, integer, text) to service_role;

comment on table public.campus_membership_requests is 'School community membership requests. Approval unlocks community_campus_id only; non-BJFU academic data remains local to the app.';

select pg_notify('pgrst', 'reload schema');
