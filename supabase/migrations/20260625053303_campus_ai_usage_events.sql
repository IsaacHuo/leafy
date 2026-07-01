create schema if not exists private;

revoke all on schema private from public, anon, authenticated;
grant usage on schema private to authenticated, service_role;

create table if not exists private.campus_ai_usage_events (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid,
  campus_id text not null,
  provider text not null default 'deepseek',
  model text not null,
  status text not null,
  request_char_count integer not null default 0,
  response_char_count integer not null default 0,
  action_count integer not null default 0,
  error_code text,
  created_at timestamptz not null default now(),
  constraint campus_ai_usage_events_status_check
    check (status in ('success', 'error'))
);

create index if not exists campus_ai_usage_events_user_created_idx
  on private.campus_ai_usage_events (auth_user_id, created_at desc);

revoke all on table private.campus_ai_usage_events from public, anon, authenticated;
grant select, insert on table private.campus_ai_usage_events to service_role;
