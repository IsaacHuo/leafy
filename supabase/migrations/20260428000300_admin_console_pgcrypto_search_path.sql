alter function public.admin_create_account(text, text, text, text, uuid)
set search_path = public, extensions;

alter function public.admin_update_account(uuid, uuid, text, text, text, text, boolean)
set search_path = public, extensions;

alter function public.admin_login(text, text, integer)
set search_path = public, extensions;

select pg_notify('pgrst', 'reload schema');
