import { createClient } from "npm:@supabase/supabase-js@2";
import {
  normalizeText,
  verifyAppTransactionJWS,
  verifySubscriptionTransactionJWS,
} from "../_shared/campus-ai-billing.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type SyncRequest = {
  app_transaction_id?: string;
  app_transaction_jws?: string;
  transaction_jws?: string | null;
};

export async function handler(request: Request): Promise<Response> {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (request.method !== "POST") {
    return json({ error: "Method not allowed." }, 405);
  }

  if (!new URL(request.url).pathname.endsWith("/sync")) {
    return json({ error: "Not found." }, 404);
  }

  const adminClient = makeAdminClient();
  if (!adminClient) {
    return json({ error: "订阅服务配置不完整。" }, 500);
  }

  const authResult = await authenticateUser(adminClient, request);
  if (!authResult.ok) {
    return json({ error: authResult.error }, authResult.status);
  }

  const body = await readJSON<SyncRequest>(request);
  let appTransaction;
  try {
    appTransaction = await verifyAppTransactionJWS(
      body.app_transaction_jws,
      body.app_transaction_id,
    );
  } catch (error) {
    console.error(
      "campus-ai-entitlement: app transaction verification failed",
      errorMessage(error),
    );
    return json({ error: "App Store 安装记录验证失败，请稍后重试。" }, 401);
  }

  if (!appTransaction?.appTransactionID) {
    return json({ error: "缺少 App Store 安装标识。" }, 400);
  }

  let subscription = null;
  try {
    subscription = await verifySubscriptionTransactionJWS(
      body.transaction_jws ?? undefined,
    );
  } catch (error) {
    console.error(
      "campus-ai-entitlement: transaction verification failed",
      errorMessage(error),
    );
    return json({ error: "订阅交易验证失败，请稍后重试。" }, 401);
  }

  if (
    subscription?.appTransactionID &&
    subscription.appTransactionID !== appTransaction.appTransactionID
  ) {
    return json({ error: "订阅交易与当前 App 安装不匹配。" }, 401);
  }

  const sync = await syncEntitlement(adminClient, {
    authUserID: authResult.userID,
    appTransactionID: appTransaction.appTransactionID,
    productID: subscription?.productID ?? null,
    originalTransactionID: subscription?.originalTransactionID ?? null,
    transactionID: subscription?.transactionID ?? null,
    environment: subscription?.environment ?? appTransaction.environment,
    status: subscription?.status ?? "free",
    currentPeriodStart: subscription?.currentPeriodStart ?? null,
    currentPeriodEnd: subscription?.currentPeriodEnd ?? null,
    signedAt: subscription?.signedAt ?? null,
  });

  if (!sync.ok) {
    return json({ error: "订阅状态同步失败，请稍后重试。" }, 500);
  }

  return json(sync.data);
}

if (import.meta.main) {
  Deno.serve(handler);
}

async function syncEntitlement(adminClient: any, params: {
  authUserID: string;
  appTransactionID: string;
  productID: string | null;
  originalTransactionID: string | null;
  transactionID: string | null;
  environment: string | null;
  status: string;
  currentPeriodStart: string | null;
  currentPeriodEnd: string | null;
  signedAt: string | null;
}) {
  const { data, error } = await adminClient.schema("private").rpc(
    "sync_campus_ai_entitlement",
    {
      p_auth_user_id: params.authUserID,
      p_app_transaction_id: params.appTransactionID,
      p_product_id: params.productID,
      p_original_transaction_id: params.originalTransactionID,
      p_transaction_id: params.transactionID,
      p_environment: params.environment,
      p_status: params.status,
      p_current_period_start: params.currentPeriodStart,
      p_current_period_end: params.currentPeriodEnd,
      p_signed_at: params.signedAt,
    },
  );

  if (error) {
    console.error("campus-ai-entitlement: sync failed", error.message);
    return { ok: false as const };
  }
  return { ok: true as const, data };
}

async function authenticateUser(adminClient: any, request: Request) {
  const token = bearerToken(request);
  if (!token) {
    return { ok: false as const, status: 401, error: "缺少登录凭证。" };
  }

  const { data, error } = await adminClient.auth.getUser(token);
  if (error || !data?.user?.id) {
    return {
      ok: false as const,
      status: 401,
      error: "登录状态已失效，请稍后重试。",
    };
  }
  return { ok: true as const, userID: data.user.id as string };
}

function makeAdminClient() {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    return null;
  }
  return createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false },
  });
}

async function readJSON<T>(request: Request): Promise<T> {
  try {
    return await request.json() as T;
  } catch {
    return {} as T;
  }
}

function json(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      "Content-Type": "application/json",
      ...corsHeaders,
    },
  });
}

function bearerToken(request: Request): string | null {
  const authHeader = request.headers.get("Authorization");
  if (!authHeader) return null;
  const [scheme, token] = authHeader.split(/\s+/, 2);
  return scheme?.toLowerCase() === "bearer" && normalizeText(token)
    ? token
    : null;
}

function errorMessage(error: unknown) {
  return error instanceof Error ? error.message : String(error);
}
