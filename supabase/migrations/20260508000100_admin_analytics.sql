create or replace function public.admin_daily_counts(
  p_days integer default 30,
  p_timezone text default 'UTC'
)
returns table (
  bucket_date date,
  profiles integer,
  posts integer,
  comments integer,
  feedback integer,
  ratings integer
)
language sql
security definer
stable
set search_path = public
as $$
  with bounds as (
    select
      least(greatest(coalesce(p_days, 30), 1), 90)::integer as days,
      coalesce(nullif(btrim(p_timezone), ''), 'UTC') as zone
  ),
  buckets as (
    select generate_series(
      ((now() at time zone bounds.zone)::date - (bounds.days - 1)),
      (now() at time zone bounds.zone)::date,
      interval '1 day'
    )::date as bucket_date
    from bounds
  ),
  profile_counts as (
    select (created_at at time zone bounds.zone)::date as bucket_date, count(*)::integer as total
    from public.profiles, bounds
    where (created_at at time zone bounds.zone)::date >= ((now() at time zone bounds.zone)::date - (bounds.days - 1))
    group by 1
  ),
  post_counts as (
    select (created_at at time zone bounds.zone)::date as bucket_date, count(*)::integer as total
    from public.posts, bounds
    where (created_at at time zone bounds.zone)::date >= ((now() at time zone bounds.zone)::date - (bounds.days - 1))
    group by 1
  ),
  comment_counts as (
    select (created_at at time zone bounds.zone)::date as bucket_date, count(*)::integer as total
    from public.comments, bounds
    where (created_at at time zone bounds.zone)::date >= ((now() at time zone bounds.zone)::date - (bounds.days - 1))
    group by 1
  ),
  feedback_counts as (
    select (created_at at time zone bounds.zone)::date as bucket_date, count(*)::integer as total
    from public.feedback_submissions, bounds
    where (created_at at time zone bounds.zone)::date >= ((now() at time zone bounds.zone)::date - (bounds.days - 1))
    group by 1
  ),
  rating_counts as (
    select (created_at at time zone bounds.zone)::date as bucket_date, count(*)::integer as total
    from public.teacher_ratings, bounds
    where (created_at at time zone bounds.zone)::date >= ((now() at time zone bounds.zone)::date - (bounds.days - 1))
    group by 1
  )
  select
    buckets.bucket_date,
    coalesce(profile_counts.total, 0),
    coalesce(post_counts.total, 0),
    coalesce(comment_counts.total, 0),
    coalesce(feedback_counts.total, 0),
    coalesce(rating_counts.total, 0)
  from buckets
  left join profile_counts using (bucket_date)
  left join post_counts using (bucket_date)
  left join comment_counts using (bucket_date)
  left join feedback_counts using (bucket_date)
  left join rating_counts using (bucket_date)
  order by buckets.bucket_date asc;
$$;

create or replace function public.admin_activity_heatmap(
  p_days integer default 30,
  p_timezone text default 'UTC'
)
returns table (
  weekday integer,
  hour integer,
  posts integer,
  comments integer,
  feedback integer
)
language sql
security definer
stable
set search_path = public
as $$
  with bounds as (
    select
      least(greatest(coalesce(p_days, 30), 1), 90)::integer as days,
      coalesce(nullif(btrim(p_timezone), ''), 'UTC') as zone
  ),
  buckets as (
    select weekday, hour
    from generate_series(0, 6) as weekday
    cross join generate_series(0, 23) as hour
  ),
  events as (
    select
      extract(dow from created_at at time zone bounds.zone)::integer as weekday,
      extract(hour from created_at at time zone bounds.zone)::integer as hour,
      'posts'::text as kind
    from public.posts, bounds
    where (created_at at time zone bounds.zone)::date >= ((now() at time zone bounds.zone)::date - (bounds.days - 1))
    union all
    select
      extract(dow from created_at at time zone bounds.zone)::integer,
      extract(hour from created_at at time zone bounds.zone)::integer,
      'comments'::text
    from public.comments, bounds
    where (created_at at time zone bounds.zone)::date >= ((now() at time zone bounds.zone)::date - (bounds.days - 1))
    union all
    select
      extract(dow from created_at at time zone bounds.zone)::integer,
      extract(hour from created_at at time zone bounds.zone)::integer,
      'feedback'::text
    from public.feedback_submissions, bounds
    where (created_at at time zone bounds.zone)::date >= ((now() at time zone bounds.zone)::date - (bounds.days - 1))
  )
  select
    buckets.weekday,
    buckets.hour,
    count(*) filter (where events.kind = 'posts')::integer,
    count(*) filter (where events.kind = 'comments')::integer,
    count(*) filter (where events.kind = 'feedback')::integer
  from buckets
  left join events using (weekday, hour)
  group by buckets.weekday, buckets.hour
  order by buckets.weekday asc, buckets.hour asc;
$$;

create or replace function public.admin_category_mix(
  p_days integer default 30,
  p_timezone text default 'UTC'
)
returns table (
  category text,
  posts integer,
  comments integer
)
language sql
security definer
stable
set search_path = public
as $$
  with bounds as (
    select
      least(greatest(coalesce(p_days, 30), 1), 90)::integer as days,
      coalesce(nullif(btrim(p_timezone), ''), 'UTC') as zone
  ),
  filtered_posts as (
    select
      posts.id,
      coalesce(nullif(btrim(posts.category), ''), '未分类') as category
    from public.posts, bounds
    where (posts.created_at at time zone bounds.zone)::date >= ((now() at time zone bounds.zone)::date - (bounds.days - 1))
  )
  select
    filtered_posts.category,
    count(distinct filtered_posts.id)::integer as posts,
    count(comments.id)::integer as comments
  from filtered_posts
  left join public.comments on comments.post_id = filtered_posts.id
  group by filtered_posts.category
  order by posts desc, comments desc, filtered_posts.category asc
  limit 10;
$$;

create or replace function public.admin_top_content(
  p_days integer default 30,
  p_timezone text default 'UTC',
  p_limit integer default 8
)
returns table (
  id uuid,
  title text,
  category text,
  author_id uuid,
  status text,
  created_at timestamptz,
  comment_count integer,
  like_count integer,
  score integer
)
language sql
security definer
stable
set search_path = public
as $$
  with bounds as (
    select
      least(greatest(coalesce(p_days, 30), 1), 90)::integer as days,
      coalesce(nullif(btrim(p_timezone), ''), 'UTC') as zone,
      least(greatest(coalesce(p_limit, 8), 1), 20)::integer as row_limit
  ),
  likes as (
    select post_id, count(*)::integer as like_count
    from public.post_likes
    group by post_id
  )
  select
    posts.id,
    posts.title,
    coalesce(nullif(btrim(posts.category), ''), '未分类') as category,
    posts.author_id,
    posts.status,
    posts.created_at,
    posts.comment_count,
    coalesce(likes.like_count, 0) as like_count,
    (posts.comment_count * 3 + coalesce(likes.like_count, 0))::integer as score
  from public.posts
  cross join bounds
  left join likes on likes.post_id = posts.id
  where (posts.created_at at time zone bounds.zone)::date >= ((now() at time zone bounds.zone)::date - (bounds.days - 1))
    and posts.status <> 'deleted'
  order by score desc, posts.created_at desc
  limit (select row_limit from bounds);
$$;

revoke all on function public.admin_daily_counts(integer, text) from public;
revoke all on function public.admin_daily_counts(integer, text) from authenticated;
revoke all on function public.admin_activity_heatmap(integer, text) from public;
revoke all on function public.admin_activity_heatmap(integer, text) from authenticated;
revoke all on function public.admin_category_mix(integer, text) from public;
revoke all on function public.admin_category_mix(integer, text) from authenticated;
revoke all on function public.admin_top_content(integer, text, integer) from public;
revoke all on function public.admin_top_content(integer, text, integer) from authenticated;

grant execute on function public.admin_daily_counts(integer, text) to service_role;
grant execute on function public.admin_activity_heatmap(integer, text) to service_role;
grant execute on function public.admin_category_mix(integer, text) to service_role;
grant execute on function public.admin_top_content(integer, text, integer) to service_role;

select pg_notify('pgrst', 'reload schema');
