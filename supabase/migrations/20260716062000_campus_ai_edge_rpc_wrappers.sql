create or replace function public.edge_campus_ai_quota_snapshot(
  p_auth_user_id uuid,
  p_app_transaction_id text,
  p_now timestamptz default now()
)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select private.campus_ai_quota_snapshot(
    p_auth_user_id,
    p_app_transaction_id,
    p_now
  );
$$;

create or replace function public.edge_campus_ai_reserve_quota(
  p_request_uuid uuid,
  p_auth_user_id uuid,
  p_app_transaction_id text,
  p_campus_id text,
  p_now timestamptz default now()
)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select private.reserve_campus_ai_quota(
    p_request_uuid,
    p_auth_user_id,
    p_app_transaction_id,
    p_campus_id,
    p_now
  );
$$;

create or replace function public.edge_campus_ai_complete_usage(
  p_request_uuid uuid,
  p_status text,
  p_counted boolean,
  p_request_char_count integer default 0,
  p_response_char_count integer default 0,
  p_input_tokens integer default 0,
  p_input_cache_hit_tokens integer default 0,
  p_input_cache_miss_tokens integer default 0,
  p_output_tokens integer default 0,
  p_reasoning_tokens integer default 0,
  p_total_tokens integer default 0,
  p_estimated_cost_usd numeric default null,
  p_error_code text default null
)
returns void
language sql
security definer
set search_path = ''
as $$
  select private.complete_campus_ai_usage(
    p_request_uuid,
    p_status,
    p_counted,
    p_request_char_count,
    p_response_char_count,
    p_input_tokens,
    p_input_cache_hit_tokens,
    p_input_cache_miss_tokens,
    p_output_tokens,
    p_reasoning_tokens,
    p_total_tokens,
    p_estimated_cost_usd,
    p_error_code
  );
$$;

create or replace function public.edge_campus_ai_sync_entitlement(
  p_auth_user_id uuid,
  p_app_transaction_id text,
  p_product_id text default null,
  p_original_transaction_id text default null,
  p_transaction_id text default null,
  p_environment text default null,
  p_status text default 'free',
  p_current_period_start timestamptz default null,
  p_current_period_end timestamptz default null,
  p_notification_uuid text default null,
  p_signed_at timestamptz default null
)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select private.sync_campus_ai_entitlement(
    p_auth_user_id,
    p_app_transaction_id,
    p_product_id,
    p_original_transaction_id,
    p_transaction_id,
    p_environment,
    p_status,
    p_current_period_start,
    p_current_period_end,
    p_notification_uuid,
    p_signed_at
  );
$$;

revoke all on function public.edge_campus_ai_quota_snapshot(uuid, text, timestamptz)
  from public, anon, authenticated;
revoke all on function public.edge_campus_ai_reserve_quota(uuid, uuid, text, text, timestamptz)
  from public, anon, authenticated;
revoke all on function public.edge_campus_ai_complete_usage(uuid, text, boolean, integer, integer, integer, integer, integer, integer, integer, integer, numeric, text)
  from public, anon, authenticated;
revoke all on function public.edge_campus_ai_sync_entitlement(uuid, text, text, text, text, text, text, timestamptz, timestamptz, text, timestamptz)
  from public, anon, authenticated;

grant execute on function public.edge_campus_ai_quota_snapshot(uuid, text, timestamptz)
  to service_role;
grant execute on function public.edge_campus_ai_reserve_quota(uuid, uuid, text, text, timestamptz)
  to service_role;
grant execute on function public.edge_campus_ai_complete_usage(uuid, text, boolean, integer, integer, integer, integer, integer, integer, integer, integer, numeric, text)
  to service_role;
grant execute on function public.edge_campus_ai_sync_entitlement(uuid, text, text, text, text, text, text, timestamptz, timestamptz, text, timestamptz)
  to service_role;
