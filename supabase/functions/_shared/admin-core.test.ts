import { assertEquals } from "jsr:@std/assert@1";
import {
  exclusiveDateEndISO,
  HttpError,
  inclusiveDateStartISO,
  mapFunctionError,
  normalizeIdentifier,
  normalizeText,
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
