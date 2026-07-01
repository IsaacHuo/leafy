#!/usr/bin/env bash
set -euo pipefail

: "${SUPABASE_DB_URL:?Set SUPABASE_DB_URL to the Postgres connection string.}"
: "${ADMIN_USERNAME:?Set ADMIN_USERNAME.}"
: "${ADMIN_PASSWORD:?Set ADMIN_PASSWORD.}"

ADMIN_DISPLAY_NAME="${ADMIN_DISPLAY_NAME:-$ADMIN_USERNAME}"
ADMIN_ROLE="${ADMIN_ROLE:-super_admin}"

psql "$SUPABASE_DB_URL" \
  -v username="$ADMIN_USERNAME" \
  -v password="$ADMIN_PASSWORD" \
  -v display_name="$ADMIN_DISPLAY_NAME" \
  -v role="$ADMIN_ROLE" \
  -c "select id, username, display_name, role, active, created_at from public.admin_create_account(:'username', :'password', :'display_name', :'role', null);"
