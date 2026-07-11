#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
migration="$repo_root/supabase/migrations/20260710121000_admin_security_runtime.sql"

if [ ! -f "$migration" ]; then
  echo "missing Task 2 migration: $migration" >&2
  exit 1
fi

require_pattern() {
  pattern=$1
  description=$2
  if ! matches_pattern "$pattern"; then
    echo "missing migration contract: $description" >&2
    exit 1
  fi
}

matches_pattern() {
  python3 - "$1" "$migration" <<'PY'
import re
import sys

pattern, path = sys.argv[1:]
with open(path, encoding="utf-8") as source:
    content = source.read()
raise SystemExit(0 if re.search(pattern, content, re.MULTILINE) else 1)
PY
}

require_pattern 'create table if not exists public\.admin_login_attempts' 'service-only login-attempt table'
require_pattern "interval\\s+'15 minutes'" '15-minute rate-limit window'
require_pattern 'username_ip_attempt_count\s*>=\s*5' 'five-failure username and IP limit'
require_pattern 'ip_attempt_count\s*>=\s*20' 'twenty-failure IP limit'
require_pattern 'create or replace function public\.admin_begin_login_attempt' 'atomic login-attempt begin RPC'
require_pattern 'pg_advisory_xact_lock' 'transaction lock for concurrent login and config writes'
require_pattern 'create or replace function public\.admin_finish_login_attempt' 'login-attempt result RPC'
require_pattern "interval\\s+'90 days'" '90-day retention default'
require_pattern 'add column if not exists request_id' 'audit request_id'
require_pattern 'add column if not exists outcome' 'audit outcome'
require_pattern 'add column if not exists duration_ms' 'audit duration_ms'
require_pattern 'add column if not exists error_code' 'audit error_code'
require_pattern 'create extension if not exists pg_trgm with schema extensions' 'pg_trgm extension'
require_pattern 'idx_posts_admin_search_fts' 'post full-text index'
require_pattern 'idx_profiles_admin_search_trgm' 'profile trigram index'
require_pattern 'idx_comments_admin_search_trgm' 'comment trigram index'
require_pattern 'idx_postgraduate_sources_admin_search_trgm' 'postgraduate source trigram index'
require_pattern 'create or replace function public\.admin_upsert_semester_runtime_config' 'atomic semester RPC'
require_pattern 'create or replace function public\.admin_upsert_national_calendar_runtime_config' 'atomic national-calendar RPC'
require_pattern 'revoke all on function public\.admin_upsert_semester_runtime_config[\s\S]*from public, anon, authenticated, service_role' 'semester RPC execute reset'
require_pattern 'revoke all on function public\.admin_upsert_national_calendar_runtime_config[\s\S]*from public, anon, authenticated, service_role' 'national-calendar RPC execute reset'
require_pattern 'grant execute on function public\.admin_upsert_semester_runtime_config[\s\S]*to service_role' 'semester RPC service-role grant'
require_pattern 'grant execute on function public\.admin_upsert_national_calendar_runtime_config[\s\S]*to service_role' 'national-calendar RPC service-role grant'
require_pattern 'grant execute on function public\.admin_begin_login_attempt[\s\S]*to service_role' 'login-attempt begin service-role grant'
require_pattern 'grant execute on function public\.admin_finish_login_attempt[\s\S]*to service_role' 'login-attempt finish service-role grant'

if matches_pattern '(?i)(create|alter|drop)\s+policy|alter\s+table\s+public\.(?!admin_login_attempts\b)[a-z0-9_]+\s+(enable|disable|force|no force)\s+row\s+level\s+security'; then
  echo 'migration must not modify existing application RLS or policies' >&2
  exit 1
fi

echo 'admin security/runtime migration static verification passed'
