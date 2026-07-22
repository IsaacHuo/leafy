begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(18);

select ok(to_regclass('public.dish_catalog') is not null, 'dish catalog is part of migration history');
select ok(to_regclass('public.dish_ratings') is not null, 'dish ratings are part of migration history');
select alike(
  pg_get_indexdef('public.idx_catalog_suggestions_open_unique'::regclass),
  '%campus_id%',
  'open catalog suggestion uniqueness is campus scoped'
);
select ok(
  to_regprocedure('public.admin_approve_catalog_suggestion_v1(uuid,uuid,text)') is not null
    and to_regprocedure('public.admin_resolve_moderation_report_v1(uuid,text,text,boolean,boolean,timestamp with time zone,text,uuid)') is not null,
  'critical admin transaction RPCs exist'
);
select ok(
  has_function_privilege('service_role', 'public.admin_approve_catalog_suggestion_v1(uuid,uuid,text)', 'EXECUTE')
    and not has_function_privilege('authenticated', 'public.admin_approve_catalog_suggestion_v1(uuid,uuid,text)', 'EXECUTE')
    and not has_function_privilege('anon', 'public.admin_approve_catalog_suggestion_v1(uuid,uuid,text)', 'EXECUTE'),
  'catalog approval RPC is service-role only'
);
select ok(
  has_function_privilege('service_role', 'public.refresh_dish_rating_summary(bigint)', 'EXECUTE')
    and not has_function_privilege('authenticated', 'public.refresh_dish_rating_summary(bigint)', 'EXECUTE')
    and not has_function_privilege('anon', 'public.refresh_dish_rating_summary(bigint)', 'EXECUTE'),
  'dish summary maintenance remains service-role only'
);

insert into public.admin_accounts(id, username, password_hash, display_name, role, active)
values ('a1000000-0000-0000-0000-000000000001', 'admin-hardening-test', crypt('test-password', gen_salt('bf', 4)), 'Test Admin', 'super_admin', true);

insert into public.profiles(
  id, campus_id, edu_id, nickname, display_name, community_campus_id, community_access_status, is_profile_complete
) values (
  'b1000000-0000-0000-0000-000000000001', 'bjfu', 'admin-hardening-user', '测试用户', '测试用户', 'bjfu', 'approved', true
);

insert into public.teachers(campus_id, name, unit, status)
values ('bjfu', '事务测试教师', '事务测试学院', 'hidden');

insert into public.catalog_suggestions(
  id, campus_id, suggestion_type, user_id, name, unit, initial_stars, status
) values (
  'c1000000-0000-0000-0000-000000000001', 'bjfu', 'teacher',
  'b1000000-0000-0000-0000-000000000001', '事务测试教师', '事务测试学院', null, 'open'
);

select is(
  (public.admin_approve_catalog_suggestion_v1(
    'c1000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001', null
  )).status,
  'approved',
  'null-star suggestion approves successfully'
);
select is(
  (select count(*) from public.teachers where campus_id = 'bjfu' and lower(btrim(name)) = lower('事务测试教师')),
  1::bigint,
  'approval reuses the existing normalized teacher'
);
select is(
  (select count(*) from public.teacher_ratings where user_id = 'b1000000-0000-0000-0000-000000000001'),
  0::bigint,
  'null initial stars create no rating'
);
select throws_ok(
  $$select public.admin_approve_catalog_suggestion_v1(
    'c1000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001', null
  )$$,
  'P0001',
  'ADMIN_CATALOG_SUGGESTION_ALREADY_REVIEWED',
  'repeated approval returns an explicit conflict signal'
);

insert into public.campuses(id, display_name, short_name, connector_kind, status, normalized_name, is_community_enabled, is_system)
values ('admin-test-campus', '后台测试大学', '后台测试', 'custom', 'active', public.normalize_school_name('后台测试大学'), true, false);
insert into public.profiles(
  id, campus_id, edu_id, nickname, display_name, community_campus_id, community_access_status, is_profile_complete
) values (
  'b1000000-0000-0000-0000-000000000002', 'admin-test-campus', 'admin-hardening-user-2',
  '跨校测试用户', '跨校测试用户', 'admin-test-campus', 'approved', true
);
insert into public.catalog_suggestions(id, campus_id, suggestion_type, user_id, name, unit, initial_stars, status)
values (
  'c1000000-0000-0000-0000-000000000002', 'admin-test-campus', 'teacher',
  'b1000000-0000-0000-0000-000000000002', '事务测试教师', '事务测试学院', 5, 'open'
);
select lives_ok(
  $$select public.admin_approve_catalog_suggestion_v1(
    'c1000000-0000-0000-0000-000000000002', 'a1000000-0000-0000-0000-000000000001', null
  )$$,
  'same normalized teacher can be approved in another campus'
);
select is(
  (select stars from public.teacher_ratings ratings join public.teachers teachers on teachers.id = ratings.teacher_id
    where ratings.user_id = 'b1000000-0000-0000-0000-000000000002' and teachers.campus_id = 'admin-test-campus'),
  5,
  'valid initial stars create one rating'
);

insert into public.posts(id, campus_id, author_id, title, body, category, status)
values (
  'd1000000-0000-0000-0000-000000000001', 'bjfu', 'b1000000-0000-0000-0000-000000000001',
  '举报事务测试', '举报不得自动下架', '测试', 'published'
);
insert into public.community_reports(
  id, reporter_id, target_type, post_id, reason, status
) values (
  'e1000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000001',
  'post', 'd1000000-0000-0000-0000-000000000001', '测试举报', 'open'
);
select lives_ok(
  $$select public.admin_resolve_moderation_report_v1(
    'e1000000-0000-0000-0000-000000000001', 'resolved', '只关闭举报', false, false,
    null, null, 'a1000000-0000-0000-0000-000000000001'
  )$$,
  'report can resolve without hiding content'
);
select is(
  (select status from public.posts where id = 'd1000000-0000-0000-0000-000000000001'),
  'published',
  'resolving a report does not auto-hide the post'
);

insert into public.community_post_pins(
  id, post_id, campus_id, scope, category, priority, status, created_by
) values (
  'f1000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001',
  'bjfu', 'global', null, 1, 'active', 'a1000000-0000-0000-0000-000000000001'
);
select lives_ok(
  $$select public.admin_moderate_posts_v1(
    array['d1000000-0000-0000-0000-000000000001'::uuid], 'hidden', '测试下架',
    'a1000000-0000-0000-0000-000000000001'
  )$$,
  'post hiding uses one transaction RPC'
);
select is(
  (select status from public.community_post_pins where id = 'f1000000-0000-0000-0000-000000000001'),
  'inactive',
  'hiding a post deactivates its active pin'
);

insert into public.admin_sessions(token_hash, admin_id, expires_at)
values (repeat('a', 64), 'a1000000-0000-0000-0000-000000000001', now() + interval '1 hour');
update public.admin_accounts set role = 'operator' where id = 'a1000000-0000-0000-0000-000000000001';
select ok(
  (select revoked_at is not null from public.admin_sessions where token_hash = repeat('a', 64)),
  'role changes revoke active admin sessions'
);
select ok(
  exists (select 1 from pg_constraint where conname = 'catalog_suggestions_review_shape'),
  'catalog review state shape is constrained'
);

select * from finish();
rollback;
