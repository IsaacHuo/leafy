create extension if not exists pg_cron;

create or replace function public.leafy_semester_effective_date()
returns date
language sql
stable
set search_path = public
as $$
  select (now() at time zone 'Asia/Shanghai')::date;
$$;

revoke all on function public.leafy_semester_effective_date()
from public, anon, authenticated;

grant execute on function public.leafy_semester_effective_date()
to service_role;

create or replace function public.reconcile_semester_runtime_active_config(
  p_campus_id text default null,
  p_effective_date date default null
)
returns table (
  campus_id text,
  semester_id text,
  semester_start_date date,
  supported_weeks integer,
  is_active boolean
)
language plpgsql
set search_path = public
as $$
declare
  target_date date := coalesce(p_effective_date, public.leafy_semester_effective_date());
  target record;
begin
  perform set_config('leafy.semester_reconcile_running', 'true', true);

  for target in
    select distinct on (configs.campus_id)
      configs.id,
      configs.campus_id
    from public.semester_runtime_configs as configs
    where (p_campus_id is null or configs.campus_id = p_campus_id)
      and configs.semester_start_date <= target_date
    order by
      configs.campus_id,
      configs.semester_start_date desc,
      configs.updated_at desc
  loop
    update public.semester_runtime_configs as configs
    set
      is_active = false,
      updated_at = now()
    where configs.campus_id = target.campus_id
      and configs.is_active = true
      and configs.id <> target.id;

    update public.semester_runtime_configs as configs
    set
      is_active = true,
      updated_at = now()
    where configs.id = target.id
      and configs.is_active = false;
  end loop;

  perform set_config('leafy.semester_reconcile_running', 'false', true);

  return query
  select
    configs.campus_id,
    configs.semester_id,
    configs.semester_start_date,
    configs.supported_weeks,
    configs.is_active
  from public.semester_runtime_configs as configs
  where p_campus_id is null or configs.campus_id = p_campus_id
  order by configs.campus_id, configs.is_active desc, configs.semester_start_date desc;
end;
$$;

revoke all on function public.reconcile_semester_runtime_active_config(text, date)
from public, anon, authenticated;

grant execute on function public.reconcile_semester_runtime_active_config(text, date)
to service_role;

create or replace function public.semester_runtime_configs_prevent_future_active()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.is_active
     and new.semester_start_date > public.leafy_semester_effective_date() then
    new.is_active := false;
  end if;

  return new;
end;
$$;

revoke all on function public.semester_runtime_configs_prevent_future_active()
from public, anon, authenticated;

grant execute on function public.semester_runtime_configs_prevent_future_active()
to service_role;

drop trigger if exists semester_runtime_configs_prevent_future_active
on public.semester_runtime_configs;

create trigger semester_runtime_configs_prevent_future_active
before insert or update on public.semester_runtime_configs
for each row
execute function public.semester_runtime_configs_prevent_future_active();

create or replace function public.semester_runtime_configs_reconcile_active_after_write()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if current_setting('leafy.semester_reconcile_running', true) = 'true' then
    return null;
  end if;

  perform public.reconcile_semester_runtime_active_config(null, null);
  return null;
end;
$$;

revoke all on function public.semester_runtime_configs_reconcile_active_after_write()
from public, anon, authenticated;

grant execute on function public.semester_runtime_configs_reconcile_active_after_write()
to service_role;

drop trigger if exists semester_runtime_configs_reconcile_active_after_write
on public.semester_runtime_configs;

create trigger semester_runtime_configs_reconcile_active_after_write
after insert or update on public.semester_runtime_configs
for each statement
execute function public.semester_runtime_configs_reconcile_active_after_write();

select public.reconcile_semester_runtime_active_config(null, null);

do $$
begin
  if exists (
    select 1
    from cron.job
    where jobname = 'leafy-semester-runtime-reconcile'
  ) then
    perform cron.unschedule('leafy-semester-runtime-reconcile');
  end if;
end
$$;

select cron.schedule(
  'leafy-semester-runtime-reconcile',
  '5 16 * * *',
  $$select public.reconcile_semester_runtime_active_config(null, null);$$
);

select pg_notify('pgrst', 'reload schema');
