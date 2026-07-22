begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(20);

select ok(to_regclass('private.community_identity_link_conflicts') is not null, 'identity conflicts are auditable');
select ok(
  to_regclass('public.idx_profile_auth_links_profile_id_unique') is null
    and to_regclass('public.idx_profile_auth_links_profile_id') is not null,
  'a profile can retain multiple indexed device Auth links'
);
select ok(
  to_regclass('public.idx_profile_auth_links_campus_edu_id_unique') is null
    and to_regclass('public.idx_profile_auth_links_campus_edu_id') is not null,
  'a school identity can retain multiple indexed device Auth links'
);
select ok(
  has_function_privilege('service_role', 'public.edge_claim_community_identity(uuid,text,text,text)', 'EXECUTE')
    and not has_function_privilege('authenticated', 'public.edge_claim_community_identity(uuid,text,text,text)', 'EXECUTE'),
  'only the bootstrap service can claim an identity'
);

select ok(
  has_function_privilege('authenticated', 'public.create_community_post_v2(uuid,text,text,text,boolean,boolean)', 'EXECUTE')
    and has_function_privilege('authenticated', 'public.create_community_comment_v1(uuid,uuid,text,boolean)', 'EXECUTE'),
  'authenticated clients can use the bounded mutation RPCs'
);
select ok(
  not has_table_privilege('authenticated', 'public.posts', 'INSERT')
    and not has_table_privilege('authenticated', 'public.comments', 'INSERT')
    and not has_table_privilege('authenticated', 'public.post_images', 'INSERT'),
  'direct community inserts are revoked'
);
select ok(to_regclass('public.idx_community_reports_open_post_unique') is not null, 'duplicate open post reports are prevented');
select unalike(
  pg_get_functiondef('public.report_community_content(text,uuid,uuid,uuid,text,text)'::regprocedure),
  '%update public.posts%',
  'reporting does not hide posts'
);
select unalike(
  pg_get_functiondef('public.report_community_content(text,uuid,uuid,uuid,text,text)'::regprocedure),
  '%update public.comments%',
  'reporting does not hide comments'
);

select ok(to_regclass('private.community_upload_receipts') is not null, 'validated upload receipts exist');
select ok(
  has_function_privilege('authenticated', 'public.attach_community_post_image_v1(uuid,uuid,integer)', 'EXECUTE')
    and not has_function_privilege('authenticated', 'public.edge_record_community_upload_validation(uuid,uuid,text,text,text,text,integer,integer,integer,integer,integer,integer)', 'EXECUTE'),
  'clients can consume but cannot mint upload receipts'
);
select ok(
  has_function_privilege('authenticated', 'public.publish_community_post_v1(uuid)', 'EXECUTE'),
  'only the validated publish RPC exposes pending posts'
);
select ok(
  exists (select 1 from pg_trigger where tgname = 'community_posts_guard_status_transition' and not tgisinternal),
  'direct post status transitions are guarded'
);

select is(private.campus_ai_entitlement_status_rank('revoked'), 5, 'revoked has terminal precedence');
select is(private.campus_ai_entitlement_status_rank('active'), 2, 'active has lower terminal precedence');

do $$
begin
  perform private.sync_campus_ai_entitlement(
    null, 'audit-monotonic', 'com.isaachuo.leafy.ai.weekly.v2', 'original-1', 'transaction-1', 'Sandbox',
    'active', now() - interval '1 day', now() + interval '6 days', 'notification-active', timestamptz '2026-07-22 00:00:00+00'
  );
  perform private.sync_campus_ai_entitlement(
    null, 'audit-monotonic', 'com.isaachuo.leafy.ai.weekly.v2', 'original-1', 'transaction-2', 'Sandbox',
    'refunded', now() - interval '1 day', now() + interval '6 days', 'notification-refund', timestamptz '2026-07-22 00:10:00+00'
  );
  perform private.sync_campus_ai_entitlement(
    null, 'audit-monotonic', 'com.isaachuo.leafy.ai.weekly.v2', 'original-1', 'transaction-old', 'Sandbox',
    'active', now() - interval '1 day', now() + interval '6 days', 'notification-old-active', timestamptz '2026-07-22 00:05:00+00'
  );
end $$;

select is(
  (select status from private.campus_ai_entitlements where app_transaction_id = 'audit-monotonic'),
  'refunded',
  'an older active transaction cannot overwrite a refund'
);
select is(
  (select last_signed_at from private.campus_ai_entitlements where app_transaction_id = 'audit-monotonic'),
  timestamptz '2026-07-22 00:10:00+00',
  'the entitlement signed timestamp never moves backwards'
);
select is(
  (private.sync_campus_ai_entitlement(
    null, 'audit-monotonic', null, null, null, null,
    'refunded', null, null, 'notification-refund', timestamptz '2026-07-22 00:10:00+00'
  ) ->> 'duplicate')::boolean,
  true,
  'duplicate StoreKit notifications are idempotent'
);
select is(
  (select count(*) from private.campus_ai_storekit_notification_ledger where notification_uuid = 'notification-refund'),
  1::bigint,
  'the notification ledger stores one row per UUID'
);
select ok(
  not has_table_privilege('authenticated', 'private.campus_ai_storekit_notification_ledger', 'SELECT'),
  'the StoreKit notification ledger is private'
);

select * from finish();
rollback;
