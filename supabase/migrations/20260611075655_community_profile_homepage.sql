alter table public.profiles
  add column if not exists bio text,
  add column if not exists shows_edu_verification_badge boolean not null default false;
