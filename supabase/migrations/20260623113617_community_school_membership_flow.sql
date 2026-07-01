alter table public.campus_membership_requests
  add column if not exists request_type text not null default 'initial_new_school',
  add column if not exists requested_campus_id text references public.campuses(id) on update cascade,
  add column if not exists from_campus_id text references public.campuses(id) on update cascade;

update public.campus_membership_requests
set request_type = 'initial_new_school'
where request_type is null or nullif(btrim(request_type), '') is null;

alter table public.campus_membership_requests
  drop constraint if exists campus_membership_requests_request_type_check;

alter table public.campus_membership_requests
  add constraint campus_membership_requests_request_type_check
  check (request_type in ('initial_new_school', 'school_change'));

alter table public.campus_membership_requests
  drop constraint if exists campus_membership_requests_request_shape;

alter table public.campus_membership_requests
  add constraint campus_membership_requests_request_shape
  check (
    (
      request_type = 'initial_new_school'
      and requested_campus_id is null
      and from_campus_id is null
    )
    or (
      request_type = 'school_change'
      and requested_campus_id is not null
      and from_campus_id is not null
    )
  );

with ranked_pending_requests as (
  select
    id,
    row_number() over (
      partition by requester_profile_id
      order by created_at desc, id desc
    ) as pending_rank
  from public.campus_membership_requests
  where status = 'pending'
)
update public.campus_membership_requests requests
set
  status = 'rejected',
  admin_note = coalesce(requests.admin_note, '已由更新的学校申请替代。'),
  reviewed_at = coalesce(requests.reviewed_at, now()),
  updated_at = now()
from ranked_pending_requests ranked
where requests.id = ranked.id
  and ranked.pending_rank > 1;

create unique index if not exists idx_campus_membership_requests_one_pending_per_profile
on public.campus_membership_requests (requester_profile_id)
where status = 'pending';

create or replace function public.community_campuses_v1(
  p_search text default null,
  p_limit integer default 20
)
returns table (
  id text,
  display_name text,
  short_name text
)
language sql
security definer
stable
set search_path = public
as $$
  select
    campuses.id,
    campuses.display_name,
    campuses.short_name
  from public.campuses campuses
  where auth.uid() is not null
    and campuses.status = 'active'
    and campuses.is_community_enabled = true
    and campuses.id not in ('general', 'bjfu')
    and (
      nullif(public.normalize_school_name(p_search), '') is null
      or campuses.normalized_name like '%' || public.normalize_school_name(p_search) || '%'
      or campuses.display_name ilike '%' || btrim(coalesce(p_search, '')) || '%'
      or campuses.short_name ilike '%' || btrim(coalesce(p_search, '')) || '%'
    )
  order by
    case
      when nullif(public.normalize_school_name(p_search), '') is not null
        and campuses.normalized_name = public.normalize_school_name(p_search)
      then 0
      when nullif(public.normalize_school_name(p_search), '') is not null
        and campuses.normalized_name like public.normalize_school_name(p_search) || '%'
      then 1
      else 2
    end,
    campuses.display_name
  limit least(greatest(coalesce(p_limit, 20), 1), 50);
$$;

create or replace function public.current_campus_membership_request()
returns public.campus_membership_requests
language sql
security definer
stable
set search_path = public
as $$
  select requests.*
  from public.campus_membership_requests requests
  where requests.requester_profile_id = public.current_profile_id()
    and requests.status = 'pending'
  order by requests.created_at desc
  limit 1;
$$;

create or replace function public.select_community_campus(p_campus_id text)
returns public.profiles
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_profile_id uuid := public.current_profile_id();
  actor_auth_user_id uuid := auth.uid();
  normalized_campus_id text := lower(btrim(coalesce(p_campus_id, '')));
  actor_profile public.profiles;
  target_campus public.campuses;
  updated_profile public.profiles;
begin
  perform set_config('app.community_membership_action', 'true', true);

  if actor_auth_user_id is null or actor_profile_id is null then
    raise exception 'COMMUNITY_AUTH_REQUIRED' using errcode = '42501';
  end if;

  if normalized_campus_id = '' or normalized_campus_id in ('general', 'bjfu') then
    raise exception 'COMMUNITY_CAMPUS_NOT_SELECTABLE' using errcode = '22023';
  end if;

  select *
  into actor_profile
  from public.profiles
  where id = actor_profile_id;

  if actor_profile.id is null then
    raise exception 'COMMUNITY_PROFILE_REQUIRED' using errcode = '42501';
  end if;

  if exists (
    select 1
    from public.campus_membership_requests requests
    where requests.requester_profile_id = actor_profile_id
      and requests.status = 'pending'
  ) then
    raise exception 'COMMUNITY_REQUEST_PENDING' using errcode = '23505';
  end if;

  if actor_profile.community_access_status = 'approved'
    and actor_profile.community_campus_id is not null
  then
    raise exception 'COMMUNITY_CAMPUS_ALREADY_SELECTED' using errcode = '23505';
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

  update public.profiles
  set
    campus_id = target_campus.id,
    community_campus_id = target_campus.id,
    community_access_status = 'approved',
    community_school_name = target_campus.display_name,
    community_rejection_reason = null,
    community_request_id = null,
    updated_at = now()
  where id = actor_profile_id
  returning * into updated_profile;

  update public.profile_auth_links
  set
    campus_id = target_campus.id,
    last_seen_at = now()
  where profile_id = actor_profile_id
    and auth_user_id = actor_auth_user_id;

  return updated_profile;
end;
$$;

create or replace function public.submit_community_school_change_request(p_campus_id text)
returns public.campus_membership_requests
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_profile_id uuid := public.current_profile_id();
  actor_auth_user_id uuid := auth.uid();
  normalized_campus_id text := lower(btrim(coalesce(p_campus_id, '')));
  actor_profile public.profiles;
  target_campus public.campuses;
  inserted_request public.campus_membership_requests;
begin
  perform set_config('app.community_membership_action', 'true', true);

  if actor_auth_user_id is null or actor_profile_id is null then
    raise exception 'COMMUNITY_AUTH_REQUIRED' using errcode = '42501';
  end if;

  if normalized_campus_id = '' or normalized_campus_id in ('general', 'bjfu') then
    raise exception 'COMMUNITY_CAMPUS_NOT_SELECTABLE' using errcode = '22023';
  end if;

  select *
  into actor_profile
  from public.profiles
  where id = actor_profile_id;

  if actor_profile.id is null
    or actor_profile.community_access_status is distinct from 'approved'
    or actor_profile.community_campus_id is null
  then
    raise exception 'COMMUNITY_APPROVED_CAMPUS_REQUIRED' using errcode = '42501';
  end if;

  if actor_profile.community_campus_id = normalized_campus_id then
    raise exception 'COMMUNITY_CAMPUS_UNCHANGED' using errcode = '22023';
  end if;

  if exists (
    select 1
    from public.campus_membership_requests requests
    where requests.requester_profile_id = actor_profile_id
      and requests.status = 'pending'
  ) then
    raise exception 'COMMUNITY_REQUEST_PENDING' using errcode = '23505';
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

  insert into public.campus_membership_requests (
    requester_profile_id,
    requester_auth_user_id,
    school_name,
    normalized_school_name,
    request_type,
    requested_campus_id,
    from_campus_id,
    status
  )
  values (
    actor_profile_id,
    actor_auth_user_id,
    target_campus.display_name,
    target_campus.normalized_name,
    'school_change',
    target_campus.id,
    actor_profile.community_campus_id,
    'pending'
  )
  returning * into inserted_request;

  update public.profiles
  set
    community_request_id = inserted_request.id,
    community_rejection_reason = null,
    updated_at = now()
  where id = actor_profile_id;

  return inserted_request;
end;
$$;

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
  actor_profile public.profiles;
  inserted_request public.campus_membership_requests;
begin
  perform set_config('app.community_membership_action', 'true', true);

  if actor_auth_user_id is null or actor_profile_id is null then
    raise exception 'COMMUNITY_AUTH_REQUIRED' using errcode = '42501';
  end if;

  if normalized_school_name is null or normalized_school_name = '' then
    raise exception 'COMMUNITY_SCHOOL_NAME_REQUIRED' using errcode = '22023';
  end if;

  select *
  into actor_profile
  from public.profiles
  where id = actor_profile_id;

  if actor_profile.id is null then
    raise exception 'COMMUNITY_PROFILE_REQUIRED' using errcode = '42501';
  end if;

  if actor_profile.community_access_status = 'approved'
    and actor_profile.community_campus_id is not null
  then
    raise exception 'COMMUNITY_CAMPUS_ALREADY_SELECTED' using errcode = '23505';
  end if;

  if exists (
    select 1
    from public.campus_membership_requests requests
    where requests.requester_profile_id = actor_profile_id
      and requests.status = 'pending'
  ) then
    raise exception 'COMMUNITY_REQUEST_PENDING' using errcode = '23505';
  end if;

  insert into public.campus_membership_requests (
    requester_profile_id,
    requester_auth_user_id,
    school_name,
    normalized_school_name,
    request_type,
    status
  )
  values (
    actor_profile_id,
    actor_auth_user_id,
    btrim(p_school_name),
    normalized_school_name,
    'initial_new_school',
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
    and status = 'pending'
  returning * into updated_request;

  if updated_request.id is null then
    raise exception 'COMMUNITY_REQUEST_NOT_FOUND' using errcode = '22023';
  end if;

  if updated_request.request_type = 'school_change'
    and updated_request.requested_campus_id is not null
    and updated_request.requested_campus_id is distinct from normalized_campus_id
  then
    raise exception 'COMMUNITY_CAMPUS_REQUEST_TARGET_MISMATCH' using errcode = '22023';
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
    and status = 'pending'
  returning * into updated_request;

  if updated_request.id is null then
    raise exception 'COMMUNITY_REQUEST_NOT_FOUND' using errcode = '22023';
  end if;

  if updated_request.request_type = 'school_change' then
    update public.profiles
    set
      community_request_id = null,
      community_rejection_reason = coalesce(updated_request.admin_note, '学校更换申请未通过。'),
      updated_at = now()
    where id = updated_request.requester_profile_id;
  else
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
  end if;

  return updated_request;
end;
$$;

revoke all on function public.community_campuses_v1(text, integer) from public, anon;
revoke all on function public.current_campus_membership_request() from public, anon;
revoke all on function public.select_community_campus(text) from public, anon;
revoke all on function public.submit_community_school_change_request(text) from public, anon;
grant execute on function public.community_campuses_v1(text, integer) to authenticated, service_role;
grant execute on function public.current_campus_membership_request() to authenticated, service_role;
grant execute on function public.select_community_campus(text) to authenticated, service_role;
grant execute on function public.submit_community_school_change_request(text) to authenticated, service_role;

select pg_notify('pgrst', 'reload schema');
