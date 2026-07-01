create table if not exists public.community_post_pins (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts (id) on delete cascade on update cascade,
  scope text not null check (scope in ('global', 'category')),
  category text,
  priority integer not null default 0,
  starts_at timestamptz not null default now(),
  ends_at timestamptz,
  status text not null default 'active' check (status in ('active', 'inactive')),
  reason text,
  created_by uuid references public.admin_accounts (id) on delete set null on update cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint community_post_pins_scope_category_shape check (
    (scope = 'global' and category is null)
    or (scope = 'category' and nullif(btrim(category), '') is not null)
  ),
  constraint community_post_pins_time_range check (
    ends_at is null or ends_at > starts_at
  )
);

create unique index if not exists idx_community_post_pins_active_unique
on public.community_post_pins (post_id, scope, coalesce(category, ''))
where status = 'active';

create index if not exists idx_community_post_pins_active_lookup
on public.community_post_pins (scope, category, priority desc, starts_at desc)
where status = 'active';

create index if not exists idx_community_post_pins_post_id
on public.community_post_pins (post_id);

drop trigger if exists community_post_pins_set_updated_at on public.community_post_pins;
create trigger community_post_pins_set_updated_at
before update on public.community_post_pins
for each row
execute function public.set_updated_at();

alter table public.community_post_pins enable row level security;

drop policy if exists "community_post_pins_select_active_authenticated" on public.community_post_pins;
create policy "community_post_pins_select_active_authenticated"
on public.community_post_pins
for select
to authenticated
using (
  status = 'active'
  and starts_at <= now()
  and (ends_at is null or ends_at > now())
  and exists (
    select 1
    from public.posts
    where posts.id = community_post_pins.post_id
      and posts.status = 'published'
  )
);

revoke all privileges on table public.community_post_pins
from public, anon, authenticated, service_role;

grant select on table public.community_post_pins to authenticated;
grant select, insert, update, delete on table public.community_post_pins to service_role;

select pg_notify('pgrst', 'reload schema');
