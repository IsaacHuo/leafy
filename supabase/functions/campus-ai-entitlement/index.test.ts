import { optionalVerifiedAppTransaction } from "./index.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

Deno.test("campus-ai-entitlement allows a quota snapshot without AppTransaction", async () => {
  let verificationCalls = 0;
  const appTransaction = await optionalVerifiedAppTransaction(
    { app_transaction_id: "untrusted-client-id" },
    async () => {
      verificationCalls += 1;
      return { appTransactionID: "should-not-run", environment: "Sandbox" };
    },
  );

  assert(
    appTransaction === null,
    "free quota should be keyed by the authenticated user",
  );
  assert(
    verificationCalls === 0,
    "missing JWS should not invoke Apple verification",
  );
});

Deno.test("campus-ai-entitlement ignores an invalid AppTransaction proof", async () => {
  const appTransaction = await optionalVerifiedAppTransaction(
    {
      app_transaction_id: "untrusted-client-id",
      app_transaction_jws: "invalid-jws",
    },
    async () => {
      throw new Error("Invalid certificate chain.");
    },
  );

  assert(
    appTransaction === null,
    "invalid proof must not authorize a client-provided ID",
  );
});

Deno.test("campus-ai-entitlement retains a verified AppTransaction proof", async () => {
  const appTransaction = await optionalVerifiedAppTransaction(
    {
      app_transaction_id: "verified-app-id",
      app_transaction_jws: "signed-jws",
    },
    async (_jws, expectedID) => {
      assert(
        expectedID === "verified-app-id",
        "expected ID should corroborate the JWS",
      );
      return { appTransactionID: "verified-app-id", environment: "Sandbox" };
    },
  );

  assert(
    appTransaction?.appTransactionID === "verified-app-id",
    "verified identity should be retained",
  );
});
