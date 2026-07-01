-- Opt in to Supabase's explicit Data API grant model.
-- Grants decide whether PostgREST can reach an object; RLS still decides row access.

revoke all privileges on table
  public.admin_accounts,
  public.admin_audit_logs,
  public.admin_sessions,
  public.admin_users,
  public.comments,
  public.community_blocks,
  public.community_notification_settings,
  public.community_notifications,
  public.community_reports,
  public.community_terms_acceptances,
  public.feedback_submissions,
  public.post_images,
  public.post_likes,
  public.posts,
  public.profile_auth_links,
  public.profiles,
  public.site_announcement_reads,
  public.site_announcements,
  public.teacher_ratings,
  public.teachers,
  public.timetable_invites,
  public.timetable_share_members,
  public.timetable_snapshots
from public, anon, authenticated, service_role;

grant select, insert, update on table
  public.profiles,
  public.posts,
  public.comments,
  public.community_notifications,
  public.community_notification_settings,
  public.site_announcement_reads,
  public.teacher_ratings,
  public.community_terms_acceptances
to authenticated;

grant select, insert, delete on table
  public.post_images,
  public.post_likes,
  public.community_blocks
to authenticated;

grant select, insert, update, delete on table
  public.timetable_snapshots
to authenticated;

grant select, insert on table
  public.community_reports
to authenticated;

grant select on table
  public.site_announcements,
  public.teachers,
  public.profile_auth_links,
  public.timetable_invites,
  public.timetable_share_members
to authenticated;

grant insert on table
  public.feedback_submissions
to authenticated;

grant select, insert, update, delete on table
  public.admin_accounts,
  public.admin_audit_logs,
  public.admin_sessions,
  public.admin_users,
  public.comments,
  public.community_blocks,
  public.community_notification_settings,
  public.community_notifications,
  public.community_reports,
  public.community_terms_acceptances,
  public.feedback_submissions,
  public.post_images,
  public.post_likes,
  public.posts,
  public.profile_auth_links,
  public.profiles,
  public.site_announcement_reads,
  public.site_announcements,
  public.teacher_ratings,
  public.teachers,
  public.timetable_invites,
  public.timetable_share_members,
  public.timetable_snapshots
to service_role;

revoke all privileges on sequence
  public.admin_audit_logs_id_seq,
  public.teachers_id_seq
from public, anon, authenticated, service_role;

grant usage, select on sequence
  public.admin_audit_logs_id_seq,
  public.teachers_id_seq
to service_role;

revoke execute on all functions in schema public
from public, anon, authenticated, service_role;

do $$
declare
  function_signature text;
begin
  foreach function_signature in array array[
    'public.current_profile_id()',
    'public.can_use_profile(uuid)',
    'public.can_use_profile_path(text)',
    'public.current_community_profile_id()',
    'public.community_latest_terms_version()',
    'public.has_accepted_community_terms(text)',
    'public.accept_community_terms(text)',
    'public.revoke_community_terms(text)',
    'public.create_community_notification(uuid, uuid, uuid, uuid, text, text, text)',
    'public.soft_delete_own_post(uuid)',
    'public.soft_delete_own_comment(uuid)',
    'public.is_profile_muted(uuid)',
    'public.report_community_content(text, uuid, uuid, uuid, text, text)',
    'public.block_community_user(uuid, text)',
    'public.unblock_community_user(uuid)',
    'public.can_view_timetable_snapshot(uuid)',
    'public.create_timetable_invite(text)',
    'public.accept_timetable_invite(text)',
    'public.revoke_timetable_share(uuid, uuid)',
    'public.stop_timetable_sharing()',
    'public.leave_timetable_share(uuid)'
  ]
  loop
    if to_regprocedure(function_signature) is not null then
      execute format('grant execute on function %s to authenticated', function_signature);
    else
      raise notice 'Skipping missing authenticated function grant: %', function_signature;
    end if;
  end loop;
end;
$$;

do $$
declare
  function_signature text;
begin
  foreach function_signature in array array[
    'public.admin_login(text, text, integer)',
    'public.admin_create_account(text, text, text, text, uuid)',
    'public.admin_update_account(uuid, uuid, text, text, text, text, boolean)',
    'public.admin_daily_counts(integer, text)',
    'public.admin_activity_heatmap(integer, text)',
    'public.admin_category_mix(integer, text)',
    'public.admin_top_content(integer, text, integer)'
  ]
  loop
    if to_regprocedure(function_signature) is not null then
      execute format('grant execute on function %s to service_role', function_signature);
    else
      raise notice 'Skipping missing service_role function grant: %', function_signature;
    end if;
  end loop;
end;
$$;

alter default privileges for role postgres in schema public
  revoke select, insert, update, delete on tables from anon, authenticated, service_role;

alter default privileges for role postgres in schema public
  revoke usage, select on sequences from anon, authenticated, service_role;

alter default privileges for role postgres in schema public
  revoke execute on functions from public, anon, authenticated, service_role;

select pg_notify('pgrst', 'reload schema');
