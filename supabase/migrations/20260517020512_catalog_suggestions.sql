create table if not exists public.catalog_suggestions (
  id uuid primary key default gen_random_uuid(),
  suggestion_type text not null,
  user_id uuid references public.profiles (id) on delete set null on update cascade,
  name text not null,
  unit text not null,
  category text,
  credit numeric(4, 1),
  note text,
  status text not null default 'open',
  approved_teacher_id bigint references public.teachers (id) on delete set null on update cascade,
  approved_course_id bigint references public.course_catalog (id) on delete set null on update cascade,
  admin_note text,
  reviewed_by uuid references public.admin_accounts (id) on delete set null on update cascade,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  search_text text generated always as (
    lower(
      coalesce(name, '') || ' ' ||
      coalesce(unit, '') || ' ' ||
      coalesce(category, '') || ' ' ||
      coalesce(note, '')
    )
  ) stored,
  constraint catalog_suggestions_type_check check (suggestion_type in ('teacher', 'course')),
  constraint catalog_suggestions_status_check check (status in ('open', 'approved', 'rejected')),
  constraint catalog_suggestions_name_not_blank check (nullif(btrim(name), '') is not null),
  constraint catalog_suggestions_unit_not_blank check (nullif(btrim(unit), '') is not null),
  constraint catalog_suggestions_category_not_blank check (category is null or nullif(btrim(category), '') is not null),
  constraint catalog_suggestions_credit_valid check (credit is null or credit >= 0)
);

create index if not exists idx_catalog_suggestions_status_created_at
on public.catalog_suggestions (status, created_at desc);

create index if not exists idx_catalog_suggestions_type_status
on public.catalog_suggestions (suggestion_type, status, created_at desc);

create index if not exists idx_catalog_suggestions_user_id
on public.catalog_suggestions (user_id, created_at desc);

create index if not exists idx_catalog_suggestions_search_text
on public.catalog_suggestions (search_text);

create unique index if not exists idx_catalog_suggestions_open_unique
on public.catalog_suggestions (
  suggestion_type,
  lower(btrim(name)),
  lower(btrim(unit)),
  lower(btrim(coalesce(category, '')))
)
where status = 'open';

drop trigger if exists catalog_suggestions_set_updated_at on public.catalog_suggestions;
create trigger catalog_suggestions_set_updated_at
before update on public.catalog_suggestions
for each row
execute function public.set_updated_at();

alter table public.catalog_suggestions enable row level security;

drop policy if exists "catalog_suggestions_insert_authenticated" on public.catalog_suggestions;
create policy "catalog_suggestions_insert_authenticated"
on public.catalog_suggestions
for insert
to authenticated
with check (
  status = 'open'
  and approved_teacher_id is null
  and approved_course_id is null
  and admin_note is null
  and reviewed_by is null
  and reviewed_at is null
  and (user_id is null or public.can_use_profile(user_id))
);

revoke all privileges on table
  public.catalog_suggestions
from public, anon, authenticated, service_role;

grant insert on table
  public.catalog_suggestions
to authenticated;

grant select, insert, update, delete on table
  public.catalog_suggestions
to service_role;

select pg_notify('pgrst', 'reload schema');
