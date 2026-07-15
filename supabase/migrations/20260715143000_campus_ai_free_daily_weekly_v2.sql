create or replace function private.campus_ai_beijing_day_start(p_now timestamptz)
returns timestamptz
language sql
stable
as $$
  select date_trunc('day', p_now at time zone 'Asia/Shanghai') at time zone 'Asia/Shanghai';
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
  daily_limit integer := 10;
  daily_start timestamptz := private.campus_ai_beijing_day_start(p_now);
  daily_end timestamptz := daily_start + interval '1 day';
  daily_used integer := 0;
  period_limit integer := null;
  period_start timestamptz := null;
  period_end timestamptz := null;
  period_used integer := null;
  effective_remaining integer := 0;
begin
  if normalized_app_transaction_id is not null then
    select *
      into active_entitlement
      from private.campus_ai_entitlements
     where app_transaction_id = normalized_app_transaction_id
       and status = 'active'
       and product_id = 'com.isaachuo.leafy.ai.weekly.v2'
       and current_period_start <= p_now
       and current_period_end > p_now
     order by updated_at desc
     limit 1;
  elsif p_auth_user_id is not null then
    select *
      into active_entitlement
      from private.campus_ai_entitlements
     where auth_user_id = p_auth_user_id
       and status = 'active'
       and product_id = 'com.isaachuo.leafy.ai.weekly.v2'
       and current_period_start <= p_now
       and current_period_end > p_now
     order by updated_at desc
     limit 1;
  end if;

  if active_entitlement.app_transaction_id is not null then
    plan_source := 'subscription';
    daily_limit := 40;
    period_limit := 120;
    period_start := active_entitlement.current_period_start;
    period_end := active_entitlement.current_period_end;
  end if;

  select count(*)::integer
    into daily_used
    from private.campus_ai_usage_events usage
   where usage.status in ('reserved', 'success')
     and usage.quota_units > 0
     and usage.created_at >= daily_start
     and usage.created_at < daily_end
     and (
       (normalized_app_transaction_id is not null and usage.app_transaction_id = normalized_app_transaction_id)
       or (normalized_app_transaction_id is null and usage.auth_user_id = p_auth_user_id)
     );

  if plan_source = 'subscription' then
    select count(*)::integer
      into period_used
      from private.campus_ai_usage_events usage
     where usage.plan_source = 'subscription'
       and usage.status in ('reserved', 'success')
       and usage.quota_units > 0
       and usage.created_at >= period_start
       and usage.created_at < period_end
       and (
         (normalized_app_transaction_id is not null and usage.app_transaction_id = normalized_app_transaction_id)
         or (normalized_app_transaction_id is null and usage.auth_user_id = p_auth_user_id)
       );
    effective_remaining := least(
      greatest(daily_limit - daily_used, 0),
      greatest(period_limit - period_used, 0)
    );
  else
    effective_remaining := greatest(daily_limit - daily_used, 0);
  end if;

  return jsonb_strip_nulls(jsonb_build_object(
    'plan_source', plan_source,
    'limit', case when plan_source = 'subscription' then period_limit else daily_limit end,
    'used', case when plan_source = 'subscription' then period_used else daily_used end,
    'remaining', effective_remaining,
    'reset_at', to_char(
      (case when plan_source = 'subscription' then period_end else daily_end end) at time zone 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
    ),
    'status', case when plan_source = 'subscription' then 'active' else 'free' end,
    'daily_limit', daily_limit,
    'daily_used', daily_used,
    'daily_remaining', greatest(daily_limit - daily_used, 0),
    'daily_reset_at', to_char(daily_end at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'period_limit', period_limit,
    'period_used', period_used,
    'period_remaining', case when period_limit is null then null else greatest(period_limit - period_used, 0) end,
    'period_reset_at', case when period_end is null then null else to_char(period_end at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') end
  ));
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
  selected_plan_source text;
  existing_event private.campus_ai_usage_events%rowtype;
begin
  if p_request_uuid is null or p_auth_user_id is null or identity_key is null then
    return jsonb_build_object('allowed', false, 'error', 'invalid_request');
  end if;

  perform pg_advisory_xact_lock(hashtext('campus-ai:' || identity_key));

  select * into existing_event
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
  selected_plan_source := snapshot->>'plan_source';

  if (snapshot->>'daily_remaining')::integer <= 0 then
    return jsonb_build_object(
      'allowed', false,
      'error', 'daily_quota_exhausted',
      'quota', snapshot
    );
  end if;

  if selected_plan_source = 'subscription'
     and coalesce((snapshot->>'period_remaining')::integer, 0) <= 0 then
    return jsonb_build_object(
      'allowed', false,
      'error', 'period_quota_exhausted',
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

revoke all on function private.campus_ai_beijing_day_start(timestamptz) from public, anon, authenticated;
revoke all on function private.campus_ai_quota_snapshot(uuid, text, timestamptz) from public, anon, authenticated;
revoke all on function private.reserve_campus_ai_quota(uuid, uuid, text, text, timestamptz) from public, anon, authenticated;

grant execute on function private.campus_ai_quota_snapshot(uuid, text, timestamptz) to service_role;
grant execute on function private.reserve_campus_ai_quota(uuid, uuid, text, text, timestamptz) to service_role;
