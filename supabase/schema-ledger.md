# MyLeafy Supabase Schema Ledger

Last updated: 2026-07-22

This ledger records the deployed schema facts that the app relies on. It is not
a replacement for migrations, and existing migration history should not be
squashed. New changes should add forward-only migrations and update this file
when they change a table, RPC, RLS policy family, grant, or Edge Function
contract.

## Domain Boundaries

| Domain | Owns | Public entry points |
| --- | --- | --- |
| `community-social` | Profiles, posts, comments, images, likes, favorites, pins, feed hydration | `community-bootstrap-user`, `community-feed`, `community_feed_v1`, `community_hot_posts_v1`, `community_profile_stats_v1` |
| `moderation` | Reports, hidden/pending/deleted content states, profile mute actions, poll deletion review | `admin-community` moderation actions, report/comment/post status updates |
| `catalog-ratings` | Teachers, courses, dishes, ratings, catalog suggestions, postgraduate sources | Teacher/course/dish tables and rating CRUD paths, catalog suggestion admin actions |
| `timetable-sharing` | Timetable snapshots, invite codes, share members, owner/viewer state changes | `create_timetable_invite`, `accept_timetable_invite`, `revoke_timetable_share`, `stop_timetable_sharing`, `leave_timetable_share` |
| `campus-runtime` | Campuses, campus membership requests, semester and national calendar runtime configs | `campus-request`, `current_profile_campus_id`, campus request admin actions |
| `campus-ai` | AI usage, quota reservations, managed entitlements, App Store notification sync | `campus-ai-assistant`, `campus-ai-entitlement`, `app-store-server-notifications`, private quota RPCs |
| `admin` | Admin accounts, sessions, login attempts, audit logs, overview analytics, announcements, feedback | `admin-login`, `admin-me`, `admin-logout`, `admin-community`, announcement wrappers |

## Compatibility Rules

- Keep existing Edge Function names and admin action names stable unless a
  versioned replacement is shipped with an adapter.
- Return backend failures through `{ error, errorEnvelope }`, where
  `errorEnvelope` has `{ code, message, retryable, details? }`.
- Use `public.backend_capabilities_v1()` for feature availability. Clients
  should branch on capability booleans instead of matching localized error text.
- Do not add client writes for state machines that already have RPC ownership
  such as timetable sharing, poll lifecycle, campus membership requests, and AI
  quota accounting.
- New high-traffic read paths should prefer hydrated RPC or Edge payloads over
  client-side multi-query assembly.

## Capability Manifest

`public.backend_capabilities_v1()` returns:

- `features.community_feed`
- `features.community_hot_posts`
- `features.community_polls`
- `features.community_notifications`
- `features.post_favorites`
- `features.catalog_ratings`
- `features.postgraduate_sources`
- `features.timetable_sharing`
- `features.campus_runtime`
- `features.campus_weather`
- `features.school_community_access`
- `features.campus_ai`
- `features.campus_ai_managed_entitlements`
- `features.admin_console`

The RPC also exposes an `rpcs` object for versioned RPC availability and an
`edge_functions` list for the deployment checklist.

## Core Tables

| Domain | Tables |
| --- | --- |
| `community-social` | `profiles`, `profile_auth_links`, `posts`, `post_images`, `comments`, `community_images`, `post_likes`, `post_favorites`, `community_blocks`, `community_notifications`, `community_post_pins` |
| `moderation` | `community_reports`, content status fields on posts/comments/polls/profiles |
| `catalog-ratings` | `teachers`, `teacher_ratings`, `course_catalog`, `course_ratings`, `dish_catalog`, `dish_ratings`, `catalog_suggestions`, `postgraduate_sources`, `postgraduate_source_suggestions` |
| `timetable-sharing` | `timetable_snapshots`, `timetable_invites`, `timetable_share_members` |
| `campus-runtime` | `campuses`, `campus_membership_requests`, `semester_runtime_configs`, `national_calendar_runtime_configs`, `campus_weather_cache` |
| `campus-ai` | `private.campus_ai_usage_events`, `private.campus_ai_entitlements` |
| `admin` | `admin_accounts`, `admin_sessions`, `admin_login_attempts`, `admin_audit_logs`, `site_announcements`, `feedback_submissions` |

## Core RPCs

| Domain | RPCs |
| --- | --- |
| `community-social` | `community_feed_v1`, `community_hot_posts_v1`, `community_profile_stats_v1`, `community_post_summary_v1`, `toggle_post_like_v1`, `toggle_post_favorite_v1`, `create_community_notification`, `unblock_community_user` |
| `community-social` polls | `my_authored_community_polls_v1`, `my_voted_community_polls_v1`, `request_delete_community_poll_v1`, `delete_own_community_poll_v1` |
| `timetable-sharing` | `can_view_timetable_snapshot`, `create_timetable_invite`, `accept_timetable_invite`, `revoke_timetable_share`, `stop_timetable_sharing`, `leave_timetable_share` |
| `campus-runtime` | `current_profile_campus_id`, `can_use_profile`, `submit_campus_membership_request`, `approve_campus_membership_request`, `reject_campus_membership_request`, `leafy_semester_effective_date`, `reconcile_semester_runtime_active_config`, `admin_upsert_semester_runtime_config`, `admin_upsert_national_calendar_runtime_config` |
| `campus-ai` | `private.campus_ai_quota_snapshot`, `private.reserve_campus_ai_quota`, `private.complete_campus_ai_usage`, `private.sync_campus_ai_entitlement` |
| `admin` | `admin_login`, `admin_create_account`, `admin_update_account`, `admin_login_rate_limit_status`, `admin_begin_login_attempt`, `admin_finish_login_attempt`, `admin_cleanup_login_attempts`, `admin_daily_counts`, `admin_activity_heatmap`, `admin_category_mix`, `admin_top_content` |

## Edge Functions

- `admin-community`
- `admin-export`
- `admin-login`
- `admin-me`
- `admin-logout`
- `admin-list-announcements`
- `admin-publish-announcement`
- `admin-update-announcement`
- `community-bootstrap-user`
- `community-feed`
- `campus-request`
- `campus-weather`
- `campus-ai-assistant`
- `campus-ai-entitlement`
- `app-store-server-notifications`
- `share-preview`

## Migration Ledger

- `20260423_community_v1.sql`
- `20260424000000_community_notifications.sql`
- `20260424000100_community_profile_completion.sql`
- `20260424000200_remove_profile_edit_lock.sql`
- `20260424000300_teacher_ratings.sql`
- `20260425000100_posts_soft_delete_policy.sql`
- `20260425000200_posts_soft_delete_rpc.sql`
- `20260425000300_prevent_post_self_likes.sql`
- `20260425000400_site_announcements.sql`
- `20260426000100_allow_profile_edits.sql`
- `20260426000200_community_profile_auth_links.sql`
- `20260427000100_post_upload_limits.sql`
- `20260428000100_notifications_feedback_and_comments.sql`
- `20260428000200_admin_console.sql`
- `20260428000300_admin_console_pgcrypto_search_path.sql`
- `20260508000100_admin_analytics.sql`
- `20260508000200_guideline_1_2_moderation.sql`
- `20260511000100_shared_timetables.sql`
- `20260511000200_shared_timetable_digest_search_path.sql`
- `20260511000300_shared_timetable_accept_ambiguity.sql`
- `20260512000100_community_notification_realtime.sql`
- `20260514000100_explicit_data_api_grants.sql`
- `20260514000200_restore_revoke_community_terms_rpc.sql`
- `20260514000300_post_favorites.sql`
- `20260516123040_course_ratings.sql`
- `20260517020512_catalog_suggestions.sql`
- `20260524140954_catalog_suggestion_teacher_name.sql`
- `20260524221717_community_post_pins.sql`
- `20260525023043_community_feed_optimization.sql`
- `20260525032702_community_feed_hardening.sql`
- `20260526144759_campus_weather_cache.sql`
- `20260528024930_community_polls_v1.sql`
- `20260528045814_community_poll_lifecycle_v2.sql`
- `20260528130839_semester_runtime_configs.sql`
- `20260529133034_postgraduate_sources.sql`
- `20260605005826_campus_scope_v1.sql`
- `20260605010100_next_semester_runtime_config.sql`
- `20260605075924_reactivate_current_semester_runtime_config.sql`
- `20260605080459_semester_runtime_auto_reconcile_guard.sql`
- `20260611075655_community_profile_homepage.sql`
- `20260611141354_community_profile_stats_v1.sql`
- `20260612042443_community_profile_cover_path.sql`
- `20260612074957_community_single_pin_category_limit.sql`
- `20260615124522_image_posts_publish_after_upload_report_hide.sql`
- `20260615165000_national_calendar_runtime_configs.sql`
- `20260618132620_school_community_access_v1.sql`
- `20260623102832_grant_school_community_admin_access.sql`
- `20260623113617_community_school_membership_flow.sql`
- `20260625053303_campus_ai_usage_events.sql`
- `20260627125947_campus_ai_managed_entitlements.sql`
- `20260701090000_backend_capabilities_v1.sql`
- `20260702022000_campus_ai_weekly_subscription.sql`
- `20260704090000_campus_email_lookup.sql`
- `20260710121000_admin_security_runtime.sql`
- `20260713190000_fix_next_semester_week_capacity.sql`
- `20260722090000_community_identity_hardening.sql`
- `20260722092000_community_mutation_hardening.sql`
- `20260722094000_campus_ai_entitlement_monotonicity.sql`
- `20260722100000_community_upload_receipts.sql`
- `20260722113000_community_school_identity_inheritance.sql`

## Community Identity Invariants

- `(campus_id, edu_id)` uniquely identifies one durable `profiles` row.
- `profiles.id` is independent from the lifetime of `auth.users`; existing IDs and all content ownership foreign keys remain unchanged.
- `profile_auth_links.auth_user_id` is unique, while multiple device Auth users may link to the same profile and school identity.
- `edge_claim_community_identity` is service-role-only, serializes claims per school identity, and moves only the current Auth link when the local school account changes.
- Notification email binding does not grant, recover, or select a community profile.

## Admin Security and Runtime Invariants

- `admin_login_attempts` has RLS enabled and no App-facing policy or grant.
  Only `service_role` may query, insert, update, or delete rows. Rate-limit and cleanup
  RPCs revoke `PUBLIC`, `anon`, and `authenticated` execute access.
- Failed admin logins use a rolling 15-minute budget: five failures for the
  normalized username and IP pair, or twenty failures for the IP across
  usernames. Successful logins are retained for audit context but do not spend
  either failure budget.
- `admin_begin_login_attempt` serializes checks and insertion by IP;
  `admin_finish_login_attempt` records the final result. Rate-limited requests
  are retained for audit but do not extend the rolling failure window.
- `leafy-admin-login-attempts-retention` runs daily and removes rows older than
  90 days through `admin_cleanup_login_attempts`.
- `admin_audit_logs` carries nullable `request_id`, `outcome`, `duration_ms`,
  and `error_code` metadata. Existing audit writers remain forward-compatible.
- Semester and national-calendar activation must use their service-role-only
  admin upsert RPCs. Both serialize activation with transaction advisory locks.
- BJFU semester runtime rows use a fixed `supported_weeks = 20`; sparse course
  weeks remain an iOS parsing and presentation concern.
  Semester writes also cooperate with the existing automatic reconcile guard
  and never activate a future semester early.
- Admin global-search indexes use `pg_trgm` for substring lookup and a
  full-text GIN index for post content. They add no App table privileges and do
  not change existing RLS policies.
- Admin Edge actions preserve all 60 legacy names and add `globalSearch`,
  session listing/revocation, and national-calendar listing/upsert. CSV export
  is isolated in `admin-export` with server-side resource and field allowlists.
