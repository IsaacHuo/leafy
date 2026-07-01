create table if not exists public.campuses (
  id text primary key,
  display_name text not null,
  short_name text not null,
  connector_kind text not null,
  status text not null default 'active' check (status in ('active', 'disabled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint campuses_id_not_blank check (nullif(btrim(id), '') is not null)
);

insert into public.campuses (id, display_name, short_name, connector_kind, status)
values ('bjfu', '北京林业大学', '北林', 'bjfu', 'active')
on conflict (id) do update
set
  display_name = excluded.display_name,
  short_name = excluded.short_name,
  connector_kind = excluded.connector_kind,
  status = excluded.status,
  updated_at = now();

do $$
declare
  table_name text;
  constraint_name text;
  index_name text;
begin
  foreach table_name in array array[
    'profiles',
    'profile_auth_links',
    'posts',
    'community_polls',
    'community_post_pins',
    'teachers',
    'course_catalog',
    'dish_catalog',
    'catalog_suggestions',
    'feedback_submissions',
    'site_announcements',
    'semester_runtime_configs',
    'campus_weather_cache',
    'timetable_snapshots',
    'timetable_invites',
    'timetable_share_members'
  ] loop
    if to_regclass('public.' || table_name) is not null then
      execute format('alter table public.%I add column if not exists campus_id text not null default %L', table_name, 'bjfu');
      execute format('update public.%I set campus_id = %L where campus_id is null or nullif(btrim(campus_id), %L) is null', table_name, 'bjfu', '');
      execute format('alter table public.%I alter column campus_id set not null', table_name);

      constraint_name := table_name || '_campus_id_fkey';
      if not exists (
        select 1
        from pg_constraint
        where conname = constraint_name
          and conrelid = format('public.%I', table_name)::regclass
      ) then
        execute format(
          'alter table public.%I add constraint %I foreign key (campus_id) references public.campuses(id) on update cascade',
          table_name,
          constraint_name
        );
      end if;

      index_name := 'idx_' || table_name || '_campus_id';
      execute format('create index if not exists %I on public.%I (campus_id)', index_name, table_name);
    end if;
  end loop;
end $$;

update public.profile_auth_links links
set campus_id = profiles.campus_id
from public.profiles profiles
where links.profile_id = profiles.id;

alter table public.profiles
  drop constraint if exists profiles_edu_id_key;

drop index if exists public.profiles_edu_id_key;

create unique index if not exists idx_profiles_campus_edu_id_unique
on public.profiles (campus_id, edu_id);

create index if not exists idx_profile_auth_links_campus_edu_id
on public.profile_auth_links (campus_id, edu_id);

create index if not exists idx_posts_campus_status_created_at
on public.posts (campus_id, status, created_at desc);

alter table public.timetable_invites
  drop constraint if exists timetable_invites_code_hash_key;

drop index if exists public.timetable_invites_code_hash_key;

create unique index if not exists idx_timetable_invites_campus_code_hash_unique
on public.timetable_invites (campus_id, code_hash);

alter table public.semester_runtime_configs
  drop constraint if exists semester_runtime_configs_semester_unique;

drop index if exists idx_semester_runtime_configs_single_active;

create unique index if not exists idx_semester_runtime_configs_campus_semester_unique
on public.semester_runtime_configs (campus_id, semester_id);

create unique index if not exists idx_semester_runtime_configs_campus_single_active
on public.semester_runtime_configs (campus_id)
where is_active = true;

create or replace function public.current_profile_campus_id()
returns text
language sql
security definer
stable
set search_path = public
as $$
  select profiles.campus_id
  from public.profile_auth_links links
  join public.profiles profiles on profiles.id = links.profile_id
  where links.auth_user_id = auth.uid()
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
      join public.profiles profiles on profiles.id = links.profile_id
      where links.auth_user_id = auth.uid()
        and links.profile_id = target_profile_id
        and profiles.campus_id = links.campus_id
    );
$$;

grant execute on function public.current_profile_campus_id() to authenticated, service_role;
grant execute on function public.can_use_profile(uuid) to authenticated, service_role;

alter table public.posts
  alter column campus_id set default coalesce(public.current_profile_campus_id(), 'bjfu');

alter table public.community_polls
  alter column campus_id set default coalesce(public.current_profile_campus_id(), 'bjfu');

alter table public.catalog_suggestions
  alter column campus_id set default coalesce(public.current_profile_campus_id(), 'bjfu');

alter table public.feedback_submissions
  alter column campus_id set default coalesce(public.current_profile_campus_id(), 'bjfu');

alter table public.timetable_snapshots
  alter column campus_id set default coalesce(public.current_profile_campus_id(), 'bjfu');

alter table public.timetable_invites
  alter column campus_id set default coalesce(public.current_profile_campus_id(), 'bjfu');

drop policy if exists "profiles_select_authenticated" on public.profiles;
create policy "profiles_select_authenticated"
on public.profiles
for select
to authenticated
using (
  public.can_use_profile(id)
  or campus_id = public.current_profile_campus_id()
);

drop policy if exists "profiles_insert_self" on public.profiles;
create policy "profiles_insert_self"
on public.profiles
for insert
to authenticated
with check (
  auth.uid() = id
  and campus_id = coalesce(public.current_profile_campus_id(), campus_id)
);

drop policy if exists "profiles_update_self" on public.profiles;
create policy "profiles_update_self"
on public.profiles
for update
to authenticated
using (public.can_use_profile(id))
with check (public.can_use_profile(id));

drop policy if exists "posts_select_published" on public.posts;
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
  campus_id = public.current_profile_campus_id()
  and public.can_use_profile(author_id)
)
with check (
  campus_id = public.current_profile_campus_id()
  and public.can_use_profile(author_id)
  and status in ('published', 'pending_review', 'hidden', 'deleted')
);

drop policy if exists "comments_select_published" on public.comments;
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
using (public.can_use_profile(author_id))
with check (public.can_use_profile(author_id));

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

create or replace function public.can_view_timetable_snapshot(target_owner_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select target_owner_id is not null
    and exists (
      select 1
      from public.profiles owner_profile
      where owner_profile.id = target_owner_id
        and owner_profile.campus_id = public.current_profile_campus_id()
    )
    and (
      public.can_use_profile(target_owner_id)
      or exists (
        select 1
        from public.timetable_share_members members
        where members.owner_id = target_owner_id
          and members.viewer_id = public.current_profile_id()
          and members.campus_id = public.current_profile_campus_id()
          and members.revoked_at is null
      )
    );
$$;

drop policy if exists "timetable_snapshots_select_permitted" on public.timetable_snapshots;
create policy "timetable_snapshots_select_permitted"
on public.timetable_snapshots
for select
to authenticated
using (
  campus_id = public.current_profile_campus_id()
  and public.can_view_timetable_snapshot(owner_id)
);

drop policy if exists "timetable_snapshots_insert_owner" on public.timetable_snapshots;
create policy "timetable_snapshots_insert_owner"
on public.timetable_snapshots
for insert
to authenticated
with check (
  campus_id = public.current_profile_campus_id()
  and public.can_use_profile(owner_id)
);

drop policy if exists "timetable_snapshots_update_owner" on public.timetable_snapshots;
create policy "timetable_snapshots_update_owner"
on public.timetable_snapshots
for update
to authenticated
using (
  campus_id = public.current_profile_campus_id()
  and public.can_use_profile(owner_id)
)
with check (
  campus_id = public.current_profile_campus_id()
  and public.can_use_profile(owner_id)
);

drop policy if exists "timetable_snapshots_delete_owner" on public.timetable_snapshots;
create policy "timetable_snapshots_delete_owner"
on public.timetable_snapshots
for delete
to authenticated
using (
  campus_id = public.current_profile_campus_id()
  and public.can_use_profile(owner_id)
);

drop policy if exists "timetable_invites_select_owner" on public.timetable_invites;
create policy "timetable_invites_select_owner"
on public.timetable_invites
for select
to authenticated
using (
  campus_id = public.current_profile_campus_id()
  and public.can_use_profile(owner_id)
);

drop policy if exists "timetable_share_members_select_participant" on public.timetable_share_members;
create policy "timetable_share_members_select_participant"
on public.timetable_share_members
for select
to authenticated
using (
  campus_id = public.current_profile_campus_id()
  and (
    public.can_use_profile(owner_id)
    or public.can_use_profile(viewer_id)
  )
);

create or replace function public.create_timetable_invite(p_code text)
returns table (
  id uuid,
  owner_id uuid,
  semester_id text,
  expires_at timestamptz,
  accepted_by uuid,
  accepted_at timestamptz,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_profile_id uuid;
  actor_campus_id text;
  normalized_code text;
  target_snapshot public.timetable_snapshots%rowtype;
  created_invite public.timetable_invites%rowtype;
begin
  actor_profile_id := public.current_profile_id();
  actor_campus_id := public.current_profile_campus_id();
  if actor_profile_id is null or actor_campus_id is null then
    raise exception 'MISSING_PROFILE';
  end if;

  select *
  into target_snapshot
  from public.timetable_snapshots snapshots
  where snapshots.owner_id = actor_profile_id
    and snapshots.campus_id = actor_campus_id
  order by snapshots.published_at desc
  limit 1;

  if target_snapshot.id is null then
    raise exception 'TIMETABLE_NOT_PUBLISHED';
  end if;

  normalized_code := public.normalize_timetable_invite_code(p_code);
  if char_length(normalized_code) <> 12 then
    raise exception 'INVALID_INVITE_CODE';
  end if;

  insert into public.timetable_invites (
    campus_id,
    owner_id,
    semester_id,
    code_hash,
    expires_at
  )
  values (
    actor_campus_id,
    actor_profile_id,
    target_snapshot.semester_id,
    public.hash_timetable_invite_code(normalized_code),
    now() + interval '7 days'
  )
  returning * into created_invite;

  return query
  select
    created_invite.id,
    created_invite.owner_id,
    created_invite.semester_id,
    created_invite.expires_at,
    created_invite.accepted_by,
    created_invite.accepted_at,
    created_invite.created_at;
exception
  when unique_violation then
    raise exception 'INVITE_CODE_COLLISION';
end;
$$;

create or replace function public.accept_timetable_invite(p_code text)
returns table (
  id uuid,
  owner_id uuid,
  semester_id text,
  courses jsonb,
  course_count integer,
  published_at timestamptz,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_profile_id uuid;
  actor_campus_id text;
  normalized_code text;
  target_invite public.timetable_invites%rowtype;
  target_snapshot public.timetable_snapshots%rowtype;
begin
  actor_profile_id := public.current_profile_id();
  actor_campus_id := public.current_profile_campus_id();
  if actor_profile_id is null or actor_campus_id is null then
    raise exception 'MISSING_PROFILE';
  end if;

  normalized_code := public.normalize_timetable_invite_code(p_code);
  if char_length(normalized_code) <> 12 then
    raise exception 'INVALID_INVITE_CODE';
  end if;

  select *
  into target_invite
  from public.timetable_invites invites
  where invites.campus_id = actor_campus_id
    and invites.code_hash = public.hash_timetable_invite_code(normalized_code)
  for update;

  if target_invite.id is null then
    raise exception 'INVALID_INVITE_CODE';
  end if;

  if target_invite.expires_at <= now() then
    raise exception 'INVITE_EXPIRED';
  end if;

  if target_invite.accepted_by is not null then
    raise exception 'INVITE_USED';
  end if;

  if target_invite.owner_id = actor_profile_id then
    raise exception 'INVITE_SELF';
  end if;

  select *
  into target_snapshot
  from public.timetable_snapshots snapshots
  where snapshots.owner_id = target_invite.owner_id
    and snapshots.semester_id = target_invite.semester_id
    and snapshots.campus_id = actor_campus_id
  limit 1;

  if target_snapshot.id is null then
    raise exception 'TIMETABLE_NOT_PUBLISHED';
  end if;

  insert into public.timetable_share_members (
    campus_id,
    owner_id,
    viewer_id,
    revoked_at
  )
  values (
    actor_campus_id,
    target_invite.owner_id,
    actor_profile_id,
    null
  )
  on conflict on constraint timetable_share_members_owner_viewer_unique do update
  set
    campus_id = excluded.campus_id,
    revoked_at = null,
    updated_at = now();

  update public.timetable_invites
  set
    accepted_by = actor_profile_id,
    accepted_at = now()
  where timetable_invites.id = target_invite.id
    and timetable_invites.campus_id = actor_campus_id;

  return query
  select
    target_snapshot.id,
    target_snapshot.owner_id,
    target_snapshot.semester_id,
    target_snapshot.courses,
    target_snapshot.course_count,
    target_snapshot.published_at,
    target_snapshot.created_at,
    target_snapshot.updated_at;
end;
$$;

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
grant usage on schema private to authenticated, service_role;

drop function if exists public.community_feed_v1(text, text, integer);
drop function if exists private.community_feed_v1_impl(text, text, integer);
drop function if exists public.community_hot_posts_v1(integer, integer);
drop function if exists private.community_hot_posts_v1_impl(integer, integer);

create or replace function private.community_feed_v1_impl(
  p_category text default null,
  p_search text default null,
  p_limit integer default 20,
  p_campus_id text default 'bjfu'
)
returns jsonb
language plpgsql
security definer
stable
set search_path = public, extensions
as $$
declare
  current_profile_id uuid := public.current_profile_id();
  current_campus_id text := public.current_profile_campus_id();
  requested_campus_id text := nullif(btrim(coalesce(p_campus_id, '')), '');
  target_campus_id text := coalesce(current_campus_id, requested_campus_id, 'bjfu');
  normalized_category text := nullif(btrim(coalesce(p_category, '')), '');
  normalized_search text := nullif(btrim(coalesce(p_search, '')), '');
  safe_limit integer := greatest(1, least(coalesce(p_limit, 20), 50));
  search_limit integer := case when nullif(btrim(coalesce(p_search, '')), '') is null then safe_limit else least(safe_limit * 4, 100) end;
  result jsonb;
begin
  with active_pins as (
    select pins.*
    from public.community_post_pins pins
    join public.posts pinned_posts on pinned_posts.id = pins.post_id
    where pins.campus_id = target_campus_id
      and pinned_posts.campus_id = target_campus_id
      and pins.status = 'active'
      and pins.starts_at <= now()
      and (pins.ends_at is null or pins.ends_at > now())
      and pinned_posts.status = 'published'
      and (
        pins.scope = 'global'
        or (
          pins.scope = 'category'
          and normalized_category is not null
          and lower(btrim(coalesce(pins.category, ''))) = lower(btrim(normalized_category))
        )
      )
  ),
  preferred_pins as (
    select distinct on (post_id)
      id,
      post_id,
      scope,
      category,
      priority,
      starts_at,
      ends_at,
      status,
      reason,
      created_at
    from active_pins
    order by post_id, priority desc, starts_at desc
  ),
  pinned_posts as (
    select posts.*
    from public.posts posts
    join preferred_pins pins on pins.post_id = posts.id
    where posts.status = 'published'
      and posts.campus_id = target_campus_id
  ),
  latest_posts as (
    select posts.*
    from public.posts posts
    where posts.campus_id = target_campus_id
      and posts.status = 'published'
      and (normalized_category is null or posts.category = normalized_category)
      and (
        normalized_search is null
        or lower(coalesce(posts.title, '') || ' ' || coalesce(posts.body, '') || ' ' || coalesce(posts.category, ''))
          like '%' || lower(normalized_search) || '%'
      )
    order by posts.created_at desc
    limit search_limit
  ),
  candidate_posts as (
    select distinct on (id) *
    from (
      select * from pinned_posts
      union all
      select * from latest_posts
    ) posts
    order by id, created_at desc
  ),
  visible_posts as (
    select posts.*
    from candidate_posts posts
    where current_profile_id is null
      or not exists (
        select 1
        from public.community_blocks blocks
        where blocks.blocker_id = current_profile_id
          and blocks.blocked_id = posts.author_id
      )
  ),
  filtered_posts as (
    select posts.*
    from visible_posts posts
    left join public.profiles author_profile on author_profile.id = posts.author_id
    where normalized_search is null
      or lower(coalesce(posts.title, '') || ' ' || coalesce(posts.body, '') || ' ' || coalesce(posts.category, '') || ' ' || coalesce(author_profile.nickname, '') || ' ' || coalesce(author_profile.display_name, ''))
        like '%' || lower(normalized_search) || '%'
  ),
  ordered_posts as (
    select
      posts.*,
      pins.id as pin_id,
      pins.scope as pin_scope,
      pins.category as pin_category,
      pins.priority as pin_priority,
      pins.starts_at as pin_starts_at,
      pins.ends_at as pin_ends_at,
      pins.status as pin_status,
      pins.reason as pin_reason,
      pins.created_at as pin_created_at
    from filtered_posts posts
    left join preferred_pins pins on pins.post_id = posts.id
    order by
      case when pins.id is null then 0 else 1 end desc,
      coalesce(pins.priority, -2147483648) desc,
      coalesce(pins.starts_at, '-infinity'::timestamptz) desc,
      posts.created_at desc
    limit safe_limit
  )
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', posts.id,
      'author_id', posts.author_id,
      'title', posts.title,
      'body', posts.body,
      'category', posts.category,
      'is_anonymous', posts.is_anonymous,
      'comment_count', posts.comment_count,
      'like_count', posts.like_count,
      'status', posts.status,
      'created_at', posts.created_at,
      'updated_at', posts.updated_at,
      'viewer_has_liked', exists (
        select 1
        from public.post_likes likes
        where likes.post_id = posts.id
          and likes.user_id = current_profile_id
      ),
      'viewer_has_favorited', exists (
        select 1
        from public.post_favorites favorites
        where favorites.post_id = posts.id
          and favorites.user_id = current_profile_id
      ),
      'pin', case
        when posts.pin_id is null then null
        else jsonb_build_object(
          'id', posts.pin_id,
          'post_id', posts.id,
          'scope', posts.pin_scope,
          'category', posts.pin_category,
          'priority', posts.pin_priority,
          'starts_at', posts.pin_starts_at,
          'ends_at', posts.pin_ends_at,
          'status', posts.pin_status,
          'reason', posts.pin_reason,
          'created_at', posts.pin_created_at
        )
      end,
      'author', case
        when author_profile.id is null then null
        else jsonb_build_object(
          'id', author_profile.id,
          'edu_id', author_profile.edu_id,
          'campus_id', author_profile.campus_id,
          'nickname', author_profile.nickname,
          'display_name', author_profile.display_name,
          'avatar_path', author_profile.avatar_path,
          'major', author_profile.major,
          'grade', author_profile.grade,
          'bound_email', author_profile.bound_email,
          'pending_bound_email', author_profile.pending_bound_email,
          'email_verification_sent_at', author_profile.email_verification_sent_at,
          'profile_edited_at', author_profile.profile_edited_at,
          'is_profile_complete', author_profile.is_profile_complete,
          'created_at', author_profile.created_at,
          'updated_at', author_profile.updated_at,
          'signed_avatar_url', null
        )
      end,
      'images', coalesce(images.images, '[]'::jsonb)
    )
    order by
      case when posts.pin_id is null then 0 else 1 end desc,
      coalesce(posts.pin_priority, -2147483648) desc,
      coalesce(posts.pin_starts_at, '-infinity'::timestamptz) desc,
      posts.created_at desc
  ), '[]'::jsonb)
  into result
  from ordered_posts posts
  left join public.profiles author_profile on author_profile.id = posts.author_id
  left join lateral (
    select jsonb_agg(
      jsonb_build_object(
        'id', post_images.id,
        'post_id', post_images.post_id,
        'path', post_images.path,
        'thumbnail_path', post_images.thumbnail_path,
        'sort_order', post_images.sort_order,
        'width', coalesce(post_images.full_width, post_images.width),
        'height', coalesce(post_images.full_height, post_images.height),
        'thumbnail_width', post_images.thumbnail_width,
        'thumbnail_height', post_images.thumbnail_height,
        'full_width', coalesce(post_images.full_width, post_images.width),
        'full_height', coalesce(post_images.full_height, post_images.height),
        'created_at', post_images.created_at,
        'signedURL', null,
        'thumbnail_url', null,
        'full_url', null
      )
      order by post_images.sort_order asc
    ) as images
    from public.post_images post_images
    where post_images.post_id = posts.id
  ) images on true;

  return jsonb_build_object(
    'generated_at', now(),
    'posts', coalesce(result, '[]'::jsonb)
  );
end;
$$;

create or replace function public.community_feed_v1(
  p_category text default null,
  p_search text default null,
  p_limit integer default 20,
  p_campus_id text default 'bjfu'
)
returns jsonb
language sql
stable
set search_path = public
as $$
  select private.community_feed_v1_impl(p_category, p_search, p_limit, p_campus_id);
$$;

create or replace function private.community_hot_posts_v1_impl(
  p_days integer default 7,
  p_limit integer default 10,
  p_campus_id text default 'bjfu'
)
returns jsonb
language plpgsql
security definer
stable
set search_path = public
as $$
declare
  current_profile_id uuid := public.current_profile_id();
  current_campus_id text := public.current_profile_campus_id();
  requested_campus_id text := nullif(btrim(coalesce(p_campus_id, '')), '');
  target_campus_id text := coalesce(current_campus_id, requested_campus_id, 'bjfu');
  safe_days integer := greatest(1, least(coalesce(p_days, 7), 90));
  safe_limit integer := greatest(1, least(coalesce(p_limit, 10), 10));
  result jsonb;
begin
  with ranked_posts as (
    select posts.*
    from public.posts posts
    where posts.campus_id = target_campus_id
      and posts.status = 'published'
      and posts.created_at >= now() - make_interval(days => safe_days)
      and (
        current_profile_id is null
        or not exists (
          select 1
          from public.community_blocks blocks
          where blocks.blocker_id = current_profile_id
            and blocks.blocked_id = posts.author_id
        )
      )
    order by
      (coalesce(posts.comment_count, 0) * 3 + coalesce(posts.like_count, 0) * 2) desc,
      posts.created_at desc
    limit safe_limit
  )
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', posts.id,
      'author_id', posts.author_id,
      'title', posts.title,
      'body', posts.body,
      'category', posts.category,
      'is_anonymous', posts.is_anonymous,
      'comment_count', posts.comment_count,
      'like_count', posts.like_count,
      'status', posts.status,
      'created_at', posts.created_at,
      'updated_at', posts.updated_at,
      'viewer_has_liked', exists (
        select 1
        from public.post_likes likes
        where likes.post_id = posts.id
          and likes.user_id = current_profile_id
      ),
      'viewer_has_favorited', exists (
        select 1
        from public.post_favorites favorites
        where favorites.post_id = posts.id
          and favorites.user_id = current_profile_id
      ),
      'pin', null,
      'author', case
        when author_profile.id is null then null
        else jsonb_build_object(
          'id', author_profile.id,
          'edu_id', author_profile.edu_id,
          'campus_id', author_profile.campus_id,
          'nickname', author_profile.nickname,
          'display_name', author_profile.display_name,
          'avatar_path', author_profile.avatar_path,
          'major', author_profile.major,
          'grade', author_profile.grade,
          'bound_email', author_profile.bound_email,
          'pending_bound_email', author_profile.pending_bound_email,
          'email_verification_sent_at', author_profile.email_verification_sent_at,
          'profile_edited_at', author_profile.profile_edited_at,
          'is_profile_complete', author_profile.is_profile_complete,
          'created_at', author_profile.created_at,
          'updated_at', author_profile.updated_at,
          'signed_avatar_url', null
        )
      end,
      'images', coalesce(images.images, '[]'::jsonb)
    )
    order by
      (coalesce(posts.comment_count, 0) * 3 + coalesce(posts.like_count, 0) * 2) desc,
      posts.created_at desc
  ), '[]'::jsonb)
  into result
  from ranked_posts posts
  left join public.profiles author_profile on author_profile.id = posts.author_id
  left join lateral (
    select jsonb_agg(
      jsonb_build_object(
        'id', post_images.id,
        'post_id', post_images.post_id,
        'path', post_images.path,
        'thumbnail_path', post_images.thumbnail_path,
        'sort_order', post_images.sort_order,
        'width', coalesce(post_images.full_width, post_images.width),
        'height', coalesce(post_images.full_height, post_images.height),
        'thumbnail_width', post_images.thumbnail_width,
        'thumbnail_height', post_images.thumbnail_height,
        'full_width', coalesce(post_images.full_width, post_images.width),
        'full_height', coalesce(post_images.full_height, post_images.height),
        'created_at', post_images.created_at,
        'signedURL', null,
        'thumbnail_url', null,
        'full_url', null
      )
      order by post_images.sort_order asc
    ) as images
    from public.post_images post_images
    where post_images.post_id = posts.id
  ) images on true;

  return jsonb_build_object(
    'generated_at', now(),
    'posts', coalesce(result, '[]'::jsonb)
  );
end;
$$;

create or replace function public.community_hot_posts_v1(
  p_days integer default 7,
  p_limit integer default 10,
  p_campus_id text default 'bjfu'
)
returns jsonb
language sql
stable
set search_path = public
as $$
  select private.community_hot_posts_v1_impl(p_days, p_limit, p_campus_id);
$$;

revoke all on function private.community_feed_v1_impl(text, text, integer, text) from public, anon, authenticated;
revoke all on function private.community_hot_posts_v1_impl(integer, integer, text) from public, anon, authenticated;
revoke all on function public.community_feed_v1(text, text, integer, text) from public, anon, authenticated;
revoke all on function public.community_hot_posts_v1(integer, integer, text) from public, anon, authenticated;
grant execute on function private.community_feed_v1_impl(text, text, integer, text) to authenticated, service_role;
grant execute on function private.community_hot_posts_v1_impl(integer, integer, text) to authenticated, service_role;
grant execute on function public.community_feed_v1(text, text, integer, text) to authenticated, service_role;
grant execute on function public.community_hot_posts_v1(integer, integer, text) to authenticated, service_role;

comment on table public.campuses is 'Campus registry for MyLeafy. Code identifiers and targets continue to use Leafy internally.';

select pg_notify('pgrst', 'reload schema');
