create table if not exists public.campus_weather_cache (
  cache_key text primary key,
  temperature double precision not null,
  condition_key text not null,
  observed_at timestamptz not null,
  source text not null,
  updated_at timestamptz not null default now()
);

alter table public.campus_weather_cache enable row level security;

revoke all on table public.campus_weather_cache from anon;
revoke all on table public.campus_weather_cache from authenticated;
