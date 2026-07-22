-- Community profiles are durable school identities. Supabase Auth users are
-- replaceable device sessions and may all point at the same profile.

drop index if exists public.idx_profile_auth_links_profile_id_unique;
drop index if exists public.idx_profile_auth_links_campus_edu_id_unique;

create index if not exists idx_profile_auth_links_profile_id
on public.profile_auth_links (profile_id);

create index if not exists idx_profile_auth_links_campus_edu_id
on public.profile_auth_links (campus_id, edu_id);

-- Existing profile IDs and every business foreign key remain unchanged. New
-- profiles must not depend on the lifetime of the first anonymous Auth user.
alter table public.profiles
  drop constraint if exists profiles_id_fkey;

alter table public.profiles
  alter column id set default gen_random_uuid();

-- The previous hardening migration archived valid secondary device links.
-- Restore only links whose Auth user and profile still exist, whose archived
-- identity still matches the profile, and whose Auth user has not since been
-- linked to another profile. Audit rows are intentionally retained.
with restorable_links as (
  select distinct on (conflicts.auth_user_id)
    conflicts.auth_user_id,
    profiles.id as profile_id,
    profiles.campus_id,
    profiles.edu_id,
    conflicts.created_at,
    conflicts.last_seen_at
  from private.community_identity_link_conflicts conflicts
  join auth.users users
    on users.id = conflicts.auth_user_id
  join public.profiles profiles
    on profiles.id = conflicts.profile_id
   and profiles.campus_id = lower(btrim(conflicts.campus_id))
   and profiles.edu_id = btrim(conflicts.edu_id)
  left join public.profile_auth_links current_links
    on current_links.auth_user_id = conflicts.auth_user_id
  where current_links.auth_user_id is null
  order by conflicts.auth_user_id, conflicts.archived_at desc
)
insert into public.profile_auth_links (
  auth_user_id,
  profile_id,
  campus_id,
  edu_id,
  created_at,
  last_seen_at
)
select
  auth_user_id,
  profile_id,
  campus_id,
  edu_id,
  created_at,
  greatest(last_seen_at, now())
from restorable_links
on conflict (auth_user_id) do nothing;

create or replace function public.edge_claim_community_identity(
  p_auth_user_id uuid,
  p_campus_id text,
  p_edu_id text,
  p_display_name text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  normalized_campus_id text := coalesce(
    lower(nullif(btrim(coalesce(p_campus_id, '')), '')),
    'bjfu'
  );
  normalized_edu_id text := nullif(btrim(coalesce(p_edu_id, '')), '');
  normalized_display_name text := nullif(btrim(coalesce(p_display_name, '')), '');
  target_profile public.profiles%rowtype;
  is_new_user boolean := false;
begin
  if p_auth_user_id is null or not exists (select 1 from auth.users where id = p_auth_user_id) then
    raise exception 'COMMUNITY_AUTH_SESSION_REQUIRED';
  end if;

  if normalized_campus_id not in ('bjfu', 'general') then
    normalized_campus_id := 'general';
  end if;

  if normalized_edu_id is null then
    raise exception 'COMMUNITY_EDU_ID_REQUIRED';
  end if;

  normalized_display_name := coalesce(normalized_display_name, normalized_edu_id);

  -- Serialize first use across devices. The unique profile identity index is
  -- the final invariant; the lock avoids turning expected concurrency into an
  -- opaque unique-violation response.
  perform pg_advisory_xact_lock(
    hashtextextended(normalized_campus_id || ':' || normalized_edu_id, 0)
  );

  select * into target_profile
  from public.profiles
  where campus_id = normalized_campus_id
    and edu_id = normalized_edu_id;

  if not found then
    insert into public.profiles (
      campus_id,
      edu_id,
      nickname,
      display_name,
      community_campus_id,
      community_access_status,
      community_school_name,
      community_rejection_reason,
      is_profile_complete
    )
    values (
      normalized_campus_id,
      normalized_edu_id,
      '',
      normalized_display_name,
      case when normalized_campus_id = 'bjfu' then 'bjfu' else null end,
      case when normalized_campus_id = 'bjfu' then 'approved' else 'general' end,
      case when normalized_campus_id = 'bjfu' then '北京林业大学' else null end,
      null,
      false
    )
    returning * into target_profile;

    is_new_user := true;
  end if;

  -- One Auth user identifies at most one profile. Switching the local school
  -- account moves only this device link; it never mutates either profile or
  -- any content owned by those profiles.
  insert into public.profile_auth_links (
    auth_user_id,
    profile_id,
    campus_id,
    edu_id,
    last_seen_at
  )
  values (
    p_auth_user_id,
    target_profile.id,
    normalized_campus_id,
    normalized_edu_id,
    now()
  )
  on conflict (auth_user_id) do update
  set
    profile_id = excluded.profile_id,
    campus_id = excluded.campus_id,
    edu_id = excluded.edu_id,
    last_seen_at = excluded.last_seen_at;

  return jsonb_build_object(
    'profile_id', target_profile.id,
    'is_new_user', is_new_user
  );
end;
$$;

revoke all on function public.edge_claim_community_identity(uuid, text, text, text)
  from public, anon, authenticated;
grant execute on function public.edge_claim_community_identity(uuid, text, text, text)
  to service_role;

comment on function public.edge_claim_community_identity(uuid, text, text, text) is
  'Maps a replaceable device Auth session to the durable profile identified by campus_id and edu_id.';

select pg_notify('pgrst', 'reload schema');
