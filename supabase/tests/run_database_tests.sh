#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source_migration="${repo_root}/supabase/migrations/20260722113000_community_school_identity_inheritance.sql"
replay_fixture="${repo_root}/supabase/tests/.community_school_identity_inheritance.replay.inc"

cleanup() {
  rm -f "${replay_fixture}"
}
trap cleanup EXIT

cp "${source_migration}" "${replay_fixture}"
supabase test db "$@"
