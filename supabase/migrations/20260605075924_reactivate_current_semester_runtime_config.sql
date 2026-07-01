begin;

update public.semester_runtime_configs
set
  is_active = false,
  updated_at = now()
where campus_id = 'bjfu'
  and is_active = true
  and semester_id <> '2025-2026-2';

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
on conflict (campus_id, semester_id) do update
set
  semester_start_date = excluded.semester_start_date,
  supported_weeks = excluded.supported_weeks,
  graduate_timetable_term_code = excluded.graduate_timetable_term_code,
  calendar_events = excluded.calendar_events,
  is_active = true,
  updated_at = now();

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
  false
)
on conflict (campus_id, semester_id) do update
set
  semester_start_date = excluded.semester_start_date,
  supported_weeks = excluded.supported_weeks,
  graduate_timetable_term_code = excluded.graduate_timetable_term_code,
  calendar_events = excluded.calendar_events,
  is_active = false,
  updated_at = now();

commit;

select pg_notify('pgrst', 'reload schema');
