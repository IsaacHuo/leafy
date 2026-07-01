alter table public.catalog_suggestions
  add column if not exists teacher_name text;

alter table public.catalog_suggestions
  drop constraint if exists catalog_suggestions_course_teacher_name_required;

alter table public.catalog_suggestions
  add constraint catalog_suggestions_course_teacher_name_required
  check (
    suggestion_type <> 'course'
    or status <> 'open'
    or nullif(btrim(teacher_name), '') is not null
  ) not valid;

drop index if exists public.idx_catalog_suggestions_open_unique;
drop index if exists public.idx_catalog_suggestions_search_text;

alter table public.catalog_suggestions
  drop column if exists search_text;

alter table public.catalog_suggestions
  add column search_text text generated always as (
    lower(
      coalesce(name, '') || ' ' ||
      coalesce(unit, '') || ' ' ||
      coalesce(teacher_name, '') || ' ' ||
      coalesce(category, '') || ' ' ||
      coalesce(note, '')
    )
  ) stored;

create index if not exists idx_catalog_suggestions_search_text
on public.catalog_suggestions (search_text);

create unique index if not exists idx_catalog_suggestions_open_unique
on public.catalog_suggestions (
  suggestion_type,
  lower(btrim(name)),
  lower(btrim(unit)),
  lower(btrim(coalesce(teacher_name, ''))),
  lower(btrim(coalesce(category, '')))
)
where status = 'open';

alter table public.catalog_suggestions enable row level security;

grant insert on table
  public.catalog_suggestions
to authenticated;

grant select, insert, update, delete on table
  public.catalog_suggestions
to service_role;

select pg_notify('pgrst', 'reload schema');
