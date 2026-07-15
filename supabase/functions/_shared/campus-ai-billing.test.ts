import {
  campusAIProductID,
  subscriptionFromTransactionPayload,
} from "./campus-ai-billing.ts";

function assert(condition: unknown, message: string) {
  if (!condition) throw new Error(message);
}

Deno.test("Leafy AI only accepts the weekly v2 product", () => {
  assert(
    campusAIProductID === "com.isaachuo.leafy.ai.weekly.v2",
    "unexpected product ID",
  );

  const active = subscriptionFromTransactionPayload({
    productId: campusAIProductID,
    appTransactionId: "app-1",
    originalTransactionId: "original-1",
    transactionId: "transaction-1",
    purchaseDate: Date.now() - 1_000,
    expiresDate: Date.now() + 60_000,
  });
  assert(active?.status === "active", "v2 transaction should be active");

  const legacy = subscriptionFromTransactionPayload({
    productId: "com.isaachuo.leafy.ai.weekly",
    expiresDate: Date.now() + 60_000,
  });
  assert(legacy === null, "legacy product must not grant entitlement");
});
