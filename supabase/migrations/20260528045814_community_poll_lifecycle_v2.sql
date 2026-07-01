-- Community polls lifecycle v2.
-- Execute manually in Supabase after 20260528024930_community_polls_v1.sql.

alter table public.community_polls
  add column if not exists deletion_status text not null default 'none',
  add column if not exists deletion_requested_at timestamptz,
  add column if not exists deletion_reason text,
  add column if not exists deletion_reviewed_at timestamptz,
  add column if not exists deletion_reviewed_by uuid references public.admin_accounts (id) on delete set null on update cascade,
  add column if not exists deletion_review_reason text;

alter table public.community_polls
  drop constraint if exists community_polls_deletion_status_check;

alter table public.community_polls
  add constraint community_polls_deletion_status_check
  check (deletion_status in ('none', 'pending', 'approved', 'rejected'));

alter table public.community_polls
  drop constraint if exists community_polls_deletion_reason_length;

alter table public.community_polls
  add constraint community_polls_deletion_reason_length
  check (deletion_reason is null or char_length(deletion_reason) <= 300);

alter table public.community_polls
  drop constraint if exists community_polls_deletion_review_reason_length;

alter table public.community_polls
  add constraint community_polls_deletion_review_reason_length
  check (deletion_review_reason is null or char_length(deletion_review_reason) <= 300);

create index if not exists idx_community_polls_deletion_pending
on public.community_polls (deletion_requested_at desc)
where deletion_status = 'pending';

drop policy if exists "community_polls_update_self" on public.community_polls;
create policy "community_polls_update_self"
on public.community_polls
for update
to authenticated
using (false)
with check (false);

create or replace function private.community_poll_json_v2(
  p_poll public.community_polls,
  p_viewer_id uuid,
  p_redact_hidden boolean default false
)
returns jsonb
language sql
security definer
stable
set search_path = public
as $$
  select jsonb_build_object(
    'id', (p_poll).id,
    'author_id', (p_poll).author_id,
    'question', case when p_redact_hidden then '投票已下架' else (p_poll).question end,
    'detail', case when p_redact_hidden then null else (p_poll).detail end,
    'status', (p_poll).status,
    'total_vote_count', case when p_redact_hidden then 0 else (p_poll).total_vote_count end,
    'viewer_option_id', case when p_redact_hidden then null else viewer_vote.option_id end,
    'closes_at', case when p_redact_hidden then null else (p_poll).closes_at end,
    'deletion_status', (p_poll).deletion_status,
    'deletion_requested_at', (p_poll).deletion_requested_at,
    'deletion_reason', case
      when p_viewer_id is not null and public.can_use_profile((p_poll).author_id) then (p_poll).deletion_reason
      else null
    end,
    'deletion_reviewed_at', (p_poll).deletion_reviewed_at,
    'deletion_review_reason', case
      when p_viewer_id is not null and public.can_use_profile((p_poll).author_id) then (p_poll).deletion_review_reason
      else null
    end,
    'created_at', (p_poll).created_at,
    'updated_at', (p_poll).updated_at,
    'author', case
      when author_profile.id is null or p_redact_hidden then null
      else jsonb_build_object(
        'id', author_profile.id,
        'edu_id', author_profile.edu_id,
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
    'options', case when p_redact_hidden then '[]'::jsonb else coalesce(options.options, '[]'::jsonb) end
  )
  from public.community_polls polls
  left join public.profiles author_profile on author_profile.id = (p_poll).author_id
  left join public.community_poll_votes viewer_vote
    on viewer_vote.poll_id = (p_poll).id
   and viewer_vote.user_id = p_viewer_id
  left join lateral (
    select jsonb_agg(
      jsonb_build_object(
        'id', poll_options.id,
        'poll_id', poll_options.poll_id,
        'text', poll_options.text,
        'sort_order', poll_options.sort_order,
        'vote_count', poll_options.vote_count,
        'created_at', poll_options.created_at
      )
      order by poll_options.sort_order asc
    ) as options
    from public.community_poll_options poll_options
    where poll_options.poll_id = (p_poll).id
  ) options on true
  where polls.id = (p_poll).id;
$$;

create or replace function private.community_poll_summary_v1_impl(p_poll_id uuid)
returns jsonb
language plpgsql
security definer
stable
set search_path = public
as $$
declare
  current_profile_id uuid := public.current_profile_id();
  target_poll public.community_polls%rowtype;
begin
  select *
  into target_poll
  from public.community_polls polls
  where polls.id = p_poll_id
    and (
      polls.status = 'published'
      or public.can_use_profile(polls.author_id)
    );

  if not found then
    return null;
  end if;

  return private.community_poll_json_v2(target_poll, current_profile_id, false);
end;
$$;

create or replace function private.request_delete_community_poll_v1_impl(
  p_poll_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_profile_id uuid := public.current_profile_id();
  normalized_reason text := nullif(btrim(coalesce(p_reason, '')), '');
  target_poll public.community_polls%rowtype;
begin
  if current_profile_id is null then
    raise exception 'COMMUNITY_PROFILE_REQUIRED';
  end if;

  if normalized_reason is not null and char_length(normalized_reason) > 300 then
    raise exception 'COMMUNITY_POLL_INVALID';
  end if;

  select *
  into target_poll
  from public.community_polls
  where id = p_poll_id
    and author_id = current_profile_id
  for update;

  if not found or target_poll.status = 'deleted' then
    raise exception 'COMMUNITY_POLL_NOT_FOUND';
  end if;

  if target_poll.deletion_status = 'pending' then
    raise exception 'COMMUNITY_POLL_DELETION_PENDING';
  end if;

  update public.community_polls
  set
    deletion_status = 'pending',
    deletion_requested_at = now(),
    deletion_reason = normalized_reason,
    deletion_reviewed_at = null,
    deletion_reviewed_by = null,
    deletion_review_reason = null
  where id = p_poll_id
  returning * into target_poll;

  return private.community_poll_summary_v1_impl(target_poll.id);
end;
$$;

create or replace function public.request_delete_community_poll_v1(
  p_poll_id uuid,
  p_reason text default null
)
returns jsonb
language sql
set search_path = public
as $$
  select private.request_delete_community_poll_v1_impl(p_poll_id, p_reason);
$$;

create or replace function private.delete_own_community_poll_v1_impl(p_poll_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform private.request_delete_community_poll_v1_impl(p_poll_id, null);
end;
$$;

create or replace function public.delete_own_community_poll_v1(p_poll_id uuid)
returns void
language sql
set search_path = public
as $$
  select private.delete_own_community_poll_v1_impl(p_poll_id);
$$;

create or replace function private.my_authored_community_polls_v1_impl(p_limit integer default 30)
returns jsonb
language plpgsql
security definer
stable
set search_path = public
as $$
declare
  current_profile_id uuid := public.current_profile_id();
  safe_limit integer := greatest(1, least(coalesce(p_limit, 30), 50));
  result jsonb;
begin
  if current_profile_id is null then
    raise exception 'COMMUNITY_PROFILE_REQUIRED';
  end if;

  select coalesce(jsonb_agg(
    private.community_poll_json_v2(polls, current_profile_id, false)
    order by polls.created_at desc
  ), '[]'::jsonb)
  into result
  from (
    select *
    from public.community_polls
    where author_id = current_profile_id
    order by created_at desc
    limit safe_limit
  ) polls;

  return result;
end;
$$;

create or replace function public.my_authored_community_polls_v1(p_limit integer default 30)
returns jsonb
language sql
set search_path = public
as $$
  select private.my_authored_community_polls_v1_impl(p_limit);
$$;

create or replace function private.my_voted_community_polls_v1_impl(p_limit integer default 30)
returns jsonb
language plpgsql
security definer
stable
set search_path = public
as $$
declare
  current_profile_id uuid := public.current_profile_id();
  safe_limit integer := greatest(1, least(coalesce(p_limit, 30), 50));
  result jsonb;
begin
  if current_profile_id is null then
    raise exception 'COMMUNITY_PROFILE_REQUIRED';
  end if;

  select coalesce(jsonb_agg(
    private.community_poll_json_v2(polls, current_profile_id, polls.status = 'hidden')
    order by votes.updated_at desc
  ), '[]'::jsonb)
  into result
  from (
    select *
    from public.community_poll_votes
    where user_id = current_profile_id
    order by updated_at desc
    limit safe_limit
  ) votes
  join public.community_polls polls on polls.id = votes.poll_id
  where polls.status <> 'deleted'
    and (polls.status <> 'hidden' or polls.author_id <> current_profile_id);

  return result;
end;
$$;

create or replace function public.my_voted_community_polls_v1(p_limit integer default 30)
returns jsonb
language sql
set search_path = public
as $$
  select private.my_voted_community_polls_v1_impl(p_limit);
$$;

revoke all on function private.community_poll_json_v2(public.community_polls, uuid, boolean) from public, anon, authenticated;
revoke all on function private.request_delete_community_poll_v1_impl(uuid, text) from public, anon, authenticated;
revoke all on function private.my_authored_community_polls_v1_impl(integer) from public, anon, authenticated;
revoke all on function private.my_voted_community_polls_v1_impl(integer) from public, anon, authenticated;
revoke all on function public.request_delete_community_poll_v1(uuid, text) from public, anon, authenticated;
revoke all on function public.my_authored_community_polls_v1(integer) from public, anon, authenticated;
revoke all on function public.my_voted_community_polls_v1(integer) from public, anon, authenticated;

grant execute on function private.community_poll_json_v2(public.community_polls, uuid, boolean) to authenticated, service_role;
grant execute on function private.request_delete_community_poll_v1_impl(uuid, text) to authenticated, service_role;
grant execute on function private.my_authored_community_polls_v1_impl(integer) to authenticated, service_role;
grant execute on function private.my_voted_community_polls_v1_impl(integer) to authenticated, service_role;
grant execute on function public.request_delete_community_poll_v1(uuid, text) to authenticated;
grant execute on function public.my_authored_community_polls_v1(integer) to authenticated;
grant execute on function public.my_voted_community_polls_v1(integer) to authenticated;

select pg_notify('pgrst', 'reload schema');
