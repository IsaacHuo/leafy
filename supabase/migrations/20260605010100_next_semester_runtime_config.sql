update public.semester_runtime_configs
set
  is_active = false,
  updated_at = now()
where campus_id = 'bjfu'
  and is_active = true
  and semester_id <> '2026-2027-1';

insert into public.semester_runtime_configs (
  campus_id,
  semester_id,
  semester_start_date,
  supported_weeks,
  graduate_timetable_term_code,
  calendar_events,
  is_active
)
values (
  'bjfu',
  '2026-2027-1',
  date '2026-09-07',
  18,
  '47',
  '[]'::jsonb,
  true
)
on conflict (campus_id, semester_id) do update
set
  semester_start_date = excluded.semester_start_date,
  supported_weeks = excluded.supported_weeks,
  graduate_timetable_term_code = excluded.graduate_timetable_term_code,
  calendar_events = excluded.calendar_events,
  is_active = true,
  updated_at = now();

select pg_notify('pgrst', 'reload schema');
