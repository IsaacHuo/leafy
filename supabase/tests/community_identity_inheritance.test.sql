begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(20);

insert into auth.users (id)
values
  ('10000000-0000-0000-0000-000000000001'),
  ('10000000-0000-0000-0000-000000000002'),
  ('10000000-0000-0000-0000-000000000003'),
  ('10000000-0000-0000-0000-000000000004'),
  ('10000000-0000-0000-0000-000000000005');

insert into public.profiles (
  id,
  campus_id,
  edu_id,
  nickname,
  display_name,
  community_campus_id,
  community_access_status,
  is_profile_complete
)
values (
  '20000000-0000-0000-0000-000000000001',
  'bjfu',
  'identity-inheritance-existing',
  '原资料',
  '原资料',
  'bjfu',
  'approved',
  true
);

insert into public.profile_auth_links (
  auth_user_id,
  profile_id,
  campus_id,
  edu_id
)
values (
  '10000000-0000-0000-0000-000000000001',
  '20000000-0000-0000-0000-000000000001',
  'bjfu',
  'identity-inheritance-existing'
);

insert into public.posts (id, campus_id, author_id, title, body, category, status)
values (
  '30000000-0000-0000-0000-000000000001',
  'bjfu',
  '20000000-0000-0000-0000-000000000001',
  '保留帖子',
  '迁移不得改写 owner',
  '测试',
  'published'
);

insert into public.comments (id, post_id, author_id, body, status)
values (
  '40000000-0000-0000-0000-000000000001',
  '30000000-0000-0000-0000-000000000001',
  '20000000-0000-0000-0000-000000000001',
  '保留评论',
  'published'
);

insert into public.post_images (id, post_id, path, sort_order, width, height)
values (
  '50000000-0000-0000-0000-000000000001',
  '30000000-0000-0000-0000-000000000001',
  'posts/identity-inheritance-existing.jpg',
  0,
  100,
  100
);

select is(
  public.edge_claim_community_identity(
    '10000000-0000-0000-0000-000000000002',
    'bjfu',
    'identity-inheritance-existing',
    '新设备'
  ) ->> 'profile_id',
  '20000000-0000-0000-0000-000000000001',
  'a new device inherits the existing profile ID'
);

select is(
  (select count(*) from public.profile_auth_links where profile_id = '20000000-0000-0000-0000-000000000001'),
  2::bigint,
  'one profile accepts multiple device Auth links'
);

select is(
  (select display_name from public.profiles where id = '20000000-0000-0000-0000-000000000001'),
  '原资料',
  'a new device never overwrites inherited profile fields'
);

select is(
  (select author_id from public.posts where id = '30000000-0000-0000-0000-000000000001'),
  '20000000-0000-0000-0000-000000000001'::uuid,
  'post ownership is unchanged'
);

select is(
  (select author_id from public.comments where id = '40000000-0000-0000-0000-000000000001'),
  '20000000-0000-0000-0000-000000000001'::uuid,
  'comment ownership is unchanged'
);

select is(
  (select post_id from public.post_images where id = '50000000-0000-0000-0000-000000000001'),
  '30000000-0000-0000-0000-000000000001'::uuid,
  'image ownership is unchanged'
);

select isnt(
  public.edge_claim_community_identity(
    '10000000-0000-0000-0000-000000000002',
    'bjfu',
    'identity-inheritance-new',
    '另一个账号'
  ) ->> 'profile_id',
  '20000000-0000-0000-0000-000000000001',
  'switching to a new school identity creates a distinct durable profile'
);

select is(
  (select edu_id from public.profile_auth_links where auth_user_id = '10000000-0000-0000-0000-000000000002'),
  'identity-inheritance-new',
  'switching identities moves only the current Auth link'
);

select is(
  (select profile_id from public.profile_auth_links where auth_user_id = '10000000-0000-0000-0000-000000000001'),
  '20000000-0000-0000-0000-000000000001'::uuid,
  'another device remains linked to the original profile'
);

select is(
  (select count(*) from public.profiles where campus_id = 'bjfu' and edu_id in ('identity-inheritance-existing', 'identity-inheritance-new')),
  2::bigint,
  'switching does not delete either profile'
);

select is(
  (select count(*) from public.posts where id = '30000000-0000-0000-0000-000000000001'),
  1::bigint,
  'switching does not delete existing content'
);

select is(
  public.edge_claim_community_identity(
    '10000000-0000-0000-0000-000000000002',
    'bjfu',
    'identity-inheritance-existing',
    '切回原账号'
  ) ->> 'profile_id',
  '20000000-0000-0000-0000-000000000001',
  'switching back restores the original profile'
);

select is(
  public.edge_claim_community_identity(
    '10000000-0000-0000-0000-000000000003',
    'bjfu',
    'identity-inheritance-concurrent',
    '设备三'
  ) ->> 'is_new_user',
  'true',
  'the first claim creates the profile'
);

select is(
  public.edge_claim_community_identity(
    '10000000-0000-0000-0000-000000000004',
    'bjfu',
    'identity-inheritance-concurrent',
    '设备四'
  ) ->> 'is_new_user',
  'false',
  'a competing device inherits instead of creating another profile'
);

select is(
  (select count(*) from public.profiles where campus_id = 'bjfu' and edu_id = 'identity-inheritance-concurrent'),
  1::bigint,
  'the unique school identity has exactly one profile'
);

select is(
  (select count(*) from public.profile_auth_links where campus_id = 'bjfu' and edu_id = 'identity-inheritance-concurrent'),
  2::bigint,
  'both competing devices retain valid links'
);

insert into private.community_identity_link_conflicts (
  auth_user_id,
  profile_id,
  campus_id,
  edu_id,
  created_at,
  last_seen_at,
  retained_auth_user_id,
  resolution_reason
)
values (
  '10000000-0000-0000-0000-000000000005',
  '20000000-0000-0000-0000-000000000001',
  'bjfu',
  'identity-inheritance-existing',
  now() - interval '1 day',
  now() - interval '1 hour',
  '10000000-0000-0000-0000-000000000001',
  'duplicate_profile_link'
);

\ir ../migrations/20260722113000_community_school_identity_inheritance.sql

select is(
  (select profile_id from public.profile_auth_links where auth_user_id = '10000000-0000-0000-0000-000000000005'),
  '20000000-0000-0000-0000-000000000001'::uuid,
  'a matching archived device link is restored safely'
);

select is(
  (select count(*) from private.community_identity_link_conflicts where auth_user_id = '10000000-0000-0000-0000-000000000005'),
  1::bigint,
  'restoring a link retains its audit row'
);

select ok(
  not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.profiles'::regclass
      and contype = 'f'
      and confrelid = 'auth.users'::regclass
  ),
  'profile lifetime is independent from replaceable Auth users'
);

select ok(
  has_function_privilege('service_role', 'public.edge_claim_community_identity(uuid,text,text,text)', 'EXECUTE')
    and not has_function_privilege('authenticated', 'public.edge_claim_community_identity(uuid,text,text,text)', 'EXECUTE'),
  'only the bootstrap service can map device sessions'
);

select * from finish();
rollback;
