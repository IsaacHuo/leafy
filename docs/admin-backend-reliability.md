# Admin backend reliability

The `/admin` backend exposes exactly 65 `admin-community` actions. The machine-readable review matrix is
`supabase/functions/admin-community/action-audit.ts`; its contract test compares every action name, role,
mutation flag, campus policy, transaction boundary, and audit target with the runtime registry.

## Write boundaries

- Catalog approval, postgraduate suggestion approval, campus approval, report resolution, post pinning, and
  post moderation use service-role-only transaction RPCs from migration
  `20260722160000_admin_backend_hardening.sql`.
- A catalog suggestion with `initial_stars = NULL` creates no rating. Approval locks the suggestion and reuses
  a normalized campus-scoped catalog row, so retrying a previously interrupted approval cannot create a duplicate.
- Reports never hide content implicitly. Content changes only when `hideContent=true` is sent explicitly.
- Author-deleted posts and comments are terminal. Admin moderation cannot restore or rewrite them.
- Creating a teacher, course, or dish requires an explicit campus in both the web UI and Edge Function.

## Request and error contract

Admin browser traffic must pass through the same-origin Cloudflare BFF and carry `ADMIN_PROXY_SECRET` to every
admin Edge Function. JSON writes are limited to 256 KiB. Malformed JSON and non-JSON bodies are rejected before
dispatch. Expected database failures map to 400/404/409 responses; only infrastructure failures become a
sanitized 500. The browser response always carries an `X-Request-ID`, and audit/last-seen failures log that ID.

## Release order

Deploy the database migration first, then `admin-login`, `admin-me`, `admin-logout`, `admin-community`, and
`admin-export`, then publish the site. Do not auto-review pending production suggestions in a migration. After all
layers are live, retry the pending suggestion from the production UI and verify the approved target, rating count,
teacher count, audit record, and consistency queries.
