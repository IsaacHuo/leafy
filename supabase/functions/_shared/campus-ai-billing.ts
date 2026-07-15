import { Buffer } from "node:buffer";
import {
  Environment,
  SignedDataVerifier,
} from "npm:@apple/app-store-server-library@3.1.0";

export const campusAIProductID = "com.isaachuo.leafy.ai.weekly.v2";

export type VerifiedAppTransaction = {
  appTransactionID: string;
  environment: string | null;
};

export type VerifiedSubscription = {
  appTransactionID: string | null;
  productID: string | null;
  originalTransactionID: string | null;
  transactionID: string | null;
  environment: string | null;
  status: "active" | "expired" | "refunded" | "revoked" | "free";
  currentPeriodStart: string | null;
  currentPeriodEnd: string | null;
  signedAt: string | null;
};

export type AppleNotificationResult = {
  notificationUUID: string | null;
  notificationType: string | null;
  subtype: string | null;
  subscription: VerifiedSubscription | null;
};

export async function verifyAppTransactionJWS(
  signedAppTransaction: string | undefined,
  expectedAppTransactionID?: string | null,
): Promise<VerifiedAppTransaction | null> {
  const trimmed = normalizeText(signedAppTransaction);
  if (!trimmed) return null;

  const payload = allowUnsignedTestData()
    ? decodeUnsignedJWSPayload<Record<string, unknown>>(trimmed)
    : await verifyWithAppleEnvironments((verifier) =>
      verifier.verifyAndDecodeAppTransaction(trimmed)
    );

  const appTransactionID = normalizeText(payload.appTransactionId);
  if (!appTransactionID) return null;
  if (
    expectedAppTransactionID &&
    appTransactionID !== expectedAppTransactionID
  ) {
    throw new Error("App transaction ID mismatch.");
  }

  return {
    appTransactionID,
    environment: normalizeText(payload.receiptType),
  };
}

export async function verifySubscriptionTransactionJWS(
  signedTransaction: string | undefined,
): Promise<VerifiedSubscription | null> {
  const trimmed = normalizeText(signedTransaction);
  if (!trimmed) return null;

  const payload = allowUnsignedTestData()
    ? decodeUnsignedJWSPayload<Record<string, unknown>>(trimmed)
    : await verifyWithAppleEnvironments((verifier) =>
      verifier.verifyAndDecodeTransaction(trimmed)
    );

  return subscriptionFromTransactionPayload(payload as Record<string, unknown>);
}

export async function verifyNotificationPayload(
  signedPayload: string,
): Promise<AppleNotificationResult> {
  const payload = allowUnsignedTestData()
    ? decodeUnsignedJWSPayload<Record<string, unknown>>(signedPayload)
    : await verifyWithAppleEnvironments((verifier) =>
      verifier.verifyAndDecodeNotification(signedPayload)
    );

  const data = objectValue(payload.data);
  const signedTransaction = normalizeText(data?.signedTransactionInfo);
  const subscription = signedTransaction
    ? await verifySubscriptionTransactionJWS(signedTransaction)
    : null;

  return {
    notificationUUID: normalizeText(payload.notificationUUID),
    notificationType: normalizeText(payload.notificationType),
    subtype: normalizeText(payload.subtype),
    subscription: subscriptionFromNotification(
      subscription,
      normalizeText(payload.notificationType),
      normalizeText(payload.subtype),
    ),
  };
}

export function subscriptionFromTransactionPayload(
  payload: Record<string, unknown>,
): VerifiedSubscription | null {
  const productID = normalizeText(payload.productId);
  if (productID !== campusAIProductID) return null;

  const expiresDate = numberValue(payload.expiresDate);
  const purchaseDate = numberValue(payload.purchaseDate);
  const signedDate = numberValue(payload.signedDate);
  const revocationDate = numberValue(payload.revocationDate);
  const appTransactionID = normalizeText(payload.appTransactionId);
  const now = Date.now();

  let status: VerifiedSubscription["status"] = "free";
  if (revocationDate) {
    status = "refunded";
  } else if (expiresDate && expiresDate > now) {
    status = "active";
  } else {
    status = "expired";
  }

  return {
    appTransactionID,
    productID,
    originalTransactionID: normalizeText(payload.originalTransactionId),
    transactionID: normalizeText(payload.transactionId),
    environment: normalizeText(payload.environment),
    status,
    currentPeriodStart: purchaseDate
      ? new Date(purchaseDate).toISOString()
      : null,
    currentPeriodEnd: expiresDate ? new Date(expiresDate).toISOString() : null,
    signedAt: signedDate ? new Date(signedDate).toISOString() : null,
  };
}

function subscriptionFromNotification(
  subscription: VerifiedSubscription | null,
  notificationType: string | null,
  subtype: string | null,
): VerifiedSubscription | null {
  if (!subscription) return null;

  switch (notificationType) {
    case "REFUND":
    case "REFUND_DECLINED":
    case "REFUND_REVERSED":
    case "CONSUMPTION_REQUEST":
      return notificationType === "REFUND"
        ? { ...subscription, status: "refunded" }
        : subscription;
    case "REVOKE":
      return { ...subscription, status: "revoked" };
    case "EXPIRED":
      return { ...subscription, status: "expired" };
    case "DID_FAIL_TO_RENEW":
      return { ...subscription, status: "expired" };
    case "DID_RENEW":
    case "SUBSCRIBED":
    case "DID_CHANGE_RENEWAL_STATUS":
    case "DID_CHANGE_RENEWAL_PREF":
    case "OFFER_REDEEMED":
    case "PRICE_INCREASE":
    case "GRACE_PERIOD_EXPIRED":
      return subscription;
    default:
      return subtype === "AUTO_RENEW_DISABLED" ? subscription : subscription;
  }
}

async function verifyWithAppleEnvironments<T>(
  operation: (verifier: SignedDataVerifier) => Promise<T>,
): Promise<T> {
  let lastError: unknown;
  for (const environment of appleVerificationEnvironments()) {
    try {
      return await operation(appleVerifier(environment));
    } catch (error) {
      lastError = error;
      console.warn(JSON.stringify({
        event: "app_store_jws_verification_attempt_failed",
        environment,
        error_name: error instanceof Error ? error.name : "UnknownError",
        error_message: error instanceof Error ? error.message : String(error),
      }));
    }
  }
  throw lastError ?? new Error("Apple transaction verification failed.");
}

function appleVerifier(environment: Environment) {
  const rootCertificates = appleRootCertificates();
  const bundleID = envText("APP_STORE_BUNDLE_ID") ?? "com.isaachuo.leafy";
  const appAppleID = integerEnv("APP_STORE_APP_APPLE_ID");
  return new SignedDataVerifier(
    rootCertificates,
    envText("APP_STORE_ENABLE_ONLINE_CHECKS") !== "false",
    environment,
    bundleID,
    appAppleID ?? undefined,
  );
}

function appleVerificationEnvironments(): Environment[] {
  const primary = appleEnvironment();
  if (primary === Environment.PRODUCTION) {
    return [Environment.PRODUCTION, Environment.SANDBOX];
  }
  if (primary === Environment.SANDBOX) {
    return [Environment.SANDBOX, Environment.PRODUCTION];
  }
  return [primary];
}

function appleRootCertificates(): Buffer[] {
  const raw = envText("APPLE_ROOT_CERTIFICATES_BASE64");
  if (!raw) {
    throw new Error("Missing APPLE_ROOT_CERTIFICATES_BASE64.");
  }

  let values: string[];
  try {
    const parsed = JSON.parse(raw);
    values = Array.isArray(parsed) ? parsed : [raw];
  } catch {
    values = raw.split(/[\n,]+/);
  }

  const certificates = values
    .map((value) => value.trim())
    .filter(Boolean)
    .map((value) => Buffer.from(value, "base64"));
  if (certificates.length === 0) {
    throw new Error("APPLE_ROOT_CERTIFICATES_BASE64 is empty.");
  }
  return certificates;
}

function appleEnvironment(): Environment {
  const raw = envText("APP_STORE_SERVER_ENVIRONMENT") ?? Environment.SANDBOX;
  switch (raw) {
    case Environment.PRODUCTION:
    case "production":
      return Environment.PRODUCTION;
    case Environment.XCODE:
    case "xcode":
      return Environment.XCODE;
    case Environment.LOCAL_TESTING:
    case "local":
      return Environment.LOCAL_TESTING;
    default:
      return Environment.SANDBOX;
  }
}

function allowUnsignedTestData() {
  return appleEnvironment() !== Environment.PRODUCTION &&
    envText("APP_STORE_SERVER_ALLOW_UNSIGNED_TEST_DATA") === "true";
}

export function decodeUnsignedJWSPayload<T extends Record<string, unknown>>(
  jws: string,
): T {
  const payload = jws.split(".")[1];
  if (!payload) {
    throw new Error("Invalid JWS payload.");
  }
  const normalized = payload.replace(/-/g, "+").replace(/_/g, "/");
  const padded = normalized.padEnd(
    normalized.length + (4 - normalized.length % 4) % 4,
    "=",
  );
  return JSON.parse(atob(padded)) as T;
}

function objectValue(value: unknown): Record<string, unknown> | null {
  return value && typeof value === "object"
    ? value as Record<string, unknown>
    : null;
}

function numberValue(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function integerEnv(key: string): number | null {
  const value = envText(key);
  if (!value) return null;
  const parsed = Number.parseInt(value, 10);
  return Number.isFinite(parsed) ? parsed : null;
}

export function normalizeText(value: unknown): string | null {
  const trimmed = typeof value === "string" ? value.trim() : "";
  return trimmed.length > 0 ? trimmed : null;
}

function envText(key: string): string | null {
  try {
    return Deno.env.get(key)?.trim() || null;
  } catch {
    return null;
  }
}
