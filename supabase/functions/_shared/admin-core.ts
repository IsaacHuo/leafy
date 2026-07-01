import { createClient } from "npm:@supabase/supabase-js@2";

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
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
  requestInfo: {
    ipAddress: string | null;
    userAgent: string | null;
  };
};

export class HttpError extends Error {
  status: number;

  constructor(status: number, message: string) {
    super(message);
    this.status = status;
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
  const token = bearerToken(request);
  if (!token) {
    return json({ error: "Missing admin session token." }, 401);
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
    return json({ error: sessionError.message }, 500);
  }

  if (!session || session.revoked_at || new Date(session.expires_at).getTime() <= Date.now()) {
    return json({ error: "Admin session expired or invalid." }, 401);
  }

  const { data: admin, error: adminError } = await adminClient
    .from("admin_accounts")
    .select("id, username, display_name, role, active, last_login_at, created_at, updated_at")
    .eq("id", session.admin_id)
    .maybeSingle();

  if (adminError) {
    return json({ error: adminError.message }, 500);
  }

  if (!admin || !admin.active) {
    return json({ error: "Admin account is disabled." }, 403);
  }

  await adminClient
    .from("admin_sessions")
    .update({ last_seen_at: new Date().toISOString() })
    .eq("token_hash", tokenHash);

  return {
    adminClient,
    admin: admin as AdminAccount,
    tokenHash,
    requestInfo,
  };
}

export async function appendAuditLog(
  context: AdminContext,
  action: string,
  params: Record<string, unknown> = {},
  target?: { type?: string | null; id?: string | number | null },
) {
  await context.adminClient.from("admin_audit_logs").insert({
    admin_id: context.admin.id,
    action,
    target_type: target?.type ?? null,
    target_id: target?.id == null ? null : String(target.id),
    params: redactSensitive(params),
    ip_address: context.requestInfo.ipAddress,
    user_agent: context.requestInfo.userAgent,
  });
}

export function requirePost(request: Request): Response | null {
  if (request.method === "OPTIONS") {
    return okOptions();
  }
  if (request.method !== "POST") {
    return json({ error: "Method not allowed." }, 405);
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

export function mapFunctionError(error: unknown) {
  if (error instanceof HttpError) {
    return json({ error: error.message }, error.status);
  }

  const message = error instanceof Error ? error.message : "Unknown admin error.";
  return json({ error: message }, 500);
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
        if (lowerKey.includes("password") || lowerKey.includes("token")) {
          return [key, "[redacted]"];
        }
        return [key, redactSensitive(item)];
      }),
    );
  }

  return value;
}
