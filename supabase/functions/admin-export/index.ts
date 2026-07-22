import {
  actionMeta,
  appendAuditLog,
  authenticateAdmin,
  corsHeaders,
  databaseError,
  errorCodeFor,
  HttpError,
  mapFunctionError,
  normalizeDate,
  normalizeText,
  readJSON,
  requirePost,
} from "../_shared/admin-core.ts";
import { roleCanExport } from "../_shared/admin-permissions.ts";
import { toCSV } from "../_shared/admin-csv.ts";

type ExportRequest = {
  resource?: string;
  filters?: Record<string, unknown>;
  sort?: { field?: string; order?: string };
};

type ExportConfig = {
  table: string;
  columns: readonly string[];
  campusColumn?: string;
  searchColumn?: string;
  dateColumn?: string;
  defaultSort: string;
  select?: string;
};

const configs: Record<string, ExportConfig> = {
  posts: config("posts", ["id", "campus_id", "author_id", "title", "body", "category", "status", "moderation_reason", "created_at", "updated_at"], "campus_id", "title"),
  polls: config("community_polls", ["id", "campus_id", "author_id", "question", "detail", "status", "total_vote_count", "closes_at", "moderation_reason", "created_at", "updated_at"], "campus_id", "question"),
  comments: { ...config("comments", ["id", "post_id", "author_id", "body", "status", "moderation_reason", "created_at", "updated_at"], undefined, "body"), select: "id,post_id,author_id,body,status,moderation_reason,created_at,updated_at,posts!inner(campus_id)" },
  reports: config("community_reports", ["id", "reporter_id", "reported_user_id", "target_type", "post_id", "comment_id", "reason", "detail", "status", "resolution_note", "created_at", "resolved_at"], undefined, "reason"),
  announcements: config("site_announcements", ["id", "campus_id", "title", "body", "level", "status", "published_at", "expires_at", "created_at", "updated_at"], "campus_id", "title"),
  postgraduate: config("postgraduate_sources", ["id", "title", "summary", "source_url", "source_kind", "trust_level", "school", "unit", "major", "exam_year", "status", "verified_at", "created_at", "updated_at"], undefined, "title"),
  suggestions: config("catalog_suggestions", ["id", "campus_id", "suggestion_type", "user_id", "name", "unit", "category", "credit", "note", "status", "admin_note", "created_at", "updated_at"], "campus_id", "name"),
  teachers: config("teachers", ["id", "campus_id", "name", "unit", "status", "rating_average", "rating_count", "created_at", "updated_at"], "campus_id", "name"),
  courses: config("course_catalog", ["id", "campus_id", "name", "unit", "category", "credit", "status", "rating_average", "rating_count", "created_at", "updated_at"], "campus_id", "name"),
  dishes: config("dish_catalog", ["id", "campus_id", "name", "location", "status", "rating_average", "rating_count", "created_at", "updated_at"], "campus_id", "name"),
  ratings: { table: "teacher_ratings", columns: ["target", "teacher_id", "dish_id", "user_id", "stars", "created_at", "updated_at"], defaultSort: "updated_at", dateColumn: "created_at" },
  profiles: config("profiles", ["id", "community_campus_id", "edu_id", "nickname", "display_name", "bound_email", "is_profile_complete", "muted_until", "mute_reason", "created_at", "updated_at"], "community_campus_id", "nickname"),
  feedback: config("feedback_submissions", ["id", "campus_id", "user_id", "issue_type", "body", "contact", "status", "admin_note", "created_at", "reviewed_at"], "campus_id", "body"),
  admins: config("admin_accounts", ["id", "username", "display_name", "role", "active", "last_login_at", "created_at", "updated_at"], undefined, "username"),
  sessions: config("admin_sessions", ["admin_id", "expires_at", "last_seen_at", "revoked_at", "created_at"], undefined, undefined),
  "audit-logs": config("admin_audit_logs", ["id", "admin_id", "action", "target_type", "target_id", "outcome", "duration_ms", "error_code", "ip_address", "created_at"], undefined, "action"),
};

Deno.serve(async (request) => {
  const requestId = request.headers.get("x-request-id") || crypto.randomUUID();
  const methodResponse = requirePost(request);
  if (methodResponse) return methodResponse;

  let context: Awaited<ReturnType<typeof authenticateAdmin>> | null = null;
  try {
    context = await authenticateAdmin(request);
    if (context instanceof Response) return context;

    const body = await readJSON<ExportRequest>(request);
    const resource = normalizeText(body.resource);
    if (!resource || !configs[resource]) throw new HttpError(400, "Unsupported export resource.");
    if (!roleCanExport(context.admin.role, resource)) throw new HttpError(403, "This account cannot export the requested resource.");

    const rows = await loadRows(context.adminClient, resource, configs[resource], body.filters ?? {}, body.sort);
    const auditLogged = await appendAuditLog(context, "exportResource", {
      resource,
      filters: body.filters ?? {},
      rowCount: rows.length,
    }, { type: "export", id: resource });
    const meta = actionMeta(context, auditLogged);
    const filename = `leafy-${resource}-${new Date().toISOString().slice(0, 10)}.csv`;
    return new Response(toCSV(configs[resource].columns, rows), {
      status: 200,
      headers: {
        ...corsHeaders,
        "Content-Type": "text/csv; charset=utf-8",
        "Content-Disposition": `attachment; filename="${filename}"`,
        "X-Request-ID": meta.request_id,
        "X-Audit-Logged": String(meta.audit_logged),
      },
    });
  } catch (error) {
    if (context && !(context instanceof Response)) {
      await appendAuditLog(context, "exportResource", {}, { type: "export", id: null }, {
        outcome: "failure",
        errorCode: errorCodeFor(error),
      });
    }
    return mapFunctionError(error, context && !(context instanceof Response) ? context.requestId : requestId);
  }
});

function config(table: string, columns: readonly string[], campusColumn?: string, searchColumn?: string): ExportConfig {
  return { table, columns, campusColumn, searchColumn, dateColumn: "created_at", defaultSort: "created_at" };
}

async function loadRows(client: any, resource: string, cfg: ExportConfig, filters: Record<string, unknown>, sort?: ExportRequest["sort"]) {
  const ratingTarget = resource === "ratings" && normalizeText(filters.target) === "dish" ? "dish" : "teacher";
  const effective = resource === "ratings"
    ? ratingTarget === "dish"
      ? { ...cfg, table: "dish_ratings", select: "dish_id,user_id,stars,created_at,updated_at,dish_catalog!inner(campus_id)" }
      : { ...cfg, table: "teacher_ratings", select: "teacher_id,user_id,stars,created_at,updated_at,teachers!inner(campus_id)" }
    : cfg;
  const select = effective.select ?? effective.columns.join(",");
  let query: any = client.from(effective.table).select(select).limit(10_000);
  const sortField = effective.columns.includes(String(sort?.field)) ? String(sort?.field) : effective.defaultSort;
  query = query.order(sortField, { ascending: String(sort?.order).toUpperCase() === "ASC" });

  const campusID = normalizeText(filters.campusID ?? filters.campus_id);
  if (campusID && campusID !== "all") {
    if (effective.campusColumn) query = query.eq(effective.campusColumn, campusID);
    if (resource === "comments") query = query.eq("posts.campus_id", campusID);
    if (resource === "ratings") query = query.eq(`${ratingTarget === "dish" ? "dish_catalog" : "teachers"}.campus_id`, campusID);
  }
  const status = normalizeText(filters.status);
  if (status && status !== "all" && effective.columns.includes("status")) query = query.eq("status", status);
  const search = normalizeText(filters.search);
  if (search && effective.searchColumn) query = query.ilike(effective.searchColumn, `%${escapeLike(search)}%`);
  const start = normalizeDate(filters.start ?? filters.start_at);
  const end = normalizeDate(filters.end ?? filters.end_at);
  if (start && effective.dateColumn) query = query.gte(effective.dateColumn, start);
  if (end && effective.dateColumn) query = query.lte(effective.dateColumn, end);

  const { data, error } = await query;
  if (error) throw databaseError(error);
  let rows = (data ?? []) as Record<string, unknown>[];
  if (resource === "ratings") rows = rows.map((row) => ({ ...row, target: ratingTarget }));
  if (resource === "reports" && campusID && campusID !== "all") {
    rows = await filterReportsForCampus(client, rows, campusID);
  }
  return rows.slice(0, 10_000);
}

async function filterReportsForCampus(client: any, rows: Record<string, unknown>[], campusID: string) {
  const postIDs = unique(rows.map((row) => row.post_id));
  const commentIDs = unique(rows.map((row) => row.comment_id));
  const profileIDs = unique(rows.map((row) => row.reported_user_id));
  const comments = await fetchInChunks(client, "comments", "id,post_id", "id", commentIDs);
  const commentPost = new Map(comments.map((row: any) => [row.id, row.post_id]));
  const allPostIDs = unique([...postIDs, ...comments.map((row: any) => row.post_id)]);
  const posts = await fetchInChunks(client, "posts", "id,campus_id", "id", allPostIDs);
  const postCampus = new Map(posts.map((row: any) => [row.id, row.campus_id]));
  const profiles = await fetchInChunks(client, "profiles", "id,community_campus_id", "id", profileIDs);
  const profileCampus = new Map(profiles.map((row: any) => [row.id, row.community_campus_id]));
  return rows.filter((row) =>
    postCampus.get(row.post_id) === campusID
    || postCampus.get(commentPost.get(row.comment_id)) === campusID
    || profileCampus.get(row.reported_user_id) === campusID
  );
}

async function fetchInChunks(client: any, table: string, select: string, column: string, ids: unknown[]) {
  const rows: any[] = [];
  for (let index = 0; index < ids.length; index += 200) {
    const { data, error } = await client.from(table).select(select).in(column, ids.slice(index, index + 200));
    if (error) throw databaseError(error);
    rows.push(...(data ?? []));
  }
  return rows;
}

function unique(values: unknown[]) {
  return Array.from(new Set(values.filter((value) => value !== null && value !== undefined)));
}

function escapeLike(value: string) {
  return value.replace(/[\\%_]/g, (character) => `\\${character}`);
}
