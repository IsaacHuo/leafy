-- Keep future community feed pinning to one active pinned post per campus.
-- Existing rows are left untouched until a new pin is inserted or reactivated.

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
grant usage on schema private to authenticated, service_role;

create or replace function private.community_post_pins_keep_single_active()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'active' then
    update public.community_post_pins pins
    set
      status = 'inactive',
      updated_at = now()
    where pins.status = 'active'
      and pins.id <> new.id
      and coalesce(pins.campus_id, 'bjfu') = coalesce(new.campus_id, 'bjfu');
  end if;

  return new;
end;
$$;

drop trigger if exists community_post_pins_keep_single_active on public.community_post_pins;
create trigger community_post_pins_keep_single_active
before insert or update of status, campus_id on public.community_post_pins
for each row
execute function private.community_post_pins_keep_single_active();

-- Enforce the post category length for future writes without modifying existing posts.
create or replace function private.posts_category_max_8_chars_guard()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.category is not null and char_length(btrim(new.category)) > 8 then
    raise exception 'Post category must be 8 characters or fewer.';
  end if;

  return new;
end;
$$;

drop trigger if exists posts_category_max_8_chars_guard on public.posts;
create trigger posts_category_max_8_chars_guard
before insert or update of category on public.posts
for each row
execute function private.posts_category_max_8_chars_guard();

comment on function private.community_post_pins_keep_single_active() is
  'Deactivates other active post pins in the same campus when a new active pin is written.';

comment on function private.posts_category_max_8_chars_guard() is
  'Rejects future post category writes longer than 8 characters without rewriting historical posts.';

revoke all on function private.community_post_pins_keep_single_active() from public, anon, authenticated;
revoke all on function private.posts_category_max_8_chars_guard() from public, anon, authenticated;

select pg_notify('pgrst', 'reload schema');
