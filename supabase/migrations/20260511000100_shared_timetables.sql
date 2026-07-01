create extension if not exists pgcrypto;

create table if not exists public.timetable_snapshots (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles (id) on delete cascade on update cascade,
  semester_id text not null,
  courses jsonb not null default '[]'::jsonb,
  course_count integer not null default 0,
  published_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint timetable_snapshots_semester_not_blank check (nullif(btrim(semester_id), '') is not null),
  constraint timetable_snapshots_courses_array check (jsonb_typeof(courses) = 'array'),
  constraint timetable_snapshots_course_count_valid check (course_count >= 0),
  constraint timetable_snapshots_owner_semester_unique unique (owner_id, semester_id)
);

create index if not exists idx_timetable_snapshots_owner_published
on public.timetable_snapshots (owner_id, published_at desc);

create table if not exists public.timetable_invites (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles (id) on delete cascade on update cascade,
  semester_id text not null,
  code_hash text not null unique,
  expires_at timestamptz not null,
  accepted_by uuid references public.profiles (id) on delete set null on update cascade,
  accepted_at timestamptz,
  created_at timestamptz not null default now(),
  constraint timetable_invites_semester_not_blank check (nullif(btrim(semester_id), '') is not null),
  constraint timetable_invites_code_hash_not_blank check (nullif(btrim(code_hash), '') is not null)
);

create index if not exists idx_timetable_invites_owner_created
on public.timetable_invites (owner_id, created_at desc);

create table if not exists public.timetable_share_members (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles (id) on delete cascade on update cascade,
  viewer_id uuid not null references public.profiles (id) on delete cascade on update cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  revoked_at timestamptz,
  constraint timetable_share_members_not_self check (owner_id <> viewer_id),
  constraint timetable_share_members_owner_viewer_unique unique (owner_id, viewer_id)
);

create index if not exists idx_timetable_share_members_owner_active
on public.timetable_share_members (owner_id, created_at desc)
where revoked_at is null;

create index if not exists idx_timetable_share_members_viewer_active
on public.timetable_share_members (viewer_id, created_at desc)
where revoked_at is null;

drop trigger if exists timetable_snapshots_set_updated_at on public.timetable_snapshots;
create trigger timetable_snapshots_set_updated_at
before update on public.timetable_snapshots
for each row
execute function public.set_updated_at();

drop trigger if exists timetable_share_members_set_updated_at on public.timetable_share_members;
create trigger timetable_share_members_set_updated_at
before update on public.timetable_share_members
for each row
execute function public.set_updated_at();

create or replace function public.normalize_timetable_invite_code(p_code text)
returns text
language sql
immutable
as $$
  select upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z2-7]', '', 'g'));
$$;

create or replace function public.hash_timetable_invite_code(p_code text)
returns text
language sql
immutable
set search_path = public, extensions
as $$
  select encode(digest(public.normalize_timetable_invite_code(p_code), 'sha256'::text), 'hex');
$$;

create or replace function public.can_view_timetable_snapshot(target_owner_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select public.can_use_profile(target_owner_id)
    or exists (
      select 1
      from public.timetable_share_members members
      where members.owner_id = target_owner_id
        and members.viewer_id = public.current_profile_id()
        and members.revoked_at is null
    );
$$;

alter table public.timetable_snapshots enable row level security;
alter table public.timetable_invites enable row level security;
alter table public.timetable_share_members enable row level security;

drop policy if exists "timetable_snapshots_select_permitted" on public.timetable_snapshots;
create policy "timetable_snapshots_select_permitted"
on public.timetable_snapshots
for select
to authenticated
using (public.can_view_timetable_snapshot(owner_id));

drop policy if exists "timetable_snapshots_insert_owner" on public.timetable_snapshots;
create policy "timetable_snapshots_insert_owner"
on public.timetable_snapshots
for insert
to authenticated
with check (public.can_use_profile(owner_id));

drop policy if exists "timetable_snapshots_update_owner" on public.timetable_snapshots;
create policy "timetable_snapshots_update_owner"
on public.timetable_snapshots
for update
to authenticated
using (public.can_use_profile(owner_id))
with check (public.can_use_profile(owner_id));

drop policy if exists "timetable_snapshots_delete_owner" on public.timetable_snapshots;
create policy "timetable_snapshots_delete_owner"
on public.timetable_snapshots
for delete
to authenticated
using (public.can_use_profile(owner_id));

drop policy if exists "timetable_invites_select_owner" on public.timetable_invites;
create policy "timetable_invites_select_owner"
on public.timetable_invites
for select
to authenticated
using (public.can_use_profile(owner_id));

drop policy if exists "timetable_share_members_select_participant" on public.timetable_share_members;
create policy "timetable_share_members_select_participant"
on public.timetable_share_members
for select
to authenticated
using (
  public.can_use_profile(owner_id)
  or public.can_use_profile(viewer_id)
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
  normalized_code text;
  target_snapshot public.timetable_snapshots%rowtype;
  created_invite public.timetable_invites%rowtype;
begin
  actor_profile_id := public.current_profile_id();
  if actor_profile_id is null then
    raise exception 'MISSING_PROFILE';
  end if;

  select *
  into target_snapshot
  from public.timetable_snapshots snapshots
  where snapshots.owner_id = actor_profile_id
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
    owner_id,
    semester_id,
    code_hash,
    expires_at
  )
  values (
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
  normalized_code text;
  target_invite public.timetable_invites%rowtype;
  target_snapshot public.timetable_snapshots%rowtype;
begin
  actor_profile_id := public.current_profile_id();
  if actor_profile_id is null then
    raise exception 'MISSING_PROFILE';
  end if;

  normalized_code := public.normalize_timetable_invite_code(p_code);
  if char_length(normalized_code) <> 12 then
    raise exception 'INVALID_INVITE_CODE';
  end if;

  select *
  into target_invite
  from public.timetable_invites invites
  where invites.code_hash = public.hash_timetable_invite_code(normalized_code)
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
  limit 1;

  if target_snapshot.id is null then
    raise exception 'TIMETABLE_NOT_PUBLISHED';
  end if;

  insert into public.timetable_share_members (
    owner_id,
    viewer_id,
    revoked_at
  )
  values (
    target_invite.owner_id,
    actor_profile_id,
    null
  )
  on conflict on constraint timetable_share_members_owner_viewer_unique do update
  set
    revoked_at = null,
    updated_at = now();

  update public.timetable_invites
  set
    accepted_by = actor_profile_id,
    accepted_at = now()
  where timetable_invites.id = target_invite.id;

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

create or replace function public.revoke_timetable_share(p_owner_id uuid, p_viewer_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'MISSING_PROFILE';
  end if;

  if not public.can_use_profile(p_owner_id) then
    raise exception 'NOT_SHARE_OWNER';
  end if;

  update public.timetable_share_members
  set
    revoked_at = now(),
    updated_at = now()
  where owner_id = p_owner_id
    and viewer_id = p_viewer_id
    and revoked_at is null;
end;
$$;

create or replace function public.stop_timetable_sharing()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_profile_id uuid;
begin
  actor_profile_id := public.current_profile_id();
  if actor_profile_id is null then
    raise exception 'MISSING_PROFILE';
  end if;

  update public.timetable_share_members
  set
    revoked_at = now(),
    updated_at = now()
  where owner_id = actor_profile_id
    and revoked_at is null;

  update public.timetable_invites
  set expires_at = least(expires_at, now())
  where owner_id = actor_profile_id
    and accepted_by is null
    and expires_at > now();
end;
$$;

create or replace function public.leave_timetable_share(p_owner_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_profile_id uuid;
begin
  actor_profile_id := public.current_profile_id();
  if actor_profile_id is null then
    raise exception 'MISSING_PROFILE';
  end if;

  update public.timetable_share_members
  set
    revoked_at = now(),
    updated_at = now()
  where owner_id = p_owner_id
    and viewer_id = actor_profile_id
    and revoked_at is null;
end;
$$;

revoke all on function public.normalize_timetable_invite_code(text) from public;
revoke all on function public.hash_timetable_invite_code(text) from public;
revoke all on function public.can_view_timetable_snapshot(uuid) from public;
revoke all on function public.create_timetable_invite(text) from public;
revoke all on function public.accept_timetable_invite(text) from public;
revoke all on function public.revoke_timetable_share(uuid, uuid) from public;
revoke all on function public.stop_timetable_sharing() from public;
revoke all on function public.leave_timetable_share(uuid) from public;

grant execute on function public.can_view_timetable_snapshot(uuid) to authenticated;
grant execute on function public.create_timetable_invite(text) to authenticated;
grant execute on function public.accept_timetable_invite(text) to authenticated;
grant execute on function public.revoke_timetable_share(uuid, uuid) to authenticated;
grant execute on function public.stop_timetable_sharing() to authenticated;
grant execute on function public.leave_timetable_share(uuid) to authenticated;

select pg_notify('pgrst', 'reload schema');
