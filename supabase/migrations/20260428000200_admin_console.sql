create extension if not exists pgcrypto;

create table if not exists public.admin_accounts (
  id uuid primary key default gen_random_uuid(),
  username text not null unique,
  password_hash text not null,
  display_name text not null,
  role text not null default 'super_admin',
  active boolean not null default true,
  last_login_at timestamptz,
  created_by uuid references public.admin_accounts (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint admin_accounts_username_format
    check (username ~ '^[a-z0-9_.-]{3,64}$'),
  constraint admin_accounts_display_name_not_blank
    check (nullif(btrim(display_name), '') is not null),
  constraint admin_accounts_role_check
    check (role in ('super_admin', 'operator', 'viewer'))
);

drop trigger if exists admin_accounts_set_updated_at on public.admin_accounts;
create trigger admin_accounts_set_updated_at
before update on public.admin_accounts
for each row
execute function public.set_updated_at();

create table if not exists public.admin_sessions (
  token_hash text primary key,
  admin_id uuid not null references public.admin_accounts (id) on delete cascade,
  expires_at timestamptz not null,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  constraint admin_sessions_token_hash_length check (char_length(token_hash) = 64),
  constraint admin_sessions_expiry_future check (expires_at > created_at)
);

create index if not exists idx_admin_sessions_admin_id
on public.admin_sessions (admin_id, created_at desc);

create index if not exists idx_admin_sessions_active
on public.admin_sessions (expires_at)
where revoked_at is null;

create table if not exists public.admin_audit_logs (
  id bigserial primary key,
  admin_id uuid references public.admin_accounts (id) on delete set null,
  action text not null,
  target_type text,
  target_id text,
  params jsonb not null default '{}'::jsonb,
  ip_address text,
  user_agent text,
  created_at timestamptz not null default now(),
  constraint admin_audit_logs_action_not_blank
    check (nullif(btrim(action), '') is not null)
);

create index if not exists idx_admin_audit_logs_created_at
on public.admin_audit_logs (created_at desc);

create index if not exists idx_admin_audit_logs_admin_id
on public.admin_audit_logs (admin_id, created_at desc);

alter table public.admin_accounts enable row level security;
alter table public.admin_sessions enable row level security;
alter table public.admin_audit_logs enable row level security;

create or replace function public.admin_create_account(
  p_username text,
  p_password text,
  p_display_name text default null,
  p_role text default 'super_admin',
  p_created_by uuid default null
)
returns table (
  id uuid,
  username text,
  display_name text,
  role text,
  active boolean,
  last_login_at timestamptz,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  normalized_username text;
  normalized_display_name text;
  normalized_role text;
  created_account_id uuid;
begin
  normalized_username := lower(btrim(coalesce(p_username, '')));
  normalized_display_name := coalesce(nullif(btrim(p_display_name), ''), normalized_username);
  normalized_role := coalesce(nullif(btrim(p_role), ''), 'super_admin');

  if normalized_username !~ '^[a-z0-9_.-]{3,64}$' then
    raise exception 'ADMIN_INVALID_USERNAME';
  end if;

  if char_length(coalesce(p_password, '')) < 8 then
    raise exception 'ADMIN_PASSWORD_TOO_SHORT';
  end if;

  if normalized_role not in ('super_admin', 'operator', 'viewer') then
    raise exception 'ADMIN_INVALID_ROLE';
  end if;

  if exists (select 1 from public.admin_accounts) then
    if not exists (
      select 1
      from public.admin_accounts
      where admin_accounts.id = p_created_by
        and admin_accounts.role = 'super_admin'
        and admin_accounts.active = true
    ) then
      raise exception 'ADMIN_SUPER_ADMIN_REQUIRED';
    end if;
  end if;

  insert into public.admin_accounts (
    username,
    password_hash,
    display_name,
    role,
    created_by
  )
  values (
    normalized_username,
    crypt(p_password, gen_salt('bf', 12)),
    normalized_display_name,
    normalized_role,
    p_created_by
  )
  returning admin_accounts.id into created_account_id;

  return query
  select
    a.id,
    a.username,
    a.display_name,
    a.role,
    a.active,
    a.last_login_at,
    a.created_at,
    a.updated_at
  from public.admin_accounts a
  where a.id = created_account_id;
end;
$$;

create or replace function public.admin_update_account(
  p_account_id uuid,
  p_actor_id uuid,
  p_username text default null,
  p_password text default null,
  p_display_name text default null,
  p_role text default null,
  p_active boolean default null
)
returns table (
  id uuid,
  username text,
  display_name text,
  role text,
  active boolean,
  last_login_at timestamptz,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  target_account public.admin_accounts%rowtype;
  normalized_username text;
  normalized_display_name text;
  normalized_role text;
  next_active boolean;
  next_role text;
begin
  if not exists (
    select 1
    from public.admin_accounts
    where admin_accounts.id = p_actor_id
      and admin_accounts.role = 'super_admin'
      and admin_accounts.active = true
  ) then
    raise exception 'ADMIN_SUPER_ADMIN_REQUIRED';
  end if;

  select *
  into target_account
  from public.admin_accounts
  where admin_accounts.id = p_account_id
  for update;

  if target_account.id is null then
    raise exception 'ADMIN_ACCOUNT_NOT_FOUND';
  end if;

  normalized_username := case
    when p_username is null then target_account.username
    else lower(btrim(p_username))
  end;
  normalized_display_name := case
    when p_display_name is null then target_account.display_name
    else coalesce(nullif(btrim(p_display_name), ''), normalized_username)
  end;
  normalized_role := case
    when p_role is null then target_account.role
    else btrim(p_role)
  end;
  next_active := coalesce(p_active, target_account.active);
  next_role := normalized_role;

  if normalized_username !~ '^[a-z0-9_.-]{3,64}$' then
    raise exception 'ADMIN_INVALID_USERNAME';
  end if;

  if normalized_role not in ('super_admin', 'operator', 'viewer') then
    raise exception 'ADMIN_INVALID_ROLE';
  end if;

  if p_password is not null and char_length(p_password) < 8 then
    raise exception 'ADMIN_PASSWORD_TOO_SHORT';
  end if;

  if p_account_id = p_actor_id and next_active = false then
    raise exception 'ADMIN_CANNOT_DISABLE_SELF';
  end if;

  if target_account.active = true
    and target_account.role = 'super_admin'
    and (next_active = false or next_role <> 'super_admin')
    and not exists (
      select 1
      from public.admin_accounts
      where admin_accounts.id <> target_account.id
        and admin_accounts.active = true
        and admin_accounts.role = 'super_admin'
    )
  then
    raise exception 'ADMIN_LAST_SUPER_ADMIN';
  end if;

  update public.admin_accounts
  set
    username = normalized_username,
    display_name = normalized_display_name,
    role = normalized_role,
    active = next_active,
    password_hash = case
      when p_password is null then password_hash
      else crypt(p_password, gen_salt('bf', 12))
    end
  where admin_accounts.id = target_account.id;

  return query
  select
    a.id,
    a.username,
    a.display_name,
    a.role,
    a.active,
    a.last_login_at,
    a.created_at,
    a.updated_at
  from public.admin_accounts a
  where a.id = target_account.id;
end;
$$;

create or replace function public.admin_login(
  p_username text,
  p_password text,
  p_expires_in_hours integer default 12
)
returns table (
  token text,
  expires_at timestamptz,
  admin_id uuid,
  username text,
  display_name text,
  role text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  account public.admin_accounts%rowtype;
  raw_token text;
  session_hash text;
  session_expires_at timestamptz;
begin
  select *
  into account
  from public.admin_accounts
  where admin_accounts.username = lower(btrim(coalesce(p_username, '')))
    and admin_accounts.active = true;

  if account.id is null
    or account.password_hash <> crypt(coalesce(p_password, ''), account.password_hash)
  then
    raise exception 'ADMIN_INVALID_CREDENTIALS';
  end if;

  raw_token := encode(gen_random_bytes(32), 'hex');
  session_hash := encode(digest(raw_token, 'sha256'), 'hex');
  session_expires_at := now() + make_interval(hours => greatest(1, least(coalesce(p_expires_in_hours, 12), 72)));

  insert into public.admin_sessions (
    token_hash,
    admin_id,
    expires_at
  )
  values (
    session_hash,
    account.id,
    session_expires_at
  );

  update public.admin_accounts
  set last_login_at = now()
  where admin_accounts.id = account.id;

  return query
  select
    raw_token,
    session_expires_at,
    account.id,
    account.username,
    account.display_name,
    account.role;
end;
$$;

revoke all on function public.admin_create_account(text, text, text, text, uuid) from public;
revoke all on function public.admin_update_account(uuid, uuid, text, text, text, text, boolean) from public;
revoke all on function public.admin_login(text, text, integer) from public;
grant execute on function public.admin_create_account(text, text, text, text, uuid) to service_role;
grant execute on function public.admin_update_account(uuid, uuid, text, text, text, text, boolean) to service_role;
grant execute on function public.admin_login(text, text, integer) to service_role;

alter table public.posts
  add column if not exists moderated_by uuid references public.admin_accounts (id) on delete set null,
  add column if not exists moderated_at timestamptz,
  add column if not exists moderation_reason text;

alter table public.posts
  drop constraint if exists posts_status_check;

alter table public.posts
  add constraint posts_status_check
  check (status in ('published', 'deleted', 'hidden'));

alter table public.comments
  add column if not exists moderated_by uuid references public.admin_accounts (id) on delete set null,
  add column if not exists moderated_at timestamptz,
  add column if not exists moderation_reason text;

alter table public.comments
  drop constraint if exists comments_status_check;

alter table public.comments
  add constraint comments_status_check
  check (status in ('published', 'deleted', 'hidden'));

alter table public.profiles
  add column if not exists muted_until timestamptz,
  add column if not exists muted_reason text,
  add column if not exists muted_by uuid references public.admin_accounts (id) on delete set null,
  add column if not exists muted_at timestamptz;

create index if not exists idx_profiles_muted_until
on public.profiles (muted_until)
where muted_until is not null;

create or replace function public.is_profile_muted(target_profile_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles
    where profiles.id = target_profile_id
      and profiles.muted_until is not null
      and profiles.muted_until > now()
  );
$$;

create or replace function public.enforce_community_author_not_muted()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.is_profile_muted(new.author_id) then
    raise exception 'COMMUNITY_USER_MUTED';
  end if;

  return new;
end;
$$;

drop trigger if exists posts_enforce_author_not_muted on public.posts;
create trigger posts_enforce_author_not_muted
before insert on public.posts
for each row
execute function public.enforce_community_author_not_muted();

drop trigger if exists comments_enforce_author_not_muted on public.comments;
create trigger comments_enforce_author_not_muted
before insert on public.comments
for each row
execute function public.enforce_community_author_not_muted();

grant execute on function public.is_profile_muted(uuid) to authenticated;

alter table public.teachers
  add column if not exists status text not null default 'published';

update public.teachers
set status = 'published'
where status is null;

alter table public.teachers
  drop constraint if exists teachers_status_check;

alter table public.teachers
  add constraint teachers_status_check
  check (status in ('published', 'hidden'));

drop policy if exists "teachers_select_authenticated" on public.teachers;
create policy "teachers_select_authenticated"
on public.teachers
for select
to authenticated
using (status = 'published');

alter table public.feedback_submissions
  add column if not exists admin_note text,
  add column if not exists reviewed_by uuid references public.admin_accounts (id) on delete set null,
  add column if not exists reviewed_at timestamptz,
  add column if not exists updated_at timestamptz not null default now();

drop trigger if exists feedback_submissions_set_updated_at on public.feedback_submissions;
create trigger feedback_submissions_set_updated_at
before update on public.feedback_submissions
for each row
execute function public.set_updated_at();

alter table public.site_announcements
  drop constraint if exists site_announcements_created_by_fkey;

alter table public.site_announcements
  add column if not exists updated_by uuid references public.admin_accounts (id) on delete set null;

select pg_notify('pgrst', 'reload schema');
