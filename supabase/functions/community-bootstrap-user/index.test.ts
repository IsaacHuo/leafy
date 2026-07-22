import {
  communityIdentityErrorCode,
  communityIdentityErrorMessage,
  normalizeCampusID,
  normalizeText,
} from "./index.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

Deno.test("community bootstrap normalizes school identity input", () => {
  assert(normalizeText(" 20260001 ") === "20260001", "expected trimmed edu id");
  assert(normalizeText("   ") === null, "expected blank input rejection");
  assert(
    normalizeCampusID(" BJFU ") === "bjfu",
    "expected normalized campus id",
  );
});

Deno.test("community bootstrap no longer exposes email recovery identity errors", () => {
  assert(
    communityIdentityErrorCode("COMMUNITY_ACCOUNT_RECOVERY_REQUIRED") === null,
    "email recovery must not be part of school identity bootstrap",
  );
  assert(
    communityIdentityErrorCode("COMMUNITY_AUTH_IDENTITY_MISMATCH") === null,
    "device sessions are remapped by the database",
  );
});

Deno.test("community bootstrap keeps stable invalid-session errors", () => {
  const code = communityIdentityErrorCode(
    "rpc: COMMUNITY_AUTH_SESSION_REQUIRED",
  );
  assert(
    code === "COMMUNITY_AUTH_SESSION_REQUIRED",
    "expected stable error code",
  );
  assert(
    communityIdentityErrorMessage(code) === "登录身份无效，请重新登录后再试。",
    "expected user-facing retry guidance",
  );
});
