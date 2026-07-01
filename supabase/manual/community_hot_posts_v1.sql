-- Manual Supabase upgrade for Leafy community hot posts.
-- Run this after the existing community feed migrations are already applied.

create schema if not exists private;

revoke all on schema private from public, anon, authenticated;
grant usage on schema private to authenticated, service_role;

create index if not exists idx_posts_published_created_at
on public.posts (created_at desc)
where status = 'published';

create or replace function private.community_hot_posts_v1_impl(
  p_days integer default 7,
  p_limit integer default 10
)
returns jsonb
language plpgsql
security definer
stable
set search_path = public
as $$
declare
  current_profile_id uuid := public.current_profile_id();
  safe_days integer := greatest(1, least(coalesce(p_days, 7), 90));
  safe_limit integer := greatest(1, least(coalesce(p_limit, 10), 10));
  result jsonb;
begin
  with candidate_posts as (
    select
      posts.*,
      (coalesce(posts.comment_count, 0) * 3 + coalesce(posts.like_count, 0) * 2) as hot_score
    from public.posts posts
    where posts.status = 'published'
      and posts.created_at >= now() - make_interval(days => safe_days)
      and (
        current_profile_id is null
        or not exists (
          select 1
          from public.community_blocks blocks
          where blocks.blocker_id = current_profile_id
            and blocks.blocked_id = posts.author_id
        )
      )
    order by
      (coalesce(posts.comment_count, 0) * 3 + coalesce(posts.like_count, 0) * 2) desc,
      posts.created_at desc
    limit safe_limit
  )
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', posts.id,
      'author_id', posts.author_id,
      'title', posts.title,
      'body', posts.body,
      'category', posts.category,
      'is_anonymous', posts.is_anonymous,
      'comment_count', posts.comment_count,
      'like_count', posts.like_count,
      'status', posts.status,
      'created_at', posts.created_at,
      'updated_at', posts.updated_at,
      'viewer_has_liked', exists (
        select 1
        from public.post_likes likes
        where likes.post_id = posts.id
          and likes.user_id = current_profile_id
      ),
      'viewer_has_favorited', exists (
        select 1
        from public.post_favorites favorites
        where favorites.post_id = posts.id
          and favorites.user_id = current_profile_id
      ),
      'pin', null,
      'author', case
        when author_profile.id is null then null
        else jsonb_build_object(
          'id', author_profile.id,
          'edu_id', author_profile.edu_id,
          'nickname', author_profile.nickname,
          'display_name', author_profile.display_name,
          'avatar_path', author_profile.avatar_path,
          'major', author_profile.major,
          'grade', author_profile.grade,
          'bound_email', author_profile.bound_email,
          'pending_bound_email', author_profile.pending_bound_email,
          'email_verification_sent_at', author_profile.email_verification_sent_at,
          'profile_edited_at', author_profile.profile_edited_at,
          'is_profile_complete', author_profile.is_profile_complete,
          'created_at', author_profile.created_at,
          'updated_at', author_profile.updated_at,
          'signed_avatar_url', null
        )
      end,
      'images', coalesce(images.images, '[]'::jsonb)
    )
    order by posts.hot_score desc, posts.created_at desc
  ), '[]'::jsonb)
  into result
  from candidate_posts posts
  left join public.profiles author_profile on author_profile.id = posts.author_id
  left join lateral (
    select jsonb_agg(
      jsonb_build_object(
        'id', post_images.id,
        'post_id', post_images.post_id,
        'path', post_images.path,
        'thumbnail_path', post_images.thumbnail_path,
        'sort_order', post_images.sort_order,
        'width', coalesce(post_images.full_width, post_images.width),
        'height', coalesce(post_images.full_height, post_images.height),
        'thumbnail_width', post_images.thumbnail_width,
        'thumbnail_height', post_images.thumbnail_height,
        'full_width', coalesce(post_images.full_width, post_images.width),
        'full_height', coalesce(post_images.full_height, post_images.height),
        'created_at', post_images.created_at,
        'signedURL', null,
        'thumbnail_url', null,
        'full_url', null
      )
      order by post_images.sort_order asc
    ) as images
    from public.post_images post_images
    where post_images.post_id = posts.id
  ) images on true;

  return jsonb_build_object(
    'generated_at', now(),
    'posts', coalesce(result, '[]'::jsonb)
  );
end;
$$;

create or replace function public.community_hot_posts_v1(
  p_days integer default 7,
  p_limit integer default 10
)
returns jsonb
language sql
stable
set search_path = public
as $$
  select private.community_hot_posts_v1_impl(p_days, p_limit);
$$;

revoke all on function private.community_hot_posts_v1_impl(integer, integer) from public, anon, authenticated;
revoke all on function public.community_hot_posts_v1(integer, integer) from public, anon, authenticated;
grant execute on function private.community_hot_posts_v1_impl(integer, integer) to authenticated, service_role;
grant execute on function public.community_hot_posts_v1(integer, integer) to authenticated, service_role;

do $$
begin
  if not exists (
    select 1
    from pg_publication
    where pubname = 'supabase_realtime'
  ) then
    create publication supabase_realtime;
  end if;

  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'community_notifications'
  ) then
    alter publication supabase_realtime add table public.community_notifications;
  end if;
end;
$$;
