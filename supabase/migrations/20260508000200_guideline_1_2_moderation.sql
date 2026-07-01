alter table public.posts
  drop constraint if exists posts_status_check;

alter table public.posts
  add constraint posts_status_check
  check (status in ('published', 'deleted', 'hidden', 'pending_review'));

alter table public.comments
  drop constraint if exists comments_status_check;

alter table public.comments
  add constraint comments_status_check
  check (status in ('published', 'deleted', 'hidden', 'pending_review'));

create table if not exists public.community_terms_acceptances (
  user_id uuid not null references public.profiles (id) on delete cascade on update cascade,
  terms_version text not null,
  accepted_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  primary key (user_id, terms_version),
  constraint community_terms_acceptances_version_not_blank check (nullif(btrim(terms_version), '') is not null)
);

create index if not exists idx_community_terms_acceptances_user
on public.community_terms_acceptances (user_id, accepted_at desc);

alter table public.community_terms_acceptances enable row level security;

drop policy if exists "community_terms_acceptances_select_self" on public.community_terms_acceptances;
create policy "community_terms_acceptances_select_self"
on public.community_terms_acceptances
for select
to authenticated
using (public.can_use_profile(user_id));

drop policy if exists "community_terms_acceptances_insert_self" on public.community_terms_acceptances;
create policy "community_terms_acceptances_insert_self"
on public.community_terms_acceptances
for insert
to authenticated
with check (public.can_use_profile(user_id));

drop policy if exists "community_terms_acceptances_update_self" on public.community_terms_acceptances;
create policy "community_terms_acceptances_update_self"
on public.community_terms_acceptances
for update
to authenticated
using (public.can_use_profile(user_id))
with check (public.can_use_profile(user_id));

create table if not exists public.community_blocks (
  blocker_id uuid not null references public.profiles (id) on delete cascade on update cascade,
  blocked_id uuid not null references public.profiles (id) on delete cascade on update cascade,
  reason text,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  constraint community_blocks_no_self_block check (blocker_id <> blocked_id)
);

create index if not exists idx_community_blocks_blocker
on public.community_blocks (blocker_id, created_at desc);

create index if not exists idx_community_blocks_blocked
on public.community_blocks (blocked_id);

alter table public.community_blocks enable row level security;

drop policy if exists "community_blocks_select_self" on public.community_blocks;
create policy "community_blocks_select_self"
on public.community_blocks
for select
to authenticated
using (public.can_use_profile(blocker_id));

drop policy if exists "community_blocks_insert_self" on public.community_blocks;
create policy "community_blocks_insert_self"
on public.community_blocks
for insert
to authenticated
with check (public.can_use_profile(blocker_id));

drop policy if exists "community_blocks_delete_self" on public.community_blocks;
create policy "community_blocks_delete_self"
on public.community_blocks
for delete
to authenticated
using (public.can_use_profile(blocker_id));

create table if not exists public.community_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles (id) on delete cascade on update cascade,
  reported_user_id uuid references public.profiles (id) on delete set null on update cascade,
  target_type text not null check (target_type in ('post', 'comment', 'user')),
  post_id uuid references public.posts (id) on delete set null on update cascade,
  comment_id uuid references public.comments (id) on delete set null on update cascade,
  reason text not null check (char_length(btrim(reason)) between 1 and 80),
  detail text,
  status text not null default 'open' check (status in ('open', 'reviewed', 'resolved', 'rejected')),
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid references public.admin_accounts (id) on delete set null,
  resolution_note text,
  constraint community_reports_target_shape check (
    (target_type = 'post' and post_id is not null and comment_id is null)
    or (target_type = 'comment' and comment_id is not null)
    or (target_type = 'user' and reported_user_id is not null and post_id is null and comment_id is null)
  )
);

create index if not exists idx_community_reports_status_created
on public.community_reports (status, created_at desc);

create index if not exists idx_community_reports_reporter
on public.community_reports (reporter_id, created_at desc);

create index if not exists idx_community_reports_reported_user
on public.community_reports (reported_user_id, created_at desc);

alter table public.community_reports enable row level security;

drop policy if exists "community_reports_insert_self" on public.community_reports;
create policy "community_reports_insert_self"
on public.community_reports
for insert
to authenticated
with check (public.can_use_profile(reporter_id));

drop policy if exists "community_reports_select_self" on public.community_reports;
create policy "community_reports_select_self"
on public.community_reports
for select
to authenticated
using (public.can_use_profile(reporter_id));

drop policy if exists "posts_select_published_or_self" on public.posts;
drop policy if exists "posts_select_published" on public.posts;
create policy "posts_select_published_or_self"
on public.posts
for select
to authenticated
using (status = 'published' or public.can_use_profile(author_id));

drop policy if exists "comments_select_published_or_self" on public.comments;
drop policy if exists "comments_select_published" on public.comments;
create policy "comments_select_published_or_self"
on public.comments
for select
to authenticated
using (status = 'published' or public.can_use_profile(author_id));

drop policy if exists "posts_update_self" on public.posts;
create policy "posts_update_self"
on public.posts
for update
to authenticated
using (
  public.can_use_profile(author_id)
  and status in ('published', 'pending_review', 'hidden')
)
with check (
  public.can_use_profile(author_id)
  and status in ('published', 'pending_review', 'deleted')
);

create or replace function public.current_community_profile_id()
returns uuid
language plpgsql
security definer
stable
set search_path = public
as $$
declare
  linked_profile_id uuid;
begin
  if auth.uid() is null then
    return null;
  end if;

  select profile_id
  into linked_profile_id
  from public.profile_auth_links
  where auth_user_id = auth.uid()
  limit 1;

  return coalesce(linked_profile_id, auth.uid());
end;
$$;

grant execute on function public.current_community_profile_id() to authenticated;

create or replace function public.community_latest_terms_version()
returns text
language sql
stable
as $$
  select 'leafy-community-eula-2026-05-08'::text;
$$;

grant execute on function public.community_latest_terms_version() to authenticated;

create or replace function public.has_accepted_community_terms(p_terms_version text default null)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1
    from public.community_terms_acceptances
    where user_id = public.current_community_profile_id()
      and terms_version = coalesce(nullif(btrim(p_terms_version), ''), public.community_latest_terms_version())
  );
$$;

grant execute on function public.has_accepted_community_terms(text) to authenticated;

create or replace function public.accept_community_terms(p_terms_version text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_profile_id uuid := public.current_community_profile_id();
  accepted_version text := coalesce(nullif(btrim(p_terms_version), ''), public.community_latest_terms_version());
begin
  if current_profile_id is null then
    raise exception 'COMMUNITY_PROFILE_REQUIRED';
  end if;

  if not exists (select 1 from public.profiles where id = current_profile_id) then
    raise exception 'COMMUNITY_PROFILE_REQUIRED';
  end if;

  insert into public.community_terms_acceptances (user_id, terms_version, accepted_at)
  values (current_profile_id, accepted_version, now())
  on conflict (user_id, terms_version)
  do update set accepted_at = excluded.accepted_at;
end;
$$;

grant execute on function public.accept_community_terms(text) to authenticated;

create or replace function public.revoke_community_terms(p_terms_version text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_profile_id uuid := public.current_community_profile_id();
  revoked_version text := coalesce(nullif(btrim(p_terms_version), ''), public.community_latest_terms_version());
begin
  if current_profile_id is null then
    raise exception 'COMMUNITY_PROFILE_REQUIRED';
  end if;

  delete from public.community_terms_acceptances
  where user_id = current_profile_id
    and terms_version = revoked_version;
end;
$$;

grant execute on function public.revoke_community_terms(text) to authenticated;

create or replace function public.community_contains_objectionable_text(target_text text)
returns boolean
language plpgsql
immutable
as $$
declare
  normalized text := lower(coalesce(target_text, ''));
  pattern text;
  patterns text[] := array[
    '约炮', '裸聊', '黄片', '色情', '卖淫', '嫖娼', '援交',
    '开盒', '人肉搜索', '身份证号', '去死', '弄死', '杀了你',
    '自杀教程', '炸弹', '恐怖袭击', '毒品', '大麻', '冰毒',
    'fuck', 'porn', 'nude', 'kill yourself', 'terrorist', 'bomb',
    'doxx', 'doxxing', 'drug dealer'
  ];
begin
  foreach pattern in array patterns loop
    if normalized like '%' || pattern || '%' then
      return true;
    end if;
  end loop;

  return false;
end;
$$;

create or replace function public.enforce_community_post_safety()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is not null then
    if not public.has_accepted_community_terms(null) then
      raise exception 'COMMUNITY_TERMS_REQUIRED';
    end if;

    if public.is_profile_muted(new.author_id) then
      raise exception 'COMMUNITY_USER_MUTED';
    end if;

    if tg_op = 'INSERT' and new.status not in ('published', 'pending_review') then
      raise exception 'COMMUNITY_INVALID_POST_STATUS';
    end if;
  end if;

  if public.community_contains_objectionable_text(coalesce(new.title, '') || ' ' || coalesce(new.body, '')) then
    raise exception 'COMMUNITY_CONTENT_REJECTED';
  end if;

  return new;
end;
$$;

drop trigger if exists posts_enforce_community_safety on public.posts;
create trigger posts_enforce_community_safety
before insert or update of title, body, status on public.posts
for each row
execute function public.enforce_community_post_safety();

create or replace function public.enforce_community_comment_safety()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is not null then
    if not public.has_accepted_community_terms(null) then
      raise exception 'COMMUNITY_TERMS_REQUIRED';
    end if;

    if public.is_profile_muted(new.author_id) then
      raise exception 'COMMUNITY_USER_MUTED';
    end if;

    if tg_op = 'INSERT' and new.status not in ('published', 'pending_review') then
      raise exception 'COMMUNITY_INVALID_COMMENT_STATUS';
    end if;
  end if;

  if public.community_contains_objectionable_text(new.body) then
    raise exception 'COMMUNITY_CONTENT_REJECTED';
  end if;

  return new;
end;
$$;

drop trigger if exists comments_enforce_community_safety on public.comments;
create trigger comments_enforce_community_safety
before insert or update of body, status on public.comments
for each row
execute function public.enforce_community_comment_safety();

create or replace function public.report_community_content(
  p_target_type text,
  p_post_id uuid default null,
  p_comment_id uuid default null,
  p_reported_user_id uuid default null,
  p_reason text default '违规内容',
  p_detail text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_profile_id uuid := public.current_community_profile_id();
  target_author_id uuid;
  target_post_id uuid;
  created_report_id uuid;
  normalized_target_type text := lower(nullif(btrim(coalesce(p_target_type, '')), ''));
  normalized_reason text := coalesce(nullif(btrim(p_reason), ''), '违规内容');
begin
  if current_profile_id is null then
    raise exception 'COMMUNITY_PROFILE_REQUIRED';
  end if;

  if normalized_target_type = 'post' then
    select author_id into target_author_id
    from public.posts
    where id = p_post_id;

    if target_author_id is null then
      raise exception 'COMMUNITY_REPORT_TARGET_NOT_FOUND';
    end if;

    target_post_id := p_post_id;

    update public.posts
    set
      status = 'hidden',
      moderated_at = now(),
      moderation_reason = 'Hidden automatically after user report'
    where id = p_post_id
      and status = 'published';
  elsif normalized_target_type = 'comment' then
    select author_id, post_id into target_author_id, target_post_id
    from public.comments
    where id = p_comment_id;

    if target_author_id is null then
      raise exception 'COMMUNITY_REPORT_TARGET_NOT_FOUND';
    end if;

    update public.comments
    set
      status = 'hidden',
      moderated_at = now(),
      moderation_reason = 'Hidden automatically after user report'
    where id = p_comment_id
      and status = 'published';
  elsif normalized_target_type = 'user' then
    target_author_id := p_reported_user_id;
    if target_author_id is null or not exists (select 1 from public.profiles where id = target_author_id) then
      raise exception 'COMMUNITY_REPORT_TARGET_NOT_FOUND';
    end if;
  else
    raise exception 'COMMUNITY_INVALID_REPORT_TARGET';
  end if;

  insert into public.community_reports (
    reporter_id,
    reported_user_id,
    target_type,
    post_id,
    comment_id,
    reason,
    detail
  )
  values (
    current_profile_id,
    target_author_id,
    normalized_target_type,
    case when normalized_target_type = 'post' then p_post_id when normalized_target_type = 'comment' then target_post_id else null end,
    case when normalized_target_type = 'comment' then p_comment_id else null end,
    normalized_reason,
    nullif(btrim(coalesce(p_detail, '')), '')
  )
  returning id into created_report_id;

  return created_report_id;
end;
$$;

grant execute on function public.report_community_content(text, uuid, uuid, uuid, text, text) to authenticated;

create or replace function public.block_community_user(
  p_blocked_id uuid,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_profile_id uuid := public.current_community_profile_id();
begin
  if current_profile_id is null then
    raise exception 'COMMUNITY_PROFILE_REQUIRED';
  end if;

  if p_blocked_id is null or not exists (select 1 from public.profiles where id = p_blocked_id) then
    raise exception 'COMMUNITY_BLOCK_TARGET_NOT_FOUND';
  end if;

  if p_blocked_id = current_profile_id then
    raise exception 'COMMUNITY_CANNOT_BLOCK_SELF';
  end if;

  insert into public.community_blocks (blocker_id, blocked_id, reason, created_at)
  values (current_profile_id, p_blocked_id, nullif(btrim(coalesce(p_reason, '')), ''), now())
  on conflict (blocker_id, blocked_id)
  do update set
    reason = excluded.reason,
    created_at = excluded.created_at;
end;
$$;

grant execute on function public.block_community_user(uuid, text) to authenticated;

create or replace function public.unblock_community_user(p_blocked_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_profile_id uuid := public.current_community_profile_id();
begin
  if current_profile_id is null then
    raise exception 'COMMUNITY_PROFILE_REQUIRED';
  end if;

  delete from public.community_blocks
  where blocker_id = current_profile_id
    and blocked_id = p_blocked_id;
end;
$$;

grant execute on function public.unblock_community_user(uuid) to authenticated;

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
    and status in ('published', 'pending_review', 'hidden');

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

grant execute on function public.soft_delete_own_post(uuid) to authenticated;

create or replace function public.soft_delete_own_comment(target_comment_id uuid)
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

  update public.comments
  set
    status = 'deleted',
    updated_at = now()
  where id = target_comment_id
    and public.can_use_profile(author_id)
    and status in ('published', 'pending_review', 'hidden');

  get diagnostics affected_count = row_count;

  if affected_count = 0 then
    if exists (
      select 1
      from public.comments
      where id = target_comment_id
        and public.can_use_profile(author_id)
        and status = 'deleted'
    ) then
      return;
    end if;

    raise exception 'comment not found or not owned by current user';
  end if;
end;
$$;

grant execute on function public.soft_delete_own_comment(uuid) to authenticated;

select pg_notify('pgrst', 'reload schema');
