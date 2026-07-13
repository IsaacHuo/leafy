-- Keep tool event storage and implementation details in the private schema.
-- PostgREST only exposes configured schemas, so Edge Functions call these
-- service-role-only wrappers through the default public API schema.

create or replace function public.reserve_campus_ai_tool_call(
  p_auth_user_id uuid,
  p_request_uuid uuid,
  p_tool_name text,
  p_now timestamptz default now()
)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select private.reserve_campus_ai_tool_call(
    p_auth_user_id,
    p_request_uuid,
    p_tool_name,
    p_now
  );
$$;

create or replace function public.complete_campus_ai_tool_call(
  p_request_uuid uuid,
  p_status text,
  p_latency_ms integer,
  p_result_count integer,
  p_error_code text default null
)
returns void
language sql
security definer
set search_path = ''
as $$
  select private.complete_campus_ai_tool_call(
    p_request_uuid,
    p_status,
    p_latency_ms,
    p_result_count,
    p_error_code
  );
$$;

revoke all on function public.reserve_campus_ai_tool_call(uuid, uuid, text, timestamptz)
  from public, anon, authenticated;
revoke all on function public.complete_campus_ai_tool_call(uuid, text, integer, integer, text)
  from public, anon, authenticated;
grant execute on function public.reserve_campus_ai_tool_call(uuid, uuid, text, timestamptz)
  to service_role;
grant execute on function public.complete_campus_ai_tool_call(uuid, text, integer, integer, text)
  to service_role;
