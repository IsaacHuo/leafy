drop policy if exists "posts_update_self" on public.posts;
create policy "posts_update_self"
on public.posts
for update
to authenticated
using (
  auth.uid() = author_id
  and status = 'published'
)
with check (
  auth.uid() = author_id
  and status in ('published', 'deleted')
);
