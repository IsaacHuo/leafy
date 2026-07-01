-- All-time public community profile stats for homepage titles.
-- Counts only published, non-anonymous posts so anonymous activity remains private.

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
grant usage on schema private to authenticated, service_role;

create index if not exists idx_posts_public_profile_stats
on public.posts (author_id, created_at desc)
where status = 'published'
  and is_anonymous = false;

create or replace function private.community_profile_title_v1(
  p_public_post_count integer,
  p_received_like_count integer
)
returns text
language sql
immutable
set search_path = public
as $$
  select case
    when greatest(coalesce(p_public_post_count, 0), 0) * 3
       + greatest(coalesce(p_received_like_count, 0), 0) >= 150 then '山水知己'
    when greatest(coalesce(p_public_post_count, 0), 0) * 3
       + greatest(coalesce(p_received_like_count, 0), 0) >= 60 then '松下常客'
    when greatest(coalesce(p_public_post_count, 0), 0) * 3
       + greatest(coalesce(p_received_like_count, 0), 0) >= 20 then '绿野熟人'
    when greatest(coalesce(p_public_post_count, 0), 0) * 3
       + greatest(coalesce(p_received_like_count, 0), 0) >= 5 then '林下伙伴'
    else '初入林园'
  end;
$$;

create or replace function private.community_profile_stats_v1_impl(
  p_profile_ids uuid[] default '{}'::uuid[]
)
returns jsonb
language plpgsql
security definer
stable
set search_path = public
as $$
declare
  requested_profile_ids uuid[];
  result jsonb;
begin
  select coalesce(array_agg(distinct profile_id), '{}'::uuid[])
  into requested_profile_ids
  from unnest(coalesce(p_profile_ids, '{}'::uuid[])) as input(profile_id)
  where profile_id is not null;

  if cardinality(requested_profile_ids) = 0 then
    return jsonb_build_object(
      'generated_at', now(),
      'profiles', '[]'::jsonb
    );
  end if;

  with target_profiles as (
    select profiles.id as profile_id
    from public.profiles profiles
    where profiles.id = any(requested_profile_ids)
  ),
  public_posts as (
    select
      posts.id,
      posts.author_id as profile_id,
      posts.created_at
    from public.posts posts
    join target_profiles targets on targets.profile_id = posts.author_id
    where posts.status = 'published'
      and posts.is_anonymous = false
  ),
  post_stats as (
    select
      profile_id,
      count(*)::integer as public_post_count,
      min(created_at) as first_post_at,
      max(created_at) as latest_post_at
    from public_posts
    group by profile_id
  ),
  like_stats as (
    select
      public_posts.profile_id,
      count(post_likes.post_id)::integer as received_like_count
    from public_posts
    left join public.post_likes post_likes on post_likes.post_id = public_posts.id
    group by public_posts.profile_id
  ),
  normalized_stats as (
    select
      targets.profile_id,
      coalesce(stats.public_post_count, 0) as public_post_count,
      coalesce(likes.received_like_count, 0) as received_like_count,
      coalesce(stats.public_post_count, 0) * 3
        + coalesce(likes.received_like_count, 0) as activity_score,
      stats.first_post_at,
      stats.latest_post_at
    from target_profiles targets
    left join post_stats stats on stats.profile_id = targets.profile_id
    left join like_stats likes on likes.profile_id = targets.profile_id
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'profile_id', profile_id,
        'public_post_count', public_post_count,
        'received_like_count', received_like_count,
        'activity_score', activity_score,
        'title', private.community_profile_title_v1(public_post_count, received_like_count),
        'first_post_at', first_post_at,
        'latest_post_at', latest_post_at
      )
      order by profile_id
    ),
    '[]'::jsonb
  )
  into result
  from normalized_stats;

  return jsonb_build_object(
    'generated_at', now(),
    'profiles', result
  );
end;
$$;

create or replace function public.community_profile_stats_v1(
  p_profile_ids uuid[] default '{}'::uuid[]
)
returns jsonb
language sql
stable
set search_path = public
as $$
  select private.community_profile_stats_v1_impl(p_profile_ids);
$$;

revoke all on function private.community_profile_title_v1(integer, integer) from public, anon, authenticated;
revoke all on function private.community_profile_stats_v1_impl(uuid[]) from public, anon, authenticated;
revoke all on function public.community_profile_stats_v1(uuid[]) from public, anon, authenticated;

grant execute on function private.community_profile_stats_v1_impl(uuid[]) to authenticated, service_role;
grant execute on function public.community_profile_stats_v1(uuid[]) to authenticated, service_role;

comment on function public.community_profile_stats_v1(uuid[]) is
  'Returns all-time public, non-anonymous community activity stats for profile homepage titles.';

select pg_notify('pgrst', 'reload schema');
