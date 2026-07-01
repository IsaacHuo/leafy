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

revoke all on function public.accept_timetable_invite(text) from public;
grant execute on function public.accept_timetable_invite(text) to authenticated;

select pg_notify('pgrst', 'reload schema');
