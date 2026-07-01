create table if not exists public.admin_users (
  user_id uuid primary key references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.admin_users enable row level security;

create table if not exists public.site_announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(btrim(title)) between 1 and 120),
  body text not null check (char_length(btrim(body)) between 1 and 4000),
  level text not null default 'info' check (level in ('info', 'warning', 'urgent')),
  status text not null default 'draft' check (status in ('draft', 'published', 'archived')),
  published_at timestamptz,
  expires_at timestamptz,
  created_by uuid not null references auth.users (id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint site_announcements_published_at_required
    check (status <> 'published' or published_at is not null),
  constraint site_announcements_expiry_after_publish
    check (expires_at is null or published_at is null or expires_at > published_at)
);

create index if not exists idx_site_announcements_public_feed
on public.site_announcements (status, published_at desc);

create index if not exists idx_site_announcements_expires_at
on public.site_announcements (expires_at);

drop trigger if exists site_announcements_set_updated_at on public.site_announcements;
create trigger site_announcements_set_updated_at
before update on public.site_announcements
for each row
execute function public.set_updated_at();

alter table public.site_announcements enable row level security;

drop policy if exists "site_announcements_select_active" on public.site_announcements;
create policy "site_announcements_select_active"
on public.site_announcements
for select
to authenticated
using (
  status = 'published'
  and published_at <= now()
  and (expires_at is null or expires_at > now())
);

create table if not exists public.site_announcement_reads (
  announcement_id uuid not null references public.site_announcements (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  read_at timestamptz not null default now(),
  primary key (announcement_id, user_id)
);

create index if not exists idx_site_announcement_reads_user
on public.site_announcement_reads (user_id, read_at desc);

alter table public.site_announcement_reads enable row level security;

drop policy if exists "site_announcement_reads_select_self" on public.site_announcement_reads;
create policy "site_announcement_reads_select_self"
on public.site_announcement_reads
for select
to authenticated
using (auth.uid() = user_id);

drop policy if exists "site_announcement_reads_insert_self" on public.site_announcement_reads;
create policy "site_announcement_reads_insert_self"
on public.site_announcement_reads
for insert
to authenticated
with check (
  auth.uid() = user_id
  and exists (
    select 1
    from public.site_announcements
    where site_announcements.id = site_announcement_reads.announcement_id
      and site_announcements.status = 'published'
      and site_announcements.published_at <= now()
      and (site_announcements.expires_at is null or site_announcements.expires_at > now())
  )
);

comment on table public.admin_users is 'Users allowed to manage site-wide announcements. Insert the first super admin manually from the Supabase SQL console.';
comment on table public.site_announcements is 'Site-wide notifications shown in the iOS notification center.';
comment on table public.site_announcement_reads is 'Per-user read receipts for site-wide announcements.';

select pg_notify('pgrst', 'reload schema');
