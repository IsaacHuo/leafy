import { assert, assertEquals } from "jsr:@std/assert@1";

const source = await Deno.readTextFile(new URL("./index.ts", import.meta.url));

Deno.test("admin-community keeps 65 registered action contracts", () => {
  const names = Array.from(source.matchAll(/^\s{2}([A-Za-z0-9]+): defineAction\(/gm), (match) => match[1]);
  assertEquals(names.length, 65);
  for (const required of ["overview", "bulkModeratePosts", "globalSearch", "listAdminSessions", "revokeAdminSession", "listNationalCalendarRuntimeConfigs", "upsertNationalCalendarRuntimeConfig"]) {
    assert(names.includes(required), `missing ${required}`);
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

Deno.test("list contracts validate sorting and use an exclusive end date", () => {
  assert(source.includes("function applySort("));
  assert(source.includes("throw new HttpError(400, `不支持按 ${requestedField} 排序。`)"));
  assert(source.includes("query.lt(column, end)"));
});

Deno.test("pending feedback includes open and reviewed", () => {
  assert(source.includes("pending: input.feedbackOpen + input.feedbackReviewed"));
  assert(source.includes('.in("status", ["open", "reviewed"])'));
});
