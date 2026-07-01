alter table public.community_notifications
  add column if not exists dismissed_at timestamptz;

create index if not exists idx_community_notifications_recipient_visible
on public.community_notifications (recipient_id, created_at desc)
where dismissed_at is null;

alter table public.site_announcement_reads
  add column if not exists dismissed_at timestamptz;

create table if not exists public.community_notification_settings (
  user_id uuid primary key references public.profiles (id) on delete cascade on update cascade,
  muted_all boolean not null default false,
  updated_at timestamptz not null default now()
);

drop trigger if exists community_notification_settings_set_updated_at on public.community_notification_settings;
create trigger community_notification_settings_set_updated_at
before update on public.community_notification_settings
for each row
execute function public.set_updated_at();

alter table public.community_notification_settings enable row level security;

drop policy if exists "community_notification_settings_select_self" on public.community_notification_settings;
create policy "community_notification_settings_select_self"
on public.community_notification_settings
for select
to authenticated
using (public.can_use_profile(user_id));

drop policy if exists "community_notification_settings_insert_self" on public.community_notification_settings;
create policy "community_notification_settings_insert_self"
on public.community_notification_settings
for insert
to authenticated
with check (public.can_use_profile(user_id));

drop policy if exists "community_notification_settings_update_self" on public.community_notification_settings;
create policy "community_notification_settings_update_self"
on public.community_notification_settings
for update
to authenticated
using (public.can_use_profile(user_id))
with check (public.can_use_profile(user_id));

create table if not exists public.feedback_submissions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.profiles (id) on delete set null on update cascade,
  issue_type text not null check (char_length(btrim(issue_type)) between 1 and 40),
  body text not null check (char_length(btrim(body)) between 1 and 4000),
  contact text,
  device_info jsonb not null default '{}'::jsonb,
  status text not null default 'open' check (status in ('open', 'reviewed', 'closed')),
  created_at timestamptz not null default now()
);

create index if not exists idx_feedback_submissions_created_at
on public.feedback_submissions (created_at desc);

alter table public.feedback_submissions enable row level security;

drop policy if exists "feedback_submissions_insert_authenticated" on public.feedback_submissions;
create policy "feedback_submissions_insert_authenticated"
on public.feedback_submissions
for insert
to authenticated
with check (user_id is null or public.can_use_profile(user_id));

drop policy if exists "site_announcement_reads_update_self" on public.site_announcement_reads;
create policy "site_announcement_reads_update_self"
on public.site_announcement_reads
for update
to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

create or replace function public.create_community_notification(
  p_recipient_id uuid,
  p_actor_id uuid,
  p_post_id uuid,
  p_comment_id uuid,
  p_type text,
  p_title text,
  p_body text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  created_notification_id uuid;
  recipient_muted boolean;
begin
  if auth.uid() is null then
    raise exception 'missing authenticated user';
  end if;

  if not public.can_use_profile(p_actor_id) then
    raise exception 'actor profile is not owned by current user';
  end if;

  if p_recipient_id = p_actor_id then
    return null;
  end if;

  if p_type not in ('comment', 'like') then
    raise exception 'invalid notification type';
  end if;

  if nullif(btrim(p_title), '') is null then
    raise exception 'notification title is required';
  end if;

  if not exists (
    select 1
    from public.posts
    where posts.id = p_post_id
      and posts.author_id = p_recipient_id
      and posts.status = 'published'
  ) then
    raise exception 'target post is not available';
  end if;

  if p_comment_id is not null and not exists (
    select 1
    from public.comments
    where comments.id = p_comment_id
      and comments.post_id = p_post_id
      and comments.author_id = p_actor_id
      and comments.status = 'published'
  ) then
    raise exception 'target comment is not available';
  end if;

  select coalesce(settings.muted_all, false)
  into recipient_muted
  from public.community_notification_settings settings
  where settings.user_id = p_recipient_id;

  if coalesce(recipient_muted, false) then
    return null;
  end if;

  insert into public.community_notifications (
    recipient_id,
    actor_id,
    post_id,
    comment_id,
    type,
    title,
    body
  )
  values (
    p_recipient_id,
    p_actor_id,
    p_post_id,
    p_comment_id,
    p_type,
    btrim(p_title),
    nullif(btrim(coalesce(p_body, '')), '')
  )
  returning id into created_notification_id;

  return created_notification_id;
end;
$$;

revoke all on function public.create_community_notification(uuid, uuid, uuid, uuid, text, text, text) from public;
grant execute on function public.create_community_notification(uuid, uuid, uuid, uuid, text, text, text) to authenticated;

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
    and status = 'published';

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

revoke all on function public.soft_delete_own_comment(uuid) from public;
grant execute on function public.soft_delete_own_comment(uuid) to authenticated;

select pg_notify('pgrst', 'reload schema');
