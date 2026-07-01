create or replace function public.enforce_post_rate_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  recent_post_count integer;
begin
  if auth.uid() is null then
    return new;
  end if;

  select count(*)
  into recent_post_count
  from public.posts
  where author_id = new.author_id
    and created_at >= now() - interval '1 hour';

  if recent_post_count >= 2 then
    raise exception 'POST_RATE_LIMIT_EXCEEDED';
  end if;

  new.created_at = now();
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists posts_enforce_rate_limit on public.posts;
create trigger posts_enforce_rate_limit
before insert on public.posts
for each row
execute function public.enforce_post_rate_limit();

create or replace function public.enforce_post_image_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  existing_image_count integer;
begin
  select count(*)
  into existing_image_count
  from public.post_images
  where post_id = new.post_id;

  if existing_image_count >= 4 then
    raise exception 'POST_IMAGE_LIMIT_EXCEEDED';
  end if;

  if new.sort_order < 0 or new.sort_order >= 4 then
    raise exception 'POST_IMAGE_LIMIT_EXCEEDED';
  end if;

  return new;
end;
$$;

drop trigger if exists post_images_enforce_image_limit on public.post_images;
create trigger post_images_enforce_image_limit
before insert on public.post_images
for each row
execute function public.enforce_post_image_limit();

notify pgrst, 'reload schema';
