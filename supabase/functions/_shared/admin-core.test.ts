import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import {
  databaseError,
  exclusiveDateEndISO,
  HttpError,
  inclusiveDateStartISO,
  mapFunctionError,
  normalizeIdentifier,
  normalizeText,
  readJSON,
  requireAdminProxy,
  requireDeletedRecord,
} from "./admin-core.ts";

Deno.test("identifier normalization accepts strings and finite integers only", () => {
  assertEquals(normalizeIdentifier(" 341 "), "341");
  assertEquals(normalizeIdentifier(341), "341");
  assertEquals(normalizeIdentifier(3.14), null);
  assertEquals(normalizeIdentifier(Number.POSITIVE_INFINITY), null);
  assertEquals(normalizeIdentifier(null), null);
  assertEquals(normalizeText(341), null);
});

Deno.test("date-only filter end advances to the next day", () => {
  assertEquals(exclusiveDateEndISO("2026-07-13"), "2026-07-14T00:00:00.000Z");
  assertEquals(inclusiveDateStartISO("2026-07-13", -480), "2026-07-12T16:00:00.000Z");
  assertEquals(exclusiveDateEndISO("2026-07-13", -480), "2026-07-13T16:00:00.000Z");
  assertEquals(exclusiveDateEndISO("invalid"), null);
  assertEquals(exclusiveDateEndISO("2026-02-31"), null);
});

Deno.test("internal errors are sanitized and keep a request id", async () => {
  const response = mapFunctionError(new HttpError(500, "relation secret_table does not exist"), "request-123");
  assertEquals(response.status, 500);
  const payload = await response.json();
  assertEquals(payload.error, "后台暂时不可用，请稍后重试。");
  assertEquals(payload.errorEnvelope.details.request_id, "request-123");
});

Deno.test("expected client errors retain an actionable message", async () => {
  const response = mapFunctionError(new HttpError(404, "该评分不存在或已被删除。"), "request-456");
  assertEquals(response.status, 404);
  const payload = await response.json();
  assertEquals(payload.error, "该评分不存在或已被删除。");
  assertEquals(payload.errorEnvelope.details.request_id, "request-456");
});

Deno.test("JSON input rejects wrong content type, malformed syntax and oversized bodies", async () => {
  for (const request of [
    new Request("https://example.test", { method: "POST", headers: { "Content-Type": "text/plain" }, body: "{}" }),
    new Request("https://example.test", { method: "POST", headers: { "Content-Type": "application/json" }, body: "{" }),
    new Request("https://example.test", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ value: "x".repeat(100) }) }),
  ]) {
    await assertRejects(() => readJSON(request, 32), HttpError);
  }
});

Deno.test("database errors distinguish conflicts, missing rows and infrastructure failures", () => {
  assertEquals(databaseError({ code: "23505", message: "duplicate" }, { duplicateMessage: "重复记录" }).status, 409);
  assertEquals(databaseError({ code: "PGRST116", message: "zero rows" }).status, 404);
  assertEquals(databaseError({ code: "08006", message: "connection lost" }).status, 500);
});

Deno.test("admin proxy validation rejects direct requests", async () => {
  const previous = Deno.env.get("ADMIN_PROXY_SECRET");
  Deno.env.set("ADMIN_PROXY_SECRET", "proxy-test-secret");
  try {
    const allowed = new Request("https://example.test", { headers: { "X-Leafy-Admin-Proxy": "proxy-test-secret" } });
    assertEquals(requireAdminProxy(allowed), null);
    const denied = requireAdminProxy(new Request("https://example.test", { headers: { "X-Request-ID": "proxy-request" } }));
    assertEquals(denied?.status, 403);
    assertEquals((await denied?.json()).errorEnvelope.details.request_id, "proxy-request");
  } finally {
    if (previous === undefined) Deno.env.delete("ADMIN_PROXY_SECRET");
    else Deno.env.set("ADMIN_PROXY_SECRET", previous);
  }
});

Deno.test("delete result rejects a zero-row mutation", () => {
  assertEquals(requireDeletedRecord({ id: "record-1" }, "missing"), { id: "record-1" });
  let thrown: unknown;
  try {
    requireDeletedRecord(null, "该评分不存在或已被删除。");
  } catch (error) {
    thrown = error;
  }
  assertEquals(thrown instanceof HttpError, true);
  assertEquals((thrown as HttpError).status, 404);
});
