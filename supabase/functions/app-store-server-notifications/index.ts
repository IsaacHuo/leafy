import { createClient } from "npm:@supabase/supabase-js@2";
import {
  normalizeText,
  verifyNotificationPayload,
} from "../_shared/campus-ai-billing.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type NotificationRequest = {
  signedPayload?: string;
};

export async function handler(request: Request): Promise<Response> {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (request.method !== "POST") {
    return json({ error: "Method not allowed." }, 405);
  }

  const body = await readJSON<NotificationRequest>(request);
  const signedPayload = normalizeText(body.signedPayload);
  if (!signedPayload) {
    return json({ error: "Missing signedPayload." }, 400);
  }

  const adminClient = makeAdminClient();
  if (!adminClient) {
    return json({ error: "Notification service is not configured." }, 500);
  }

  let notification;
  try {
    notification = await verifyNotificationPayload(signedPayload);
  } catch (error) {
    console.error(
      "app-store-server-notifications: verification failed",
      errorMessage(error),
    );
    return json({ error: "Invalid signedPayload." }, 401);
  }

  if (!notification.subscription?.appTransactionID) {
    return json({ ok: true, ignored: true });
  }

  const { error } = await adminClient.schema("private").rpc(
    "sync_campus_ai_entitlement",
    {
      p_auth_user_id: null,
      p_app_transaction_id: notification.subscription.appTransactionID,
      p_product_id: notification.subscription.productID,
      p_original_transaction_id:
        notification.subscription.originalTransactionID,
      p_transaction_id: notification.subscription.transactionID,
      p_environment: notification.subscription.environment,
      p_status: notification.subscription.status,
      p_current_period_start: notification.subscription.currentPeriodStart,
      p_current_period_end: notification.subscription.currentPeriodEnd,
      p_notification_uuid: notification.notificationUUID,
      p_signed_at: notification.subscription.signedAt,
    },
  );

  if (error) {
    console.error("app-store-server-notifications: sync failed", error.message);
    return json({ error: "Notification sync failed." }, 500);
  }

  return json({
    ok: true,
    notification_uuid: notification.notificationUUID,
    notification_type: notification.notificationType,
    subtype: notification.subtype,
  });
}

if (import.meta.main) {
  Deno.serve(handler);
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

function errorMessage(error: unknown) {
  return error instanceof Error ? error.message : String(error);
}
