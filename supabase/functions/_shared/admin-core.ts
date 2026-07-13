import { createClient } from "npm:@supabase/supabase-js@2";

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-request-id, x-leafy-admin-proxy, x-leafy-client-ip",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

export type AdminRole = "super_admin" | "operator" | "viewer";

export type AdminAccount = {
  id: string;
  username: string;
  display_name: string;
  role: AdminRole;
  active: boolean;
  last_login_at?: string | null;
  created_at?: string;
  updated_at?: string;
};

export type AdminContext = {
  adminClient: any;
  admin: AdminAccount;
  tokenHash: string;
  sessionExpiresAt: string;
  requestId: string;
  startedAt: number;
  requestInfo: {
    ipAddress: string | null;
    userAgent: string | null;
  };
};

export type BackendErrorCode =
  | "bad_request"
  | "unauthorized"
  | "forbidden"
  | "not_found"
  | "method_not_allowed"
  | "conflict"
  | "rate_limited"
  | "backend_unavailable"
  | "internal_error";

export type BackendErrorEnvelope = {
  code: BackendErrorCode;
  message: string;
  retryable: boolean;
  details?: unknown;
};

export class HttpError extends Error {
  status: number;
  code?: BackendErrorCode;
  retryable?: boolean;
  details?: unknown;

  constructor(
    status: number,
    message: string,
    options: { code?: BackendErrorCode; retryable?: boolean; details?: unknown } = {},
  ) {
    super(message);
    this.status = status;
    this.code = options.code;
    this.retryable = options.retryable;
    this.details = options.details;
  }
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

export function okOptions() {
  return new Response("ok", { headers: corsHeaders });
}

export function errorResponse(
  status: number,
  code: BackendErrorCode,
  message: string,
  options: { retryable?: boolean; details?: unknown } = {},
) {
  const errorEnvelope: BackendErrorEnvelope = {
    code,
    message,
    retryable: options.retryable ?? defaultRetryable(status),
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

export function createAdminClient(): any {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    throw new HttpError(500, "Missing Supabase service environment variables.");
  }

  return createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false },
  }) as any;
}

export async function authenticateAdmin(request: Request): Promise<AdminContext | Response> {
  const requestId = request.headers.get("x-request-id") || crypto.randomUUID();
  const token = bearerToken(request);
  if (!token) {
    return errorResponse(401, "unauthorized", "Missing admin session token.");
  }

  const tokenHash = await sha256Hex(token);
  const adminClient = createAdminClient();
  const requestInfo = getRequestInfo(request);

  const { data: session, error: sessionError } = await adminClient
    .from("admin_sessions")
    .select("token_hash, admin_id, expires_at, revoked_at")
    .eq("token_hash", tokenHash)
    .maybeSingle();

  if (sessionError) {
    console.error(JSON.stringify({ event: "admin_session_lookup_failed", request_id: requestId, error: sessionError.message }));
    return errorResponse(500, "backend_unavailable", "后台暂时不可用，请稍后重试。", { details: { request_id: requestId } });
  }

  if (!session || session.revoked_at || new Date(session.expires_at).getTime() <= Date.now()) {
    return errorResponse(401, "unauthorized", "Admin session expired or invalid.");
  }

  const { data: admin, error: adminError } = await adminClient
    .from("admin_accounts")
    .select("id, username, display_name, role, active, last_login_at, created_at, updated_at")
    .eq("id", session.admin_id)
    .maybeSingle();

  if (adminError) {
    console.error(JSON.stringify({ event: "admin_account_lookup_failed", request_id: requestId, error: adminError.message }));
    return errorResponse(500, "backend_unavailable", "后台暂时不可用，请稍后重试。", { details: { request_id: requestId } });
  }

  if (!admin || !admin.active) {
    return errorResponse(403, "forbidden", "Admin account is disabled.");
  }

  await adminClient
    .from("admin_sessions")
    .update({ last_seen_at: new Date().toISOString() })
    .eq("token_hash", tokenHash);

  return {
    adminClient,
    admin: admin as AdminAccount,
    tokenHash,
    sessionExpiresAt: session.expires_at,
    requestId,
    startedAt: Date.now(),
    requestInfo,
  };
}

export async function appendAuditLog(
  context: AdminContext,
  action: string,
  params: Record<string, unknown> = {},
  target?: { type?: string | null; id?: string | number | null },
  options: { outcome?: "success" | "failure"; errorCode?: string | null } = {},
): Promise<boolean> {
  const { error } = await context.adminClient.from("admin_audit_logs").insert({
    admin_id: context.admin.id,
    action,
    target_type: target?.type ?? null,
    target_id: target?.id == null ? null : String(target.id),
    params: redactSensitive(params),
    ip_address: context.requestInfo.ipAddress,
    user_agent: context.requestInfo.userAgent,
    request_id: context.requestId,
    outcome: options.outcome ?? "success",
    duration_ms: Math.max(0, Date.now() - context.startedAt),
    error_code: options.errorCode ?? null,
  });

  if (error) {
    console.error(JSON.stringify({
      event: "admin_audit_failed",
      request_id: context.requestId,
      action,
      error: error.message,
    }));
    return false;
  }
  return true;
}

export function actionMeta(context: AdminContext, auditLogged: boolean) {
  return {
    request_id: context.requestId,
    audit_logged: auditLogged,
    duration_ms: Math.max(0, Date.now() - context.startedAt),
  };
}

export function requirePost(request: Request): Response | null {
  if (request.method === "OPTIONS") {
    return okOptions();
  }
  if (request.method !== "POST") {
    return errorResponse(405, "method_not_allowed", "Method not allowed.", { retryable: false });
  }
  return null;
}

export function requireSuperAdmin(context: AdminContext) {
  if (context.admin.role !== "super_admin") {
    throw new HttpError(403, "Super admin permission is required.");
  }
}

export function requireOperator(context: AdminContext) {
  if (context.admin.role === "viewer") {
    throw new HttpError(403, "This admin account is read-only.");
  }
}

export function normalizeText(value: unknown): string | null {
  const trimmed = typeof value === "string" ? value.trim() : "";
  return trimmed.length > 0 ? trimmed : null;
}

export function normalizeIdentifier(value: unknown): string | null {
  if (typeof value === "string") {
    const trimmed = value.trim();
    return trimmed.length > 0 ? trimmed : null;
  }
  if (typeof value === "number" && Number.isFinite(value) && Number.isInteger(value)) {
    return String(value);
  }
  return null;
}

export function requireDeletedRecord<T>(value: T | null | undefined, message: string): T {
  if (value == null) {
    throw new HttpError(404, message);
  }
  return value;
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

export function inclusiveDateStartISO(value: unknown, timezoneOffsetMinutes = 0): string | null {
  const text = normalizeText(value);
  if (!text) return null;
  if (/^\d{4}-\d{2}-\d{2}$/.test(text)) {
    return dateOnlyBoundaryISO(text, timezoneOffsetMinutes, 0);
  }
  return normalizeDate(text);
}

export function exclusiveDateEndISO(value: unknown, timezoneOffsetMinutes = 0): string | null {
  const text = normalizeText(value);
  if (!text) return null;
  if (/^\d{4}-\d{2}-\d{2}$/.test(text)) {
    return dateOnlyBoundaryISO(text, timezoneOffsetMinutes, 1);
  }
  const normalized = normalizeDate(text);
  if (!normalized) return null;
  return new Date(new Date(normalized).getTime() + 1).toISOString();
}

function dateOnlyBoundaryISO(text: string, timezoneOffsetMinutes: number, dayOffset: number) {
  const [year, month, day] = text.split("-").map(Number);
  const base = new Date(Date.UTC(year, month - 1, day));
  if (
    Number.isNaN(base.getTime()) ||
    base.getUTCFullYear() !== year ||
    base.getUTCMonth() !== month - 1 ||
    base.getUTCDate() !== day
  ) {
    return null;
  }
  return new Date(base.getTime() + (dayOffset * 1440 + timezoneOffsetMinutes) * 60_000).toISOString();
}

export function mapFunctionError(error: unknown, requestId?: string) {
  if (error instanceof HttpError) {
    if (error.status >= 500) {
      console.error(JSON.stringify({
        event: "admin_request_failed",
        request_id: requestId ?? null,
        code: error.code ?? statusToErrorCode(error.status),
        error: error.message,
      }));
      return errorResponse(
        error.status,
        error.code ?? statusToErrorCode(error.status),
        "后台暂时不可用，请稍后重试。",
        { retryable: error.retryable, details: requestId ? { request_id: requestId } : undefined },
      );
    }
    return errorResponse(
      error.status,
      error.code ?? statusToErrorCode(error.status),
      error.message,
      { retryable: error.retryable, details: error.details },
    );
  }

  const message = error instanceof Error ? error.message : "Unknown admin error.";
  console.error(JSON.stringify({ event: "admin_request_failed", request_id: requestId ?? null, code: "internal_error", error: message }));
  return errorResponse(500, "internal_error", "后台发生未知错误，请稍后重试。", {
    details: requestId ? { request_id: requestId } : undefined,
  });
}

export function errorCodeFor(error: unknown): BackendErrorCode {
  if (error instanceof HttpError) {
    return error.code ?? statusToErrorCode(error.status);
  }
  return "internal_error";
}

function statusToErrorCode(status: number): BackendErrorCode {
  if (status === 400) return "bad_request";
  if (status === 401) return "unauthorized";
  if (status === 403) return "forbidden";
  if (status === 404) return "not_found";
  if (status === 405) return "method_not_allowed";
  if (status === 409) return "conflict";
  if (status === 429) return "rate_limited";
  if (status >= 500) return "backend_unavailable";
  return "internal_error";
}

function defaultRetryable(status: number) {
  return status === 429 || status >= 500;
}

function bearerToken(request: Request): string | null {
  const authHeader = request.headers.get("Authorization");
  if (!authHeader) {
    return null;
  }

  const [scheme, token] = authHeader.split(/\s+/, 2);
  if (scheme?.toLowerCase() !== "bearer" || !token) {
    return null;
  }

  return token;
}

async function sha256Hex(value: string): Promise<string> {
  const buffer = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(buffer))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function getRequestInfo(request: Request) {
  const forwardedFor = request.headers.get("x-forwarded-for");
  return {
    ipAddress: forwardedFor?.split(",")[0]?.trim() || null,
    userAgent: request.headers.get("user-agent"),
  };
}

function redactSensitive(value: unknown): unknown {
  if (Array.isArray(value)) {
    return value.map(redactSensitive);
  }

  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value as Record<string, unknown>).map(([key, item]) => {
        const lowerKey = key.toLowerCase();
        if (
          lowerKey.includes("password")
          || lowerKey.includes("token")
          || lowerKey.includes("secret")
          || lowerKey === "search"
          || lowerKey === "query"
          || lowerKey.includes("contact")
          || lowerKey.includes("email")
        ) {
          return [key, "[redacted]"];
        }
        return [key, redactSensitive(item)];
      }),
    );
  }

  return value;
}
