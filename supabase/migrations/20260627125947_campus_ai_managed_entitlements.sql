create schema if not exists private;

alter table private.campus_ai_usage_events
  add column if not exists request_uuid uuid,
  add column if not exists app_transaction_id text,
  add column if not exists plan_source text not null default 'free',
  add column if not exists quota_units integer not null default 0,
  add column if not exists input_tokens integer not null default 0,
  add column if not exists input_cache_hit_tokens integer not null default 0,
  add column if not exists input_cache_miss_tokens integer not null default 0,
  add column if not exists output_tokens integer not null default 0,
  add column if not exists reasoning_tokens integer not null default 0,
  add column if not exists total_tokens integer not null default 0,
  add column if not exists estimated_cost_usd numeric(12, 8),
  add column if not exists first_token_at timestamptz,
  add column if not exists completed_at timestamptz;

alter table private.campus_ai_usage_events
  drop constraint if exists campus_ai_usage_events_status_check;

alter table private.campus_ai_usage_events
  add constraint campus_ai_usage_events_status_check
    check (status in ('reserved', 'success', 'error'));

alter table private.campus_ai_usage_events
  drop constraint if exists campus_ai_usage_events_plan_source_check;

alter table private.campus_ai_usage_events
  add constraint campus_ai_usage_events_plan_source_check
    check (plan_source in ('free', 'subscription'));

create unique index if not exists campus_ai_usage_events_request_uuid_idx
  on private.campus_ai_usage_events (request_uuid)
  where request_uuid is not null;

create index if not exists campus_ai_usage_events_app_transaction_created_idx
  on private.campus_ai_usage_events (app_transaction_id, created_at desc)
  where app_transaction_id is not null;

create table if not exists private.campus_ai_entitlements (
  app_transaction_id text primary key,
  auth_user_id uuid,
  product_id text,
  original_transaction_id text,
  transaction_id text,
  environment text,
  status text not null default 'free',
  current_period_start timestamptz,
  current_period_end timestamptz,
  last_notification_uuid text,
  last_signed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint campus_ai_entitlements_status_check
    check (status in ('free', 'active', 'expired', 'refunded', 'revoked'))
);

create index if not exists campus_ai_entitlements_auth_user_idx
  on private.campus_ai_entitlements (auth_user_id);

revoke all on table private.campus_ai_entitlements from public, anon, authenticated;
grant select, insert, update on table private.campus_ai_entitlements to service_role;

create or replace function private.campus_ai_beijing_month_start(p_now timestamptz)
returns timestamptz
language sql
stable
as $$
  select date_trunc('month', p_now at time zone 'Asia/Shanghai') at time zone 'Asia/Shanghai';
$$;

create or replace function private.campus_ai_quota_snapshot(
  p_auth_user_id uuid,
  p_app_transaction_id text,
  p_now timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path = private, public
as $$
declare
  normalized_app_transaction_id text := nullif(btrim(p_app_transaction_id), '');
  active_entitlement private.campus_ai_entitlements%rowtype;
  plan_source text := 'free';
  quota_limit integer := 10;
  period_start timestamptz := private.campus_ai_beijing_month_start(p_now);
  period_end timestamptz := period_start + interval '1 month';
  used_count integer := 0;
begin
  if normalized_app_transaction_id is not null then
    select *
      into active_entitlement
      from private.campus_ai_entitlements
     where app_transaction_id = normalized_app_transaction_id
       and status = 'active'
       and current_period_end > p_now
     order by updated_at desc
     limit 1;
  elsif p_auth_user_id is not null then
    select *
      into active_entitlement
      from private.campus_ai_entitlements
     where auth_user_id = p_auth_user_id
       and status = 'active'
       and current_period_end > p_now
     order by updated_at desc
     limit 1;
  end if;

  if active_entitlement.app_transaction_id is not null then
    plan_source := 'subscription';
    quota_limit := 120;
    period_start := coalesce(active_entitlement.current_period_start, period_start);
    period_end := active_entitlement.current_period_end;
  end if;

  select count(*)::integer
    into used_count
    from private.campus_ai_usage_events usage
   where usage.plan_source = plan_source
     and usage.status in ('reserved', 'success')
     and usage.quota_units > 0
     and usage.created_at >= period_start
     and usage.created_at < period_end
     and (
       (normalized_app_transaction_id is not null and usage.app_transaction_id = normalized_app_transaction_id)
       or (normalized_app_transaction_id is null and usage.auth_user_id = p_auth_user_id)
     );

  return jsonb_build_object(
    'plan_source', plan_source,
    'limit', quota_limit,
    'used', used_count,
    'remaining', greatest(quota_limit - used_count, 0),
    'reset_at', to_char(period_end at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'status', case when plan_source = 'subscription' then 'active' else 'free' end
  );
end;
$$;

create or replace function private.reserve_campus_ai_quota(
  p_request_uuid uuid,
  p_auth_user_id uuid,
  p_app_transaction_id text,
  p_campus_id text,
  p_now timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path = private, public
as $$
declare
  normalized_app_transaction_id text := nullif(btrim(p_app_transaction_id), '');
  identity_key text := coalesce(normalized_app_transaction_id, p_auth_user_id::text);
  snapshot jsonb;
  used_count integer;
  quota_limit integer;
  hourly_count integer;
  selected_plan_source text;
  existing_event private.campus_ai_usage_events%rowtype;
begin
  if p_request_uuid is null or p_auth_user_id is null or identity_key is null then
    return jsonb_build_object('allowed', false, 'error', 'invalid_request');
  end if;

  perform pg_advisory_xact_lock(hashtext('campus-ai:' || identity_key));

  select *
    into existing_event
    from private.campus_ai_usage_events
   where request_uuid = p_request_uuid
   limit 1;

  if existing_event.id is not null then
    return jsonb_build_object(
      'allowed', existing_event.status <> 'error',
      'request_id', existing_event.request_uuid,
      'already_reserved', true,
      'quota', private.campus_ai_quota_snapshot(p_auth_user_id, normalized_app_transaction_id, p_now)
    );
  end if;

  snapshot := private.campus_ai_quota_snapshot(p_auth_user_id, normalized_app_transaction_id, p_now);
  used_count := (snapshot->>'used')::integer;
  quota_limit := (snapshot->>'limit')::integer;
  selected_plan_source := snapshot->>'plan_source';

  select count(*)::integer
    into hourly_count
    from private.campus_ai_usage_events usage
   where usage.status in ('reserved', 'success')
     and usage.quota_units > 0
     and usage.created_at >= p_now - interval '1 hour'
     and (
       (normalized_app_transaction_id is not null and usage.app_transaction_id = normalized_app_transaction_id)
       or (normalized_app_transaction_id is null and usage.auth_user_id = p_auth_user_id)
     );

  if hourly_count >= 30 then
    return jsonb_build_object(
      'allowed', false,
      'error', 'hourly_rate_limited',
      'quota', snapshot
    );
  end if;

  if used_count >= quota_limit then
    return jsonb_build_object(
      'allowed', false,
      'error', 'quota_exhausted',
      'quota', snapshot
    );
  end if;

  insert into private.campus_ai_usage_events (
    request_uuid,
    auth_user_id,
    app_transaction_id,
    campus_id,
    provider,
    model,
    plan_source,
    status,
    quota_units
  ) values (
    p_request_uuid,
    p_auth_user_id,
    normalized_app_transaction_id,
    coalesce(nullif(btrim(p_campus_id), ''), 'unknown'),
    'deepseek',
    'deepseek-v4-flash',
    selected_plan_source,
    'reserved',
    1
  );

  return jsonb_build_object(
    'allowed', true,
    'request_id', p_request_uuid,
    'already_reserved', false,
    'quota', private.campus_ai_quota_snapshot(p_auth_user_id, normalized_app_transaction_id, p_now)
  );
end;
$$;

create or replace function private.complete_campus_ai_usage(
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
language plpgsql
security definer
set search_path = private, public
as $$
begin
  update private.campus_ai_usage_events
     set status = case when p_status in ('success', 'error') then p_status else 'error' end,
         quota_units = case when p_counted then 1 else 0 end,
         request_char_count = greatest(coalesce(p_request_char_count, 0), 0),
         response_char_count = greatest(coalesce(p_response_char_count, 0), 0),
         input_tokens = greatest(coalesce(p_input_tokens, 0), 0),
         input_cache_hit_tokens = greatest(coalesce(p_input_cache_hit_tokens, 0), 0),
         input_cache_miss_tokens = greatest(coalesce(p_input_cache_miss_tokens, 0), 0),
         output_tokens = greatest(coalesce(p_output_tokens, 0), 0),
         reasoning_tokens = greatest(coalesce(p_reasoning_tokens, 0), 0),
         total_tokens = greatest(coalesce(p_total_tokens, 0), 0),
         estimated_cost_usd = p_estimated_cost_usd,
         error_code = p_error_code,
         first_token_at = case when p_counted then coalesce(first_token_at, now()) else first_token_at end,
         completed_at = now()
   where request_uuid = p_request_uuid;
end;
$$;

create or replace function private.sync_campus_ai_entitlement(
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
language plpgsql
security definer
set search_path = private, public
as $$
declare
  normalized_app_transaction_id text := nullif(btrim(p_app_transaction_id), '');
  normalized_status text := coalesce(nullif(btrim(p_status), ''), 'free');
begin
  if normalized_app_transaction_id is null then
    return jsonb_build_object('quota', private.campus_ai_quota_snapshot(p_auth_user_id, normalized_app_transaction_id));
  end if;

  if normalized_status not in ('free', 'active', 'expired', 'refunded', 'revoked') then
    normalized_status := 'free';
  end if;

  insert into private.campus_ai_entitlements (
    app_transaction_id,
    auth_user_id,
    product_id,
    original_transaction_id,
    transaction_id,
    environment,
    status,
    current_period_start,
    current_period_end,
    last_notification_uuid,
    last_signed_at
  ) values (
    normalized_app_transaction_id,
    p_auth_user_id,
    p_product_id,
    p_original_transaction_id,
    p_transaction_id,
    p_environment,
    normalized_status,
    p_current_period_start,
    p_current_period_end,
    p_notification_uuid,
    p_signed_at
  )
  on conflict (app_transaction_id) do update
    set auth_user_id = coalesce(excluded.auth_user_id, private.campus_ai_entitlements.auth_user_id),
        product_id = coalesce(excluded.product_id, private.campus_ai_entitlements.product_id),
        original_transaction_id = coalesce(excluded.original_transaction_id, private.campus_ai_entitlements.original_transaction_id),
        transaction_id = coalesce(excluded.transaction_id, private.campus_ai_entitlements.transaction_id),
        environment = coalesce(excluded.environment, private.campus_ai_entitlements.environment),
        status = excluded.status,
        current_period_start = coalesce(excluded.current_period_start, private.campus_ai_entitlements.current_period_start),
        current_period_end = coalesce(excluded.current_period_end, private.campus_ai_entitlements.current_period_end),
        last_notification_uuid = coalesce(excluded.last_notification_uuid, private.campus_ai_entitlements.last_notification_uuid),
        last_signed_at = coalesce(excluded.last_signed_at, private.campus_ai_entitlements.last_signed_at),
        updated_at = now();

  return jsonb_build_object(
    'quota', private.campus_ai_quota_snapshot(p_auth_user_id, normalized_app_transaction_id)
  );
end;
$$;

revoke all on function private.campus_ai_beijing_month_start(timestamptz) from public, anon, authenticated;
revoke all on function private.campus_ai_quota_snapshot(uuid, text, timestamptz) from public, anon, authenticated;
revoke all on function private.reserve_campus_ai_quota(uuid, uuid, text, text, timestamptz) from public, anon, authenticated;
revoke all on function private.complete_campus_ai_usage(uuid, text, boolean, integer, integer, integer, integer, integer, integer, integer, integer, numeric, text) from public, anon, authenticated;
revoke all on function private.sync_campus_ai_entitlement(uuid, text, text, text, text, text, text, timestamptz, timestamptz, text, timestamptz) from public, anon, authenticated;

grant execute on function private.campus_ai_quota_snapshot(uuid, text, timestamptz) to service_role;
grant execute on function private.reserve_campus_ai_quota(uuid, uuid, text, text, timestamptz) to service_role;
grant execute on function private.complete_campus_ai_usage(uuid, text, boolean, integer, integer, integer, integer, integer, integer, integer, integer, numeric, text) to service_role;
grant execute on function private.sync_campus_ai_entitlement(uuid, text, text, text, text, text, text, timestamptz, timestamptz, text, timestamptz) to service_role;
