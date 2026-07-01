create table if not exists public.semester_runtime_configs (
  id uuid primary key default gen_random_uuid(),
  semester_id text not null,
  semester_start_date date not null,
  supported_weeks integer not null default 20,
  graduate_timetable_term_code text not null,
  calendar_events jsonb not null default '[]'::jsonb,
  is_active boolean not null default false,
  created_by uuid references public.admin_accounts (id) on delete set null on update cascade,
  updated_by uuid references public.admin_accounts (id) on delete set null on update cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint semester_runtime_configs_semester_not_blank
    check (nullif(btrim(semester_id), '') is not null),
  constraint semester_runtime_configs_graduate_term_not_blank
    check (nullif(btrim(graduate_timetable_term_code), '') is not null),
  constraint semester_runtime_configs_weeks_valid
    check (supported_weeks between 1 and 30),
  constraint semester_runtime_configs_calendar_events_array
    check (jsonb_typeof(calendar_events) = 'array'),
  constraint semester_runtime_configs_semester_unique
    unique (semester_id)
);

create unique index if not exists idx_semester_runtime_configs_single_active
on public.semester_runtime_configs (is_active)
where is_active = true;

drop trigger if exists semester_runtime_configs_set_updated_at on public.semester_runtime_configs;
create trigger semester_runtime_configs_set_updated_at
before update on public.semester_runtime_configs
for each row
execute function public.set_updated_at();

alter table public.semester_runtime_configs enable row level security;

drop policy if exists "semester_runtime_configs_select_active" on public.semester_runtime_configs;
create policy "semester_runtime_configs_select_active"
on public.semester_runtime_configs
for select
to anon, authenticated
using (is_active = true);

revoke all privileges on table public.semester_runtime_configs
from public, anon, authenticated, service_role;

grant select on table public.semester_runtime_configs
to anon, authenticated;

grant select, insert, update, delete on table public.semester_runtime_configs
to service_role;

insert into public.semester_runtime_configs (
  semester_id,
  semester_start_date,
  supported_weeks,
  graduate_timetable_term_code,
  calendar_events,
  is_active
)
values (
  '2025-2026-2',
  date '2026-03-09',
  20,
  '46',
  '[
    {"id":"qingming-2026","title":"清明","startDateString":"2026-04-04","endDateString":"2026-04-06","kind":"holiday"},
    {"id":"sports-2026","title":"运动会停课","startDateString":"2026-04-24","endDateString":"2026-04-24","kind":"closure"},
    {"id":"labor-2026","title":"五一","startDateString":"2026-05-01","endDateString":"2026-05-05","kind":"holiday"},
    {"id":"dragonboat-2026","title":"端午","startDateString":"2026-06-19","endDateString":"2026-06-21","kind":"holiday"}
  ]'::jsonb,
  true
)
on conflict (semester_id) do nothing;

comment on table public.semester_runtime_configs is 'Runtime semester rollover configuration consumed by the iOS app. Keep exactly one active row.';

select pg_notify('pgrst', 'reload schema');
