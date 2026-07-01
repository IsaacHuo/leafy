-- These tables were created after the project opted into explicit Data API
-- grants. The admin Edge Function uses service_role and needs direct access
-- for listing requests/campuses and creating an approved campus.
grant select, insert on table public.campuses to service_role;
grant select on table public.campus_membership_requests to service_role;

select pg_notify('pgrst', 'reload schema');
