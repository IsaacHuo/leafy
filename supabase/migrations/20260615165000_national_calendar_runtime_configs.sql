create table if not exists public.national_calendar_runtime_configs (
  id uuid primary key default gen_random_uuid(),
  year integer not null,
  holidays jsonb not null default '[]'::jsonb,
  solar_terms jsonb not null default '[]'::jsonb,
  is_active boolean not null default false,
  created_by uuid references public.admin_accounts (id) on delete set null on update cascade,
  updated_by uuid references public.admin_accounts (id) on delete set null on update cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint national_calendar_runtime_configs_year_valid
    check (year between 2000 and 2100),
  constraint national_calendar_runtime_configs_holidays_array
    check (jsonb_typeof(holidays) = 'array'),
  constraint national_calendar_runtime_configs_solar_terms_array
    check (jsonb_typeof(solar_terms) = 'array'),
  constraint national_calendar_runtime_configs_year_unique
    unique (year)
);

create unique index if not exists idx_national_calendar_runtime_configs_single_active
on public.national_calendar_runtime_configs (is_active)
where is_active = true;

drop trigger if exists national_calendar_runtime_configs_set_updated_at on public.national_calendar_runtime_configs;
create trigger national_calendar_runtime_configs_set_updated_at
before update on public.national_calendar_runtime_configs
for each row
execute function public.set_updated_at();

alter table public.national_calendar_runtime_configs enable row level security;

drop policy if exists "national_calendar_runtime_configs_select_active" on public.national_calendar_runtime_configs;
create policy "national_calendar_runtime_configs_select_active"
on public.national_calendar_runtime_configs
for select
to anon, authenticated
using (is_active = true);

revoke all privileges on table public.national_calendar_runtime_configs
from public, anon, authenticated, service_role;

grant select on table public.national_calendar_runtime_configs
to anon, authenticated;

grant select, insert, update, delete on table public.national_calendar_runtime_configs
to service_role;

insert into public.national_calendar_runtime_configs (
  year,
  holidays,
  solar_terms,
  is_active
)
values (
  2026,
  '[
    {"id":"new-year-2026","title":"元旦","startDateString":"2026-01-01","endDateString":"2026-01-03","kind":"holiday"},
    {"id":"spring-festival-2026","title":"春节","startDateString":"2026-02-15","endDateString":"2026-02-23","kind":"holiday"},
    {"id":"qingming-2026","title":"清明","startDateString":"2026-04-04","endDateString":"2026-04-06","kind":"holiday"},
    {"id":"labor-2026","title":"五一","startDateString":"2026-05-01","endDateString":"2026-05-05","kind":"holiday"},
    {"id":"dragonboat-2026","title":"端午","startDateString":"2026-06-19","endDateString":"2026-06-21","kind":"holiday"},
    {"id":"midautumn-2026","title":"中秋","startDateString":"2026-09-25","endDateString":"2026-09-27","kind":"holiday"},
    {"id":"national-day-2026","title":"国庆","startDateString":"2026-10-01","endDateString":"2026-10-07","kind":"holiday"}
  ]'::jsonb,
  '[
    {"id":"minor-cold-2026","title":"小寒","dateString":"2026-01-05"},
    {"id":"major-cold-2026","title":"大寒","dateString":"2026-01-20"},
    {"id":"start-spring-2026","title":"立春","dateString":"2026-02-04"},
    {"id":"rain-water-2026","title":"雨水","dateString":"2026-02-19"},
    {"id":"insects-awaken-2026","title":"惊蛰","dateString":"2026-03-05"},
    {"id":"spring-equinox-2026","title":"春分","dateString":"2026-03-20"},
    {"id":"pure-brightness-2026","title":"清明","dateString":"2026-04-04"},
    {"id":"grain-rain-2026","title":"谷雨","dateString":"2026-04-20"},
    {"id":"start-summer-2026","title":"立夏","dateString":"2026-05-05"},
    {"id":"grain-full-2026","title":"小满","dateString":"2026-05-21"},
    {"id":"grain-in-ear-2026","title":"芒种","dateString":"2026-06-05"},
    {"id":"summer-solstice-2026","title":"夏至","dateString":"2026-06-21"},
    {"id":"minor-heat-2026","title":"小暑","dateString":"2026-07-07"},
    {"id":"major-heat-2026","title":"大暑","dateString":"2026-07-23"},
    {"id":"start-autumn-2026","title":"立秋","dateString":"2026-08-07"},
    {"id":"limit-heat-2026","title":"处暑","dateString":"2026-08-23"},
    {"id":"white-dew-2026","title":"白露","dateString":"2026-09-07"},
    {"id":"autumn-equinox-2026","title":"秋分","dateString":"2026-09-23"},
    {"id":"cold-dew-2026","title":"寒露","dateString":"2026-10-08"},
    {"id":"frost-descent-2026","title":"霜降","dateString":"2026-10-23"},
    {"id":"start-winter-2026","title":"立冬","dateString":"2026-11-07"},
    {"id":"minor-snow-2026","title":"小雪","dateString":"2026-11-22"},
    {"id":"major-snow-2026","title":"大雪","dateString":"2026-12-07"},
    {"id":"winter-solstice-2026","title":"冬至","dateString":"2026-12-22"}
  ]'::jsonb,
  true
)
on conflict (year) do update
set
  holidays = excluded.holidays,
  solar_terms = excluded.solar_terms,
  is_active = true,
  updated_at = now();

comment on table public.national_calendar_runtime_configs is 'Global official national holiday and solar-term calendar consumed by the iOS app.';

select pg_notify('pgrst', 'reload schema');
