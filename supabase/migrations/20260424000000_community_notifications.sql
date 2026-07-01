create table if not exists public.community_notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references public.profiles (id) on delete cascade on update cascade,
  actor_id uuid references public.profiles (id) on delete set null on update cascade,
  post_id uuid references public.posts (id) on delete cascade on update cascade,
  comment_id uuid references public.comments (id) on delete cascade on update cascade,
  type text not null check (type in ('comment', 'like')),
  title text not null,
  body text,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists idx_community_notifications_recipient
on public.community_notifications (recipient_id, created_at desc);

create index if not exists idx_community_notifications_post_id
on public.community_notifications (post_id);

alter table public.community_notifications enable row level security;

drop policy if exists "community_notifications_select_recipient" on public.community_notifications;
create policy "community_notifications_select_recipient"
on public.community_notifications
for select
to authenticated
using (auth.uid() = recipient_id);

drop policy if exists "community_notifications_update_recipient" on public.community_notifications;
create policy "community_notifications_update_recipient"
on public.community_notifications
for update
to authenticated
using (auth.uid() = recipient_id)
with check (auth.uid() = recipient_id);

drop policy if exists "community_notifications_insert_actor" on public.community_notifications;
create policy "community_notifications_insert_actor"
on public.community_notifications
for insert
to authenticated
with check (
  auth.uid() = actor_id
  and recipient_id <> auth.uid()
  and exists (
    select 1
    from public.posts
    where posts.id = community_notifications.post_id
      and posts.author_id = community_notifications.recipient_id
      and posts.status = 'published'
  )
);

select pg_notify('pgrst', 'reload schema');
