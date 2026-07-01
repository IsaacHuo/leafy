-- Community polls v1.
-- Execute manually in Supabase before releasing the iOS poll UI.

create schema if not exists private;

revoke all on schema private from public, anon, authenticated;
grant usage on schema private to authenticated, service_role;

create table if not exists public.community_polls (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references public.profiles (id) on delete cascade on update cascade,
  question text not null,
  detail text,
  status text not null default 'pending_review' check (status in ('pending_review', 'published', 'hidden', 'deleted')),
  total_vote_count integer not null default 0 check (total_vote_count >= 0),
  closes_at timestamptz,
  moderated_by uuid references public.admin_accounts (id) on delete set null on update cascade,
  moderated_at timestamptz,
  moderation_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint community_polls_question_not_blank check (nullif(btrim(question), '') is not null),
  constraint community_polls_question_length check (char_length(question) <= 120),
  constraint community_polls_detail_length check (detail is null or char_length(detail) <= 500)
);

create table if not exists public.community_poll_options (
  id uuid primary key default gen_random_uuid(),
  poll_id uuid not null references public.community_polls (id) on delete cascade on update cascade,
  text text not null,
  sort_order integer not null default 0,
  vote_count integer not null default 0 check (vote_count >= 0),
  created_at timestamptz not null default now(),
  constraint community_poll_options_text_not_blank check (nullif(btrim(text), '') is not null),
  constraint community_poll_options_text_length check (char_length(text) <= 80),
  constraint community_poll_options_sort_order_nonnegative check (sort_order >= 0),
  unique (poll_id, sort_order)
);

create table if not exists public.community_poll_votes (
  poll_id uuid not null references public.community_polls (id) on delete cascade on update cascade,
  option_id uuid not null references public.community_poll_options (id) on delete cascade on update cascade,
  user_id uuid not null references public.profiles (id) on delete cascade on update cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (poll_id, user_id)
);

create index if not exists idx_community_polls_created_at
on public.community_polls (created_at desc)
where status in ('published', 'pending_review');

create index if not exists idx_community_polls_author_id
on public.community_polls (author_id, created_at desc);

create index if not exists idx_community_poll_options_poll_sort
on public.community_poll_options (poll_id, sort_order);

create index if not exists idx_community_poll_votes_user_created_at
on public.community_poll_votes (user_id, created_at desc);

create index if not exists idx_community_poll_votes_option_id
on public.community_poll_votes (option_id);

drop trigger if exists community_polls_set_updated_at on public.community_polls;
create trigger community_polls_set_updated_at
before update on public.community_polls
for each row
execute function public.set_updated_at();

drop trigger if exists community_poll_votes_set_updated_at on public.community_poll_votes;
create trigger community_poll_votes_set_updated_at
before update on public.community_poll_votes
for each row
execute function public.set_updated_at();

alter table public.community_polls enable row level security;
alter table public.community_poll_options enable row level security;
alter table public.community_poll_votes enable row level security;

drop policy if exists "community_polls_select_published" on public.community_polls;
create policy "community_polls_select_published"
on public.community_polls
for select
to authenticated
using (status = 'published' or public.can_use_profile(author_id));

drop policy if exists "community_polls_insert_self" on public.community_polls;
create policy "community_polls_insert_self"
on public.community_polls
for insert
to authenticated
with check (
  public.can_use_profile(author_id)
  and status = 'pending_review'
  and exists (
    select 1
    from public.profiles
    where profiles.id = community_polls.author_id
      and profiles.is_profile_complete = true
      and nullif(btrim(profiles.nickname), '') is not null
  )
);

drop policy if exists "community_polls_update_self" on public.community_polls;
create policy "community_polls_update_self"
on public.community_polls
for update
to authenticated
using (public.can_use_profile(author_id) and status <> 'deleted')
with check (public.can_use_profile(author_id) and status = 'deleted');

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
      and public.can_use_profile(polls.author_id)
  )
);

drop policy if exists "community_poll_votes_select_self" on public.community_poll_votes;
create policy "community_poll_votes_select_self"
on public.community_poll_votes
for select
to authenticated
using (public.can_use_profile(user_id));

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
      and polls.status = 'published'
      and (polls.closes_at is null or polls.closes_at > now())
  )
);

drop policy if exists "community_poll_votes_update_self" on public.community_poll_votes;
create policy "community_poll_votes_update_self"
on public.community_poll_votes
for update
to authenticated
using (public.can_use_profile(user_id))
with check (public.can_use_profile(user_id));

create or replace function public.enforce_community_poll_safety()
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

    if tg_op = 'INSERT' and new.status <> 'pending_review' then
      raise exception 'COMMUNITY_POLL_INVALID';
    end if;
  end if;

  if public.community_contains_objectionable_text(coalesce(new.question, '') || ' ' || coalesce(new.detail, '')) then
    raise exception 'COMMUNITY_CONTENT_REJECTED';
  end if;

  return new;
end;
$$;

drop trigger if exists community_polls_enforce_safety on public.community_polls;
create trigger community_polls_enforce_safety
before insert or update of question, detail, status on public.community_polls
for each row
execute function public.enforce_community_poll_safety();

create or replace function public.enforce_community_poll_option_safety()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.community_contains_objectionable_text(new.text) then
    raise exception 'COMMUNITY_CONTENT_REJECTED';
  end if;

  return new;
end;
$$;

drop trigger if exists community_poll_options_enforce_safety on public.community_poll_options;
create trigger community_poll_options_enforce_safety
before insert or update of text on public.community_poll_options
for each row
execute function public.enforce_community_poll_option_safety();

create or replace function public.enforce_community_poll_vote_option()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1
    from public.community_poll_options options
    where options.id = new.option_id
      and options.poll_id = new.poll_id
  ) then
    raise exception 'COMMUNITY_POLL_OPTION_NOT_FOUND';
  end if;

  return new;
end;
$$;

drop trigger if exists community_poll_votes_enforce_option on public.community_poll_votes;
create trigger community_poll_votes_enforce_option
before insert or update of option_id, poll_id on public.community_poll_votes
for each row
execute function public.enforce_community_poll_vote_option();

create or replace function private.community_poll_summary_v1_impl(p_poll_id uuid)
returns jsonb
language plpgsql
security definer
stable
set search_path = public
as $$
declare
  current_profile_id uuid := public.current_profile_id();
  result jsonb;
begin
  select jsonb_build_object(
    'id', polls.id,
    'author_id', polls.author_id,
    'question', polls.question,
    'detail', polls.detail,
    'status', polls.status,
    'total_vote_count', polls.total_vote_count,
    'viewer_option_id', viewer_vote.option_id,
    'closes_at', polls.closes_at,
    'created_at', polls.created_at,
    'updated_at', polls.updated_at,
    'author', case
      when author_profile.id is null then null
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
    'options', coalesce(options.options, '[]'::jsonb)
  )
  into result
  from public.community_polls polls
  left join public.profiles author_profile on author_profile.id = polls.author_id
  left join public.community_poll_votes viewer_vote
    on viewer_vote.poll_id = polls.id
   and viewer_vote.user_id = current_profile_id
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
    where poll_options.poll_id = polls.id
  ) options on true
  where polls.id = p_poll_id
    and polls.status <> 'deleted'
    and (
      polls.status = 'published'
      or public.can_use_profile(polls.author_id)
    );

  return result;
end;
$$;

create or replace function private.create_community_poll_v1_impl(
  p_question text,
  p_detail text default null,
  p_options text[] default '{}',
  p_closes_at timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_profile_id uuid := public.current_profile_id();
  normalized_question text := nullif(btrim(coalesce(p_question, '')), '');
  normalized_detail text := nullif(btrim(coalesce(p_detail, '')), '');
  normalized_options text[] := '{}';
  option_text text;
  created_poll_id uuid;
  option_index integer := 0;
begin
  if current_profile_id is null then
    raise exception 'COMMUNITY_PROFILE_REQUIRED';
  end if;

  if not exists (
    select 1
    from public.profiles
    where profiles.id = current_profile_id
      and profiles.is_profile_complete = true
      and nullif(btrim(profiles.nickname), '') is not null
  ) then
    raise exception 'PROFILE_COMPLETION_REQUIRED';
  end if;

  if not public.has_accepted_community_terms(public.community_latest_terms_version()) then
    raise exception 'COMMUNITY_TERMS_REQUIRED';
  end if;

  if public.is_profile_muted(current_profile_id) then
    raise exception 'COMMUNITY_USER_MUTED';
  end if;

  if normalized_question is null or char_length(normalized_question) > 120 then
    raise exception 'COMMUNITY_POLL_INVALID';
  end if;

  if normalized_detail is not null and char_length(normalized_detail) > 500 then
    raise exception 'COMMUNITY_POLL_INVALID';
  end if;

  if p_closes_at is not null and p_closes_at <= now() then
    raise exception 'COMMUNITY_POLL_INVALID';
  end if;

  foreach option_text in array coalesce(p_options, '{}') loop
    option_text := nullif(btrim(coalesce(option_text, '')), '');
    if option_text is not null then
      if char_length(option_text) > 80 then
        raise exception 'COMMUNITY_POLL_INVALID';
      end if;
      normalized_options := array_append(normalized_options, option_text);
    end if;
  end loop;

  if coalesce(array_length(normalized_options, 1), 0) < 2
     or coalesce(array_length(normalized_options, 1), 0) > 6 then
    raise exception 'COMMUNITY_POLL_INVALID';
  end if;

  insert into public.community_polls (author_id, question, detail, closes_at, status)
  values (current_profile_id, normalized_question, normalized_detail, p_closes_at, 'pending_review')
  returning id into created_poll_id;

  foreach option_text in array normalized_options loop
    insert into public.community_poll_options (poll_id, text, sort_order)
    values (created_poll_id, option_text, option_index);
    option_index := option_index + 1;
  end loop;

  return private.community_poll_summary_v1_impl(created_poll_id);
end;
$$;

create or replace function private.vote_community_poll_v1_impl(p_poll_id uuid, p_option_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_profile_id uuid := public.current_profile_id();
  target_poll public.community_polls%rowtype;
  existing_option_id uuid;
begin
  if current_profile_id is null then
    raise exception 'COMMUNITY_PROFILE_REQUIRED';
  end if;

  if not exists (
    select 1
    from public.profiles
    where profiles.id = current_profile_id
      and profiles.is_profile_complete = true
      and nullif(btrim(profiles.nickname), '') is not null
  ) then
    raise exception 'PROFILE_COMPLETION_REQUIRED';
  end if;

  if not public.has_accepted_community_terms(public.community_latest_terms_version()) then
    raise exception 'COMMUNITY_TERMS_REQUIRED';
  end if;

  select *
  into target_poll
  from public.community_polls
  where id = p_poll_id
    and status = 'published'
  for update;

  if not found then
    raise exception 'COMMUNITY_POLL_NOT_FOUND';
  end if;

  if target_poll.closes_at is not null and target_poll.closes_at <= now() then
    raise exception 'COMMUNITY_POLL_CLOSED';
  end if;

  if not exists (
    select 1
    from public.community_poll_options
    where id = p_option_id
      and poll_id = p_poll_id
  ) then
    raise exception 'COMMUNITY_POLL_OPTION_NOT_FOUND';
  end if;

  select option_id
  into existing_option_id
  from public.community_poll_votes
  where poll_id = p_poll_id
    and user_id = current_profile_id
  for update;

  if existing_option_id = p_option_id then
    return private.community_poll_summary_v1_impl(p_poll_id);
  end if;

  if existing_option_id is not null then
    update public.community_poll_options
    set vote_count = greatest(vote_count - 1, 0)
    where id = existing_option_id;
  else
    update public.community_polls
    set total_vote_count = total_vote_count + 1
    where id = p_poll_id;
  end if;

  update public.community_poll_options
  set vote_count = vote_count + 1
  where id = p_option_id;

  insert into public.community_poll_votes (poll_id, option_id, user_id, created_at, updated_at)
  values (p_poll_id, p_option_id, current_profile_id, now(), now())
  on conflict (poll_id, user_id) do update
  set
    option_id = excluded.option_id,
    updated_at = now();

  return private.community_poll_summary_v1_impl(p_poll_id);
end;
$$;

create or replace function private.delete_own_community_poll_v1_impl(p_poll_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_profile_id uuid := public.current_profile_id();
begin
  if current_profile_id is null then
    raise exception 'COMMUNITY_PROFILE_REQUIRED';
  end if;

  update public.community_polls
  set status = 'deleted'
  where id = p_poll_id
    and author_id = current_profile_id
    and status <> 'deleted';

  if not found then
    raise exception 'COMMUNITY_POLL_NOT_FOUND';
  end if;
end;
$$;

create or replace function public.create_community_poll_v1(
  p_question text,
  p_detail text default null,
  p_options text[] default '{}',
  p_closes_at timestamptz default null
)
returns jsonb
language sql
set search_path = public
as $$
  select private.create_community_poll_v1_impl(p_question, p_detail, p_options, p_closes_at);
$$;

create or replace function public.vote_community_poll_v1(p_poll_id uuid, p_option_id uuid)
returns jsonb
language sql
set search_path = public
as $$
  select private.vote_community_poll_v1_impl(p_poll_id, p_option_id);
$$;

create or replace function public.delete_own_community_poll_v1(p_poll_id uuid)
returns void
language sql
set search_path = public
as $$
  select private.delete_own_community_poll_v1_impl(p_poll_id);
$$;

revoke all privileges on table
  public.community_polls,
  public.community_poll_options,
  public.community_poll_votes
from public, anon, authenticated, service_role;

grant select on table public.community_polls to authenticated;
grant select on table public.community_poll_options to authenticated;
grant select on table public.community_poll_votes to authenticated;
grant select, insert, update, delete on table
  public.community_polls,
  public.community_poll_options,
  public.community_poll_votes
to service_role;

revoke all on function private.community_poll_summary_v1_impl(uuid) from public, anon, authenticated;
revoke all on function private.create_community_poll_v1_impl(text, text, text[], timestamptz) from public, anon, authenticated;
revoke all on function private.vote_community_poll_v1_impl(uuid, uuid) from public, anon, authenticated;
revoke all on function private.delete_own_community_poll_v1_impl(uuid) from public, anon, authenticated;
revoke all on function public.create_community_poll_v1(text, text, text[], timestamptz) from public, anon, authenticated;
revoke all on function public.vote_community_poll_v1(uuid, uuid) from public, anon, authenticated;
revoke all on function public.delete_own_community_poll_v1(uuid) from public, anon, authenticated;

grant execute on function private.community_poll_summary_v1_impl(uuid) to authenticated, service_role;
grant execute on function private.create_community_poll_v1_impl(text, text, text[], timestamptz) to authenticated, service_role;
grant execute on function private.vote_community_poll_v1_impl(uuid, uuid) to authenticated, service_role;
grant execute on function private.delete_own_community_poll_v1_impl(uuid) to authenticated, service_role;
grant execute on function public.create_community_poll_v1(text, text, text[], timestamptz) to authenticated;
grant execute on function public.vote_community_poll_v1(uuid, uuid) to authenticated;
grant execute on function public.delete_own_community_poll_v1(uuid) to authenticated;

select pg_notify('pgrst', 'reload schema');
