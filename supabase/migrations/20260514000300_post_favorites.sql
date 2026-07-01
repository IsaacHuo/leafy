create table if not exists public.post_favorites (
  post_id uuid not null references public.posts (id) on delete cascade on update cascade,
  user_id uuid not null references public.profiles (id) on delete cascade on update cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);

create index if not exists idx_post_favorites_user_created_at
on public.post_favorites (user_id, created_at desc);

create index if not exists idx_post_favorites_post_id
on public.post_favorites (post_id);

alter table public.post_favorites enable row level security;

drop policy if exists "post_favorites_select_self" on public.post_favorites;
create policy "post_favorites_select_self"
on public.post_favorites
for select
to authenticated
using (public.can_use_profile(user_id));

drop policy if exists "post_favorites_insert_self" on public.post_favorites;
create policy "post_favorites_insert_self"
on public.post_favorites
for insert
to authenticated
with check (
  public.can_use_profile(user_id)
  and exists (
    select 1
    from public.profiles
    where profiles.id = post_favorites.user_id
      and profiles.is_profile_complete = true
      and nullif(btrim(profiles.nickname), '') is not null
  )
  and exists (
    select 1
    from public.posts
    where posts.id = post_favorites.post_id
      and posts.status = 'published'
  )
);

drop policy if exists "post_favorites_delete_self" on public.post_favorites;
create policy "post_favorites_delete_self"
on public.post_favorites
for delete
to authenticated
using (public.can_use_profile(user_id));

revoke all privileges on table public.post_favorites
from public, anon, authenticated, service_role;

grant select, insert, delete on table public.post_favorites to authenticated;
grant select, insert, update, delete on table public.post_favorites to service_role;

select pg_notify('pgrst', 'reload schema');
