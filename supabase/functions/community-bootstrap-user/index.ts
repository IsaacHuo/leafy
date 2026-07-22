import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type BootstrapRequest = {
  edu_id?: string | null;
  display_name?: string | null;
  campus_id?: string | null;
};

export async function handler(request: Request): Promise<Response> {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = request.headers.get("Authorization");
    if (!authHeader) {
      console.error("community-bootstrap-user: missing Authorization header");
      return json({ error: "Missing Authorization header." }, 401);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !anonKey || !serviceRoleKey) {
      return json({ error: "Missing Supabase environment variables." }, 500);
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
      console.error("community-bootstrap-user: invalid Supabase session", userError?.message ?? "no-user");
      return json({ error: userError?.message ?? "Supabase session missing or invalid." }, 401);
    }

    const body = await readRequestBody(request);
    const eduID = normalizeText(body.edu_id);
    if (!eduID) {
      console.error("community-bootstrap-user: edu_id missing");
      return json({ error: "登录身份缺失，请重新登录后再试。" }, 400);
    }

    const requestedCampusID = normalizeCampusID(body.campus_id);
    const isBJFU = requestedCampusID === "bjfu";
    const campusID = isBJFU ? "bjfu" : "general";
    const displayName = normalizeText(body.display_name) ?? eduID;

    const { data: claim, error: claimError } = await adminClient.rpc(
      "edge_claim_community_identity",
      {
        p_auth_user_id: user.id,
        p_campus_id: campusID,
        p_edu_id: eduID,
        p_display_name: displayName,
      },
    );

    if (claimError) {
      const code = communityIdentityErrorCode(claimError.message);
      if (code) {
        return json({ error: communityIdentityErrorMessage(code), code }, 409);
      }
      console.error("community-bootstrap-user: identity claim failed", claimError.code ?? "unknown");
      return json({ error: "社区身份绑定失败，请稍后重试。", code: "COMMUNITY_IDENTITY_CLAIM_FAILED" }, 500);
    }

    const targetProfileID = normalizeText(claim?.profile_id);
    if (!targetProfileID) {
      return json({ error: "Community identity claim returned no profile.", code: "COMMUNITY_IDENTITY_CLAIM_FAILED" }, 500);
    }

    const { data: profile, error: profileError } = await adminClient
      .from("profiles")
      .select("*")
      .eq("id", targetProfileID)
      .maybeSingle();

    if (profileError) {
      return json({ error: profileError.message }, 500);
    }

    if (!profile) {
      return json({ error: "Community profile was not created. Please retry after signing in again." }, 500);
    }

    return json({
      profile,
      is_new_user: claim?.is_new_user === true,
      is_profile_complete: profile.is_profile_complete,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error";
    return json({ error: message }, 500);
  }
}

if (import.meta.main) Deno.serve(handler);

async function readRequestBody(request: Request): Promise<BootstrapRequest> {
  try {
    return (await request.json()) as BootstrapRequest;
  } catch {
    return {};
  }
}

export function normalizeText(value: string | null | undefined): string | null {
  const trimmed = value?.trim() ?? "";
  return trimmed.length > 0 ? trimmed : null;
}

export function normalizeCampusID(value: string | null | undefined): string {
  const normalized = normalizeText(value)?.toLowerCase() ?? "bjfu";
  return normalized.length > 0 ? normalized : "bjfu";
}

export function communityIdentityErrorCode(message: string): string | null {
  const codes = [
    "COMMUNITY_AUTH_SESSION_REQUIRED",
    "COMMUNITY_EDU_ID_REQUIRED",
  ];
  return codes.find((code) => message.includes(code)) ?? null;
}

export function communityIdentityErrorMessage(_code: string): string {
  return "登录身份无效，请重新登录后再试。";
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
