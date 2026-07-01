-- Community feed optimization for high-latency non-mainland networks.
-- Keep iOS requests coarse-grained and let Postgres aggregate the feed in-region.

alter table public.posts
  add column if not exists like_count integer not null default 0;

alter table public.post_images
  add column if not exists thumbnail_path text,
  add column if not exists thumbnail_width integer,
  add column if not exists thumbnail_height integer,
  add column if not exists full_width integer,
  add column if not exists full_height integer;

update public.posts
set like_count = coalesce(likes.like_count, 0)
from (
  select posts.id, count(post_likes.post_id)::integer as like_count
  from public.posts
  left join public.post_likes on post_likes.post_id = posts.id
  group by posts.id
) as likes
where posts.id = likes.id
  and posts.like_count is distinct from likes.like_count;

update public.post_images
set
  full_width = coalesce(full_width, width),
  full_height = coalesce(full_height, height)
where full_width is null
   or full_height is null;

create index if not exists idx_posts_published_created_at
on public.posts (created_at desc)
where status = 'published';

create index if not exists idx_posts_published_category_created_at
on public.posts (category, created_at desc)
where status = 'published';

create index if not exists idx_posts_published_search
on public.posts
using gin (to_tsvector('simple', coalesce(title, '') || ' ' || coalesce(body, '') || ' ' || coalesce(category, '')))
where status = 'published';

create index if not exists idx_post_likes_user_post_id
on public.post_likes (user_id, post_id);

create index if not exists idx_post_favorites_user_post_id
on public.post_favorites (user_id, post_id);

create or replace function public.refresh_post_like_count(target_post_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
  update public.posts
  set like_count = (
    select count(*)::integer
    from public.post_likes
    where post_id = target_post_id
  )
  where id = target_post_id;
$$;

create or replace function public.handle_post_like_count_sync()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    perform public.refresh_post_like_count(old.post_id);
    return old;
  end if;

  if tg_op = 'UPDATE' and old.post_id <> new.post_id then
    perform public.refresh_post_like_count(old.post_id);
  end if;

  perform public.refresh_post_like_count(new.post_id);
  return new;
end;
$$;

drop trigger if exists post_likes_sync_post_like_count on public.post_likes;
create trigger post_likes_sync_post_like_count
after insert or update or delete on public.post_likes
for each row
execute function public.handle_post_like_count_sync();

update storage.buckets
set public = true
where id = 'community-images';

create or replace function public.community_feed_v1(
  p_category text default null,
  p_search text default null,
  p_limit integer default 20
)
returns jsonb
language plpgsql
security definer
stable
set search_path = public
as $$
declare
  current_profile_id uuid := public.current_profile_id();
  normalized_category text := nullif(btrim(coalesce(p_category, '')), '');
  normalized_search text := nullif(btrim(coalesce(p_search, '')), '');
  safe_limit integer := greatest(1, least(coalesce(p_limit, 20), 50));
  search_limit integer := case when nullif(btrim(coalesce(p_search, '')), '') is null then safe_limit else least(safe_limit * 4, 100) end;
  result jsonb;
begin
  with active_pins as (
    select pins.*
    from public.community_post_pins pins
    join public.posts pinned_posts on pinned_posts.id = pins.post_id
    where pins.status = 'active'
      and pins.starts_at <= now()
      and (pins.ends_at is null or pins.ends_at > now())
      and pinned_posts.status = 'published'
      and (
        pins.scope = 'global'
        or (
          pins.scope = 'category'
          and normalized_category is not null
          and lower(btrim(coalesce(pins.category, ''))) = lower(btrim(normalized_category))
        )
      )
  ),
  preferred_pins as (
    select distinct on (post_id)
      id,
      post_id,
      scope,
      category,
      priority,
      starts_at,
      ends_at,
      status,
      reason,
      created_at
    from active_pins
    order by post_id, priority desc, starts_at desc
  ),
  pinned_posts as (
    select posts.*
    from public.posts posts
    join preferred_pins pins on pins.post_id = posts.id
    where posts.status = 'published'
  ),
  latest_posts as (
    select posts.*
    from public.posts posts
    where posts.status = 'published'
      and (normalized_category is null or posts.category = normalized_category)
      and (
        normalized_search is null
        or lower(posts.title) like '%' || lower(normalized_search) || '%'
        or lower(posts.body) like '%' || lower(normalized_search) || '%'
        or lower(coalesce(posts.category, '')) like '%' || lower(normalized_search) || '%'
      )
    order by posts.created_at desc
    limit search_limit
  ),
  candidate_posts as (
    select distinct on (id) *
    from (
      select * from pinned_posts
      union all
      select * from latest_posts
    ) posts
    order by id, created_at desc
  ),
  visible_posts as (
    select posts.*
    from candidate_posts posts
    where current_profile_id is null
      or not exists (
        select 1
        from public.community_blocks blocks
        where blocks.blocker_id = current_profile_id
          and blocks.blocked_id = posts.author_id
      )
  ),
  filtered_posts as (
    select posts.*
    from visible_posts posts
    left join public.profiles author_profile on author_profile.id = posts.author_id
    where normalized_search is null
      or lower(posts.title) like '%' || lower(normalized_search) || '%'
      or lower(posts.body) like '%' || lower(normalized_search) || '%'
      or lower(coalesce(posts.category, '')) like '%' || lower(normalized_search) || '%'
      or lower(coalesce(author_profile.nickname, '')) like '%' || lower(normalized_search) || '%'
      or lower(coalesce(author_profile.display_name, '')) like '%' || lower(normalized_search) || '%'
  ),
  ordered_posts as (
    select
      posts.*,
      pins.id as pin_id,
      pins.scope as pin_scope,
      pins.category as pin_category,
      pins.priority as pin_priority,
      pins.starts_at as pin_starts_at,
      pins.ends_at as pin_ends_at,
      pins.status as pin_status,
      pins.reason as pin_reason,
      pins.created_at as pin_created_at
    from filtered_posts posts
    left join preferred_pins pins on pins.post_id = posts.id
    order by
      case when pins.id is null then 0 else 1 end desc,
      coalesce(pins.priority, -2147483648) desc,
      coalesce(pins.starts_at, '-infinity'::timestamptz) desc,
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
      'pin', case
        when posts.pin_id is null then null
        else jsonb_build_object(
          'id', posts.pin_id,
          'post_id', posts.id,
          'scope', posts.pin_scope,
          'category', posts.pin_category,
          'priority', posts.pin_priority,
          'starts_at', posts.pin_starts_at,
          'ends_at', posts.pin_ends_at,
          'status', posts.pin_status,
          'reason', posts.pin_reason,
          'created_at', posts.pin_created_at
        )
      end,
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
    order by
      case when posts.pin_id is null then 0 else 1 end desc,
      coalesce(posts.pin_priority, -2147483648) desc,
      coalesce(posts.pin_starts_at, '-infinity'::timestamptz) desc,
      posts.created_at desc
  ), '[]'::jsonb)
  into result
  from ordered_posts posts
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

create or replace function public.community_post_summary_v1(p_post_id uuid)
returns jsonb
language plpgsql
security definer
stable
set search_path = public
as $$
declare
  current_profile_id uuid := public.current_profile_id();
  result jsonb;
begin
  select jsonb_build_object(
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
    'pin', case
      when pin_record.id is null then null
      else jsonb_build_object(
        'id', pin_record.id,
        'post_id', pin_record.post_id,
        'scope', pin_record.scope,
        'category', pin_record.category,
        'priority', pin_record.priority,
        'starts_at', pin_record.starts_at,
        'ends_at', pin_record.ends_at,
        'status', pin_record.status,
        'reason', pin_record.reason,
        'created_at', pin_record.created_at
      )
    end,
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
  into result
  from public.posts posts
  left join public.profiles author_profile on author_profile.id = posts.author_id
  left join lateral (
    select pins.*
    from public.community_post_pins pins
    where pins.post_id = posts.id
      and pins.status = 'active'
      and pins.starts_at <= now()
      and (pins.ends_at is null or pins.ends_at > now())
      and (
        pins.scope = 'global'
        or (
          pins.scope = 'category'
          and lower(btrim(coalesce(pins.category, ''))) = lower(btrim(coalesce(posts.category, '')))
        )
      )
    order by pins.priority desc, pins.starts_at desc
    limit 1
  ) pin_record on true
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
  ) images on true
  where posts.id = p_post_id
    and posts.status = 'published'
    and (
      current_profile_id is null
      or not exists (
        select 1
        from public.community_blocks blocks
        where blocks.blocker_id = current_profile_id
          and blocks.blocked_id = posts.author_id
      )
    );

  return result;
end;
$$;

create or replace function public.toggle_post_like_v1(p_post_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_profile_id uuid := public.current_profile_id();
  target_post public.posts%rowtype;
  did_create boolean := false;
begin
  if current_profile_id is null then
    raise exception 'COMMUNITY_PROFILE_REQUIRED';
  end if;

  if not exists (
    select 1
    from public.profiles
    where profiles.id = current_profile_id
      and profiles.is_profile_complete = true
      and nullif(btrim(profiles.nickname), '') is not null
  ) then
    raise exception 'PROFILE_COMPLETION_REQUIRED';
  end if;

  if not public.has_accepted_community_terms(public.community_latest_terms_version()) then
    raise exception 'COMMUNITY_TERMS_REQUIRED';
  end if;

  select *
  into target_post
  from public.posts
  where id = p_post_id
    and status = 'published';

  if not found then
    raise exception 'COMMUNITY_POST_NOT_FOUND';
  end if;

  if target_post.author_id = current_profile_id then
    raise exception 'CANNOT_LIKE_OWN_POST';
  end if;

  if exists (
    select 1
    from public.community_blocks blocks
    where blocks.blocker_id = current_profile_id
      and blocks.blocked_id = target_post.author_id
  ) then
    raise exception 'COMMUNITY_POST_NOT_FOUND';
  end if;

  if exists (
    select 1
    from public.post_likes
    where post_id = p_post_id
      and user_id = current_profile_id
  ) then
    delete from public.post_likes
    where post_id = p_post_id
      and user_id = current_profile_id;
  else
    insert into public.post_likes (post_id, user_id, created_at)
    values (p_post_id, current_profile_id, now());
    did_create := true;
  end if;

  if did_create and target_post.author_id <> current_profile_id then
    perform public.create_community_notification(
      target_post.author_id,
      current_profile_id,
      p_post_id,
      null,
      'like',
      coalesce((
        select nullif(btrim(nickname), '')
        from public.profiles
        where id = current_profile_id
      ), '北林同学') || ' 点赞了你的帖子',
      target_post.title
    );
  end if;

  return public.community_post_summary_v1(p_post_id);
end;
$$;

create or replace function public.toggle_post_favorite_v1(p_post_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_profile_id uuid := public.current_profile_id();
  target_post public.posts%rowtype;
begin
  if current_profile_id is null then
    raise exception 'COMMUNITY_PROFILE_REQUIRED';
  end if;

  if not exists (
    select 1
    from public.profiles
    where profiles.id = current_profile_id
      and profiles.is_profile_complete = true
      and nullif(btrim(profiles.nickname), '') is not null
  ) then
    raise exception 'PROFILE_COMPLETION_REQUIRED';
  end if;

  if not public.has_accepted_community_terms(public.community_latest_terms_version()) then
    raise exception 'COMMUNITY_TERMS_REQUIRED';
  end if;

  select *
  into target_post
  from public.posts
  where id = p_post_id
    and status = 'published';

  if not found then
    raise exception 'COMMUNITY_POST_NOT_FOUND';
  end if;

  if exists (
    select 1
    from public.community_blocks blocks
    where blocks.blocker_id = current_profile_id
      and blocks.blocked_id = target_post.author_id
  ) then
    raise exception 'COMMUNITY_POST_NOT_FOUND';
  end if;

  if exists (
    select 1
    from public.post_favorites
    where post_id = p_post_id
      and user_id = current_profile_id
  ) then
    delete from public.post_favorites
    where post_id = p_post_id
      and user_id = current_profile_id;
  else
    insert into public.post_favorites (post_id, user_id, created_at)
    values (p_post_id, current_profile_id, now());
  end if;

  return public.community_post_summary_v1(p_post_id);
end;
$$;

revoke all on function public.refresh_post_like_count(uuid) from public, anon, authenticated;
revoke all on function public.handle_post_like_count_sync() from public, anon, authenticated;
revoke all on function public.community_feed_v1(text, text, integer) from public, anon, authenticated;
revoke all on function public.community_post_summary_v1(uuid) from public, anon, authenticated;
revoke all on function public.toggle_post_like_v1(uuid) from public, anon, authenticated;
revoke all on function public.toggle_post_favorite_v1(uuid) from public, anon, authenticated;

grant execute on function public.community_feed_v1(text, text, integer) to authenticated, service_role;
grant execute on function public.community_post_summary_v1(uuid) to authenticated, service_role;
grant execute on function public.toggle_post_like_v1(uuid) to authenticated;
grant execute on function public.toggle_post_favorite_v1(uuid) to authenticated;

grant select, insert, delete on table public.post_images to authenticated;
grant select, insert, update on table public.posts to authenticated;
grant select, insert, delete on table public.post_likes to authenticated, service_role;
grant select, insert, delete on table public.post_favorites to authenticated, service_role;
grant select, insert, update, delete on table public.post_images to service_role;
grant select, insert, update, delete on table public.posts to service_role;

select pg_notify('pgrst', 'reload schema');
