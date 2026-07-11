import { createClient } from "npm:@supabase/supabase-js@2";

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type AdminContext = {
  // This function intentionally uses a dynamic public schema; generated DB types are not available in Edge runtime.
  adminClient: any;
  userID: string;
};

type BackendErrorCode =
  | "bad_request"
  | "unauthorized"
  | "forbidden"
  | "method_not_allowed"
  | "backend_unavailable"
  | "internal_error";

export async function createAdminContext(request: Request): Promise<AdminContext | Response> {
  const authHeader = request.headers.get("Authorization");
  if (!authHeader) {
    return errorResponse(401, "unauthorized", "Missing Authorization header.");
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    return errorResponse(500, "backend_unavailable", "Missing Supabase environment variables.");
  }

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false },
  });

  const {
    data: { user },
    error: userError,
  } = await userClient.auth.getUser();

  if (userError || !user) {
    return errorResponse(401, "unauthorized", userError?.message ?? "Supabase session missing or invalid.");
  }

  const { data: adminUser, error: adminError } = await adminClient
    .from("admin_users")
    .select("user_id")
    .eq("user_id", user.id)
    .maybeSingle();

  if (adminError) {
    return errorResponse(500, "backend_unavailable", adminError.message);
  }

  if (!adminUser) {
    return errorResponse(403, "forbidden", "You are not allowed to manage site announcements.");
  }

  return { adminClient, userID: user.id };
}

export function json(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      "Content-Type": "application/json",
      ...corsHeaders,
    },
  });
}

export function errorResponse(
  status: number,
  code: BackendErrorCode,
  message: string,
  options: { retryable?: boolean; details?: unknown } = {},
) {
  const errorEnvelope: { code: BackendErrorCode; message: string; retryable: boolean; details?: unknown } = {
    code,
    message,
    retryable: options.retryable ?? (status >= 500),
  };

  if (options.details !== undefined) {
    errorEnvelope.details = options.details;
  }

  return json({ error: message, errorEnvelope }, status);
}

export async function readJSON<T>(request: Request): Promise<T> {
  try {
    return (await request.json()) as T;
  } catch {
    return {} as T;
  }
}

export function normalizeText(value: unknown): string | null {
  const trimmed = typeof value === "string" ? value.trim() : "";
  return trimmed.length > 0 ? trimmed : null;
}

export function normalizeStatus(value: unknown): "draft" | "published" {
  return value === "draft" ? "draft" : "published";
}

export function normalizeLevel(value: unknown): "info" | "warning" | "urgent" {
  if (value === "warning" || value === "urgent") {
    return value;
  }
  return "info";
}

export function normalizeDate(value: unknown): string | null {
  const text = normalizeText(value);
  if (!text) {
    return null;
  }

  const date = new Date(text);
  if (Number.isNaN(date.getTime())) {
    return null;
  }

  return date.toISOString();
}
