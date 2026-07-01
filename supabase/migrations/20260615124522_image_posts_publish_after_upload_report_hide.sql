create schema if not exists private;

-- Image posts no longer require manual review. Existing image posts that were
-- waiting only because they contained images should become visible.
update public.posts
set
  status = 'published',
  moderated_by = null,
  moderated_at = null,
  moderation_reason = null,
  updated_at = now()
where status = 'pending_review'
  and exists (
    select 1
    from public.post_images
    where post_images.post_id = posts.id
  );

create or replace function private.publish_post_after_image_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.posts
  set
    status = 'published',
    updated_at = now()
  where id = new.post_id
    and status = 'pending_review';

  return new;
end;
$$;

drop trigger if exists post_images_publish_post_after_insert on public.post_images;
create trigger post_images_publish_post_after_insert
after insert on public.post_images
for each row
execute function private.publish_post_after_image_insert();

revoke all on function private.publish_post_after_image_insert() from public, anon, authenticated;

-- A user report immediately removes visible content from feeds while keeping
-- the report open for the admin queue.
create or replace function public.report_community_content(
  p_target_type text,
  p_post_id uuid default null,
  p_comment_id uuid default null,
  p_reported_user_id uuid default null,
  p_reason text default '违规内容',
  p_detail text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_profile_id uuid := public.current_community_profile_id();
  target_author_id uuid;
  target_post_id uuid;
  created_report_id uuid;
  normalized_target_type text := lower(nullif(btrim(coalesce(p_target_type, '')), ''));
  normalized_reason text := coalesce(nullif(btrim(p_reason), ''), '违规内容');
begin
  if current_profile_id is null then
    raise exception 'COMMUNITY_PROFILE_REQUIRED';
  end if;

  if normalized_target_type = 'post' then
    select author_id into target_author_id
    from public.posts
    where id = p_post_id;

    if target_author_id is null then
      raise exception 'COMMUNITY_REPORT_TARGET_NOT_FOUND';
    end if;

    target_post_id := p_post_id;

    update public.posts
    set
      status = 'hidden',
      moderated_by = null,
      moderated_at = now(),
      moderation_reason = 'Hidden automatically after user report'
    where id = p_post_id
      and status = 'published';
  elsif normalized_target_type = 'comment' then
    select author_id, post_id into target_author_id, target_post_id
    from public.comments
    where id = p_comment_id;

    if target_author_id is null then
      raise exception 'COMMUNITY_REPORT_TARGET_NOT_FOUND';
    end if;

    update public.comments
    set
      status = 'hidden',
      moderated_by = null,
      moderated_at = now(),
      moderation_reason = 'Hidden automatically after user report'
    where id = p_comment_id
      and status = 'published';
  elsif normalized_target_type = 'user' then
    target_author_id := p_reported_user_id;
    if target_author_id is null or not exists (select 1 from public.profiles where id = target_author_id) then
      raise exception 'COMMUNITY_REPORT_TARGET_NOT_FOUND';
    end if;
  else
    raise exception 'COMMUNITY_INVALID_REPORT_TARGET';
  end if;

  insert into public.community_reports (
    reporter_id,
    reported_user_id,
    target_type,
    post_id,
    comment_id,
    reason,
    detail,
    status
  )
  values (
    current_profile_id,
    target_author_id,
    normalized_target_type,
    case when normalized_target_type = 'post' then p_post_id when normalized_target_type = 'comment' then target_post_id else null end,
    case when normalized_target_type = 'comment' then p_comment_id else null end,
    normalized_reason,
    nullif(btrim(coalesce(p_detail, '')), ''),
    'open'
  )
  returning id into created_report_id;

  return created_report_id;
end;
$$;

revoke all on function public.report_community_content(text, uuid, uuid, uuid, text, text) from public;
grant execute on function public.report_community_content(text, uuid, uuid, uuid, text, text) to authenticated;

select pg_notify('pgrst', 'reload schema');
