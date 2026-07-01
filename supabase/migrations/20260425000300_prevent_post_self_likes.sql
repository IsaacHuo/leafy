delete from public.post_likes
using public.posts
where post_likes.post_id = posts.id
  and post_likes.user_id = posts.author_id;

drop policy if exists "post_likes_insert_self" on public.post_likes;
create policy "post_likes_insert_self"
on public.post_likes
for insert
to authenticated
with check (
  auth.uid() = user_id
  and exists (
    select 1
    from public.profiles
    where profiles.id = auth.uid()
      and profiles.is_profile_complete = true
      and nullif(btrim(profiles.nickname), '') is not null
  )
  and exists (
    select 1
    from public.posts
    where posts.id = post_likes.post_id
      and posts.status = 'published'
      and posts.author_id <> auth.uid()
  )
);

create or replace function public.prevent_post_self_like()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (
    select 1
    from public.posts
    where posts.id = new.post_id
      and posts.author_id = new.user_id
  ) then
    raise exception 'CANNOT_LIKE_OWN_POST';
  end if;

  return new;
end;
$$;

drop trigger if exists post_likes_prevent_self_like on public.post_likes;
create trigger post_likes_prevent_self_like
before insert or update on public.post_likes
for each row
execute function public.prevent_post_self_like();

select pg_notify('pgrst', 'reload schema');
