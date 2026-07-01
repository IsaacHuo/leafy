import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type CampusRequestBody = {
  action?: string | null;
  school_name?: string | null;
  campus_id?: string | null;
};

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (request.method !== "POST") {
    return json({ error: "Method not allowed." }, 405);
  }

  try {
    const authHeader = request.headers.get("Authorization");
    if (!authHeader) {
      return json({ error: "Missing Authorization header." }, 401);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    if (!supabaseUrl || !anonKey) {
      return json({ error: "Missing Supabase environment variables." }, 500);
    }

    const client = createClient(supabaseUrl, anonKey, {
      auth: { persistSession: false },
      global: { headers: { Authorization: authHeader } },
    });

    const {
      data: { user },
      error: userError,
    } = await client.auth.getUser();
    if (userError || !user) {
      return json({ error: userError?.message ?? "Supabase session missing or invalid." }, 401);
    }

    const body = await readBody(request);
    const action = normalizeText(body.action) ?? (normalizeText(body.campus_id) ? "select_existing" : "submit_new_school");

    if (action === "current") {
      const { data: requestRecord, error: requestError } = await client.rpc("current_campus_membership_request");
      if (requestError) {
        return json({ error: publicDatabaseError(requestError.message) }, 500);
      }
      return json({ request: normalizeRPCRecord(requestRecord) });
    }

    if (action === "select_existing") {
      const campusID = normalizeText(body.campus_id);
      if (!campusID) {
        return json({ error: "请选择学校。" }, 400);
      }
      if (isBJFUSchoolName(campusID)) {
        return json({ error: "北京林业大学请使用专属入口登录北林社区，通用入口不能选择北林社区身份。" }, 400);
      }
      const { data: profileRecord, error: profileError } = await client.rpc("select_community_campus", {
        p_campus_id: campusID,
      });
      if (profileError) {
        return json({ error: publicDatabaseError(profileError.message) }, 500);
      }
      return json({ profile: normalizeRPCRecord(profileRecord) });
    }

    if (action === "request_change") {
      const campusID = normalizeText(body.campus_id);
      if (!campusID) {
        return json({ error: "请选择新的学校。" }, 400);
      }
      if (isBJFUSchoolName(campusID)) {
        return json({ error: "北京林业大学请使用专属入口登录北林社区，通用入口不能申请切换到北林社区身份。" }, 400);
      }
      const { data: requestRecord, error: requestError } = await client.rpc("submit_community_school_change_request", {
        p_campus_id: campusID,
      });
      if (requestError) {
        return json({ error: publicDatabaseError(requestError.message) }, 500);
      }
      const requestItem = normalizeRPCRecord(requestRecord);
      const profile = await fetchProfile(client, requestItem?.requester_profile_id);
      return json({ request: requestItem, profile });
    }

    const schoolName = normalizeText(body.school_name);
    if (!schoolName) {
      return json({ error: "请填写学校名称。" }, 400);
    }
    if (isBJFUSchoolName(schoolName)) {
      return json({ error: "北京林业大学请使用专属入口登录北林社区，通用入口不审核为北林社区身份。" }, 400);
    }

    const { data: requestRecord, error: requestError } = await client.rpc("submit_campus_membership_request", {
      p_school_name: schoolName,
    });
    if (requestError) {
      return json({ error: publicDatabaseError(requestError.message) }, 500);
    }

    const requestItem = normalizeRPCRecord(requestRecord);
    const profile = await fetchProfile(client, requestItem?.requester_profile_id);
    return json({ request: requestItem, profile });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error";
    return json({ error: message }, 500);
  }
});

async function readBody(request: Request): Promise<CampusRequestBody> {
  try {
    return (await request.json()) as CampusRequestBody;
  } catch {
    return {};
  }
}

function normalizeText(value: string | null | undefined): string | null {
  const trimmed = value?.trim() ?? "";
  return trimmed.length > 0 ? trimmed : null;
}

function isBJFUSchoolName(value: string): boolean {
    const normalized = value.replace(/\s+/g, "").toLowerCase();
    return normalized === "北京林业大学" || normalized === "北林" || normalized === "bjfu";
}

function publicDatabaseError(message: string): string {
  if (message.includes("COMMUNITY_REQUEST_PENDING")) {
    return "已有学校申请正在审核中，请等待处理后再提交。";
  }
  if (message.includes("COMMUNITY_CAMPUS_ALREADY_SELECTED")) {
    return "当前账号已经加入学校社区，如需更换请在个人资料中提交审核。";
  }
  if (message.includes("COMMUNITY_CAMPUS_UNCHANGED")) {
    return "你已经在这个学校社区中。";
  }
  if (message.includes("COMMUNITY_APPROVED_CAMPUS_REQUIRED")) {
    return "请先加入一个学校社区，再提交更换申请。";
  }
  if (message.includes("COMMUNITY_CAMPUS_NOT_SELECTABLE") || message.includes("COMMUNITY_CAMPUS_NOT_FOUND")) {
    return "这个学校社区暂不可选择。";
  }
  return message;
}

function normalizeRPCRecord<T = any>(value: T | T[] | null | undefined): T | null {
  if (Array.isArray(value)) {
    return value[0] ?? null;
  }
  return value ?? null;
}

async function fetchProfile(client: any, profileID: string | null | undefined) {
  if (!profileID) {
    return null;
  }
  const { data: profile, error } = await client
    .from("profiles")
    .select("*")
    .eq("id", profileID)
    .maybeSingle();
  if (error) {
    throw error;
  }
  return profile;
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
