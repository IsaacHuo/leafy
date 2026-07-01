create extension if not exists pgcrypto;

create or replace function public.hash_timetable_invite_code(p_code text)
returns text
language sql
immutable
set search_path = public, extensions
as $$
  select encode(digest(public.normalize_timetable_invite_code(p_code), 'sha256'::text), 'hex');
$$;

select pg_notify('pgrst', 'reload schema');
