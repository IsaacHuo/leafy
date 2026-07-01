create or replace function public.revoke_community_terms(p_terms_version text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_profile_id uuid := public.current_community_profile_id();
  revoked_version text := coalesce(nullif(btrim(p_terms_version), ''), public.community_latest_terms_version());
begin
  if current_profile_id is null then
    raise exception 'COMMUNITY_PROFILE_REQUIRED';
  end if;

  delete from public.community_terms_acceptances
  where user_id = current_profile_id
    and terms_version = revoked_version;
end;
$$;

revoke all on function public.revoke_community_terms(text) from public, anon, service_role;
grant execute on function public.revoke_community_terms(text) to authenticated;

select pg_notify('pgrst', 'reload schema');
