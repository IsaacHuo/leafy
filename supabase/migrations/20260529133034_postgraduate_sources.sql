create table if not exists public.postgraduate_sources (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  summary text not null default '',
  source_url text not null,
  source_kind text not null default 'other',
  trust_level text not null default 'curated',
  school text,
  unit text,
  major text,
  exam_year integer,
  published_at timestamptz,
  verified_at timestamptz,
  status text not null default 'published',
  created_by uuid references public.admin_accounts (id) on delete set null on update cascade,
  updated_by uuid references public.admin_accounts (id) on delete set null on update cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  search_text text generated always as (
    lower(
      coalesce(title, '') || ' ' ||
      coalesce(summary, '') || ' ' ||
      coalesce(school, '') || ' ' ||
      coalesce(unit, '') || ' ' ||
      coalesce(major, '') || ' ' ||
      coalesce(source_url, '')
    )
  ) stored,
  constraint postgraduate_sources_title_not_blank check (nullif(btrim(title), '') is not null),
  constraint postgraduate_sources_url_not_blank check (nullif(btrim(source_url), '') is not null),
  constraint postgraduate_sources_source_kind_check check (
    source_kind in (
      'admission_notice',
      'major_catalog',
      'score_line',
      'enrollment_plan',
      'bibliography',
      'retest',
      'registration',
      'other'
    )
  ),
  constraint postgraduate_sources_trust_level_check check (trust_level in ('official', 'curated', 'verified_user')),
  constraint postgraduate_sources_status_check check (status in ('published', 'hidden', 'archived')),
  constraint postgraduate_sources_exam_year_valid check (exam_year is null or exam_year between 2000 and 2100)
);

create table if not exists public.postgraduate_source_suggestions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.profiles (id) on delete set null on update cascade,
  title text not null,
  source_url text not null,
  school text,
  unit text,
  major text,
  exam_year integer,
  source_kind text not null default 'other',
  note text,
  status text not null default 'open',
  approved_source_id uuid references public.postgraduate_sources (id) on delete set null on update cascade,
  admin_note text,
  reviewed_by uuid references public.admin_accounts (id) on delete set null on update cascade,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  search_text text generated always as (
    lower(
      coalesce(title, '') || ' ' ||
      coalesce(source_url, '') || ' ' ||
      coalesce(school, '') || ' ' ||
      coalesce(unit, '') || ' ' ||
      coalesce(major, '') || ' ' ||
      coalesce(note, '')
    )
  ) stored,
  constraint postgraduate_source_suggestions_title_not_blank check (nullif(btrim(title), '') is not null),
  constraint postgraduate_source_suggestions_url_not_blank check (nullif(btrim(source_url), '') is not null),
  constraint postgraduate_source_suggestions_source_kind_check check (
    source_kind in (
      'admission_notice',
      'major_catalog',
      'score_line',
      'enrollment_plan',
      'bibliography',
      'retest',
      'registration',
      'other'
    )
  ),
  constraint postgraduate_source_suggestions_status_check check (status in ('open', 'approved', 'rejected')),
  constraint postgraduate_source_suggestions_exam_year_valid check (exam_year is null or exam_year between 2000 and 2100)
);

create index if not exists idx_postgraduate_sources_status_verified
on public.postgraduate_sources (status, verified_at desc, published_at desc, created_at desc);

create index if not exists idx_postgraduate_sources_scope
on public.postgraduate_sources (school, major, exam_year)
where status = 'published';

create index if not exists idx_postgraduate_sources_search_text
on public.postgraduate_sources (search_text);

create index if not exists idx_postgraduate_source_suggestions_user_created
on public.postgraduate_source_suggestions (user_id, created_at desc);

create index if not exists idx_postgraduate_source_suggestions_status_created
on public.postgraduate_source_suggestions (status, created_at desc);

create index if not exists idx_postgraduate_source_suggestions_search_text
on public.postgraduate_source_suggestions (search_text);

create unique index if not exists idx_postgraduate_suggestions_open_unique
on public.postgraduate_source_suggestions (
  lower(btrim(source_url)),
  lower(btrim(coalesce(school, ''))),
  lower(btrim(coalesce(major, ''))),
  coalesce(exam_year, 0)
)
where status = 'open';

drop trigger if exists postgraduate_sources_set_updated_at on public.postgraduate_sources;
create trigger postgraduate_sources_set_updated_at
before update on public.postgraduate_sources
for each row
execute function public.set_updated_at();

drop trigger if exists postgraduate_source_suggestions_set_updated_at on public.postgraduate_source_suggestions;
create trigger postgraduate_source_suggestions_set_updated_at
before update on public.postgraduate_source_suggestions
for each row
execute function public.set_updated_at();

alter table public.postgraduate_sources enable row level security;
alter table public.postgraduate_source_suggestions enable row level security;

drop policy if exists "postgraduate_sources_select_published_authenticated" on public.postgraduate_sources;
create policy "postgraduate_sources_select_published_authenticated"
on public.postgraduate_sources
for select
to authenticated
using (status = 'published');

drop policy if exists "postgraduate_source_suggestions_select_self" on public.postgraduate_source_suggestions;
create policy "postgraduate_source_suggestions_select_self"
on public.postgraduate_source_suggestions
for select
to authenticated
using (user_id is not null and public.can_use_profile(user_id));

drop policy if exists "postgraduate_source_suggestions_insert_self" on public.postgraduate_source_suggestions;
create policy "postgraduate_source_suggestions_insert_self"
on public.postgraduate_source_suggestions
for insert
to authenticated
with check (
  status = 'open'
  and approved_source_id is null
  and admin_note is null
  and reviewed_by is null
  and reviewed_at is null
  and user_id is not null
  and public.can_use_profile(user_id)
);

revoke all privileges on table
  public.postgraduate_sources,
  public.postgraduate_source_suggestions
from public, anon, authenticated, service_role;

grant select on table public.postgraduate_sources to authenticated;
grant select, insert on table public.postgraduate_source_suggestions to authenticated;

grant select, insert, update, delete on table
  public.postgraduate_sources,
  public.postgraduate_source_suggestions
to service_role;

insert into public.postgraduate_sources (
  title,
  summary,
  source_url,
  source_kind,
  trust_level,
  school,
  unit,
  major,
  exam_year,
  published_at,
  verified_at,
  status
)
values
  (
    '中国研究生招生信息网',
    '报名、调剂、硕士专业目录和招生单位信息的官方入口。',
    'https://yz.chsi.com.cn/',
    'registration',
    'official',
    null,
    null,
    null,
    null,
    null,
    now(),
    'published'
  ),
  (
    '学信网',
    '用于学籍学历查询、账号校验和报名相关身份信息核对。',
    'https://www.chsi.com.cn/',
    'registration',
    'official',
    null,
    null,
    null,
    null,
    null,
    now(),
    'published'
  ),
  (
    '北京林业大学研究生院',
    '北林研究生招生通知、专业目录、复试录取和历年统计的官方入口。',
    'https://graduate.bjfu.edu.cn/',
    'admission_notice',
    'official',
    '北京林业大学',
    null,
    null,
    null,
    null,
    now(),
    'published'
  )
on conflict do nothing;

comment on table public.postgraduate_sources is 'Reviewed postgraduate information sources displayed by the iOS app.';
comment on table public.postgraduate_source_suggestions is 'User-submitted postgraduate source leads awaiting operator review.';

select pg_notify('pgrst', 'reload schema');
