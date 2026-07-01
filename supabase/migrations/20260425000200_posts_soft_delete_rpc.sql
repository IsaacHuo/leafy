create or replace function public.soft_delete_own_post(target_post_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  affected_count integer;
begin
  if auth.uid() is null then
    raise exception 'missing authenticated user';
  end if;

  update public.posts
  set
    status = 'deleted',
    updated_at = now()
  where id = target_post_id
    and author_id = auth.uid()
    and status = 'published';

  get diagnostics affected_count = row_count;

  if affected_count = 0 then
    if exists (
      select 1
      from public.posts
      where id = target_post_id
        and author_id = auth.uid()
        and status = 'deleted'
    ) then
      return;
    end if;

    raise exception 'post not found or not owned by current user';
  end if;
end;
$$;

revoke all on function public.soft_delete_own_post(uuid) from public;
grant execute on function public.soft_delete_own_post(uuid) to authenticated;
