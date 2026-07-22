import { assert, assertEquals } from "jsr:@std/assert@1";
import { adminActionAuditMatrix } from "./action-audit.ts";

const source = await Deno.readTextFile(new URL("./index.ts", import.meta.url));

Deno.test("admin-community keeps 65 registered action contracts", () => {
  const names = Array.from(source.matchAll(/^\s{2}([A-Za-z0-9]+): defineAction\(/gm), (match) => match[1]);
  assertEquals(names.length, 65);
  for (const required of ["overview", "bulkModeratePosts", "globalSearch", "listAdminSessions", "revokeAdminSession", "listNationalCalendarRuntimeConfigs", "upsertNationalCalendarRuntimeConfig"]) {
    assert(names.includes(required), `missing ${required}`);
  }
});

Deno.test("all 65 runtime actions match the machine-readable audit matrix", () => {
  const matches = Array.from(source.matchAll(/^\s{2}([A-Za-z0-9]+): defineAction\(/gm));
  assertEquals(adminActionAuditMatrix.length, 65);
  assertEquals(adminActionAuditMatrix.map((row) => row.action), matches.map((match) => match[1]));
  for (const [index, match] of matches.entries()) {
    const block = source.slice(match.index ?? 0, matches[index + 1]?.index ?? source.indexOf("} satisfies Record"));
    const runtimeRole = block.includes('permission: "super_admin"')
      ? "super_admin"
      : block.includes('permission: "operator"') ? "operator" : "viewer";
    const row = adminActionAuditMatrix[index];
    assertEquals(row.role, runtimeRole, `${row.action} role drifted`);
    assertEquals(row.mutating, block.includes("mutating: true"), `${row.action} mutating flag drifted`);
    assert(row.auditTarget.length > 0, `${row.action} audit target missing`);
  }
});

Deno.test("critical multi-write actions declare transaction RPC boundaries", () => {
  for (const action of [
    "approveCampusRequest", "moderatePost", "bulkModeratePosts", "pinPost",
    "resolveModerationReport", "approvePostgraduateSuggestion", "approveCatalogSuggestion",
  ]) {
    assertEquals(adminActionAuditMatrix.find((row) => row.action === action)?.transactionBoundary, "transaction_rpc");
  }
  for (const action of ["upsertTeacher", "upsertCourse", "upsertDish"]) {
    assertEquals(adminActionAuditMatrix.find((row) => row.action === action)?.campusPolicy, "required");
  }
});

Deno.test("high-risk additions require operator or super-admin", () => {
  assert(source.includes('revokeAdminSession: defineAction("revokeAdminSession", revokeAdminSession, { domain: "admin", permission: "super_admin", mutating: true })'));
  assert(source.includes('upsertNationalCalendarRuntimeConfig: defineAction("upsertNationalCalendarRuntimeConfig", upsertNationalCalendarRuntimeConfig, { domain: "campus-runtime", permission: "operator", mutating: true })'));
});

Deno.test("global search enforces length, per-resource and total limits", () => {
  assert(source.includes("query.length < 2 || query.length > 100"));
  assert(source.includes("pageSize: 8"));
  assert(source.includes("].slice(0, 40)"));
});

Deno.test("authenticated failures and successes both use structured audit metadata", () => {
  assert(source.includes("actionMeta(context, auditLogged)"));
  assert(source.includes('outcome: "failure"'));
  assert(source.includes("errorCode: errorCodeFor(error)"));
});

Deno.test("catalog ratings accept numeric identifiers and expose stable record ids", () => {
  assert(source.includes('requiredIdentifier(params, "teacherID", "teacher_id")'));
  assert(source.includes('requiredIdentifier(params, "dishID", "dish_id")'));
  assert(source.includes('id: `teacher:${item.teacher_id}:${item.user_id}`'));
  assert(source.includes('id: `dish:${item.dish_id}:${item.user_id}`'));
  assert(source.includes('.select("teacher_id, user_id, stars, created_at, updated_at")'));
  assert(source.includes(".maybeSingle()"));
});

Deno.test("catalog approval treats null stars as absent and delegates to one transaction", () => {
  assert(source.includes('rpc("admin_approve_catalog_suggestion_v1"'));
  assert(!source.includes("initialStarsFromSuggestion"));
  assert(!source.includes('?? status === "resolved"'));
});

Deno.test("nested profile hydration uses an explicit non-PII projection", () => {
  const helper = source.slice(source.indexOf("async function fetchProfileMap"), source.indexOf("function profileAdminProjection"));
  assert(helper.includes('select("id, community_campus_id, nickname, display_name, avatar_path, is_profile_complete, muted_until")'));
  assert(!helper.includes('select("*")'));
});

Deno.test("list contracts validate sorting and use an exclusive end date", () => {
  assert(source.includes("function applySort("));
  assert(source.includes("throw new HttpError(400, `不支持按 ${requestedField} 排序。`)"));
  assert(source.includes("query.lt(column, end)"));
});

Deno.test("pending feedback includes open and reviewed", () => {
  assert(source.includes("pending: input.feedbackOpen + input.feedbackReviewed"));
  assert(source.includes('.in("status", ["open", "reviewed"])'));
});

Deno.test("semester calendar events preserve compatible academic categories", () => {
  assert(source.includes("row.academicCategory ?? row.academic_category"));
  for (const category of ["public_holiday", "important_date", "semester_end", "winter_break", "summer_break"]) {
    assert(source.includes(`"${category}"`), `missing ${category}`);
  }
  assert(source.includes("...(academicCategory ? { academicCategory } : {})"));
});
