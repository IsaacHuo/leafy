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

Deno.serve(async (request) => {
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
    const now = new Date().toISOString();

    const { data: existingProfileByEduID, error: eduProfileError } = await adminClient
      .from("profiles")
      .select("*")
      .eq("campus_id", campusID)
      .eq("edu_id", eduID)
      .maybeSingle();

    if (eduProfileError) {
      return json({ error: eduProfileError.message }, 500);
    }

    const { data: currentProfile, error: currentProfileError } = await adminClient
      .from("profiles")
      .select("*")
      .eq("id", user.id)
      .maybeSingle();

    if (currentProfileError) {
      return json({ error: currentProfileError.message }, 500);
    }

    const { data: currentLink, error: currentLinkError } = await adminClient
      .from("profile_auth_links")
      .select("*")
      .eq("auth_user_id", user.id)
      .maybeSingle();

    if (currentLinkError) {
      return json({ error: currentLinkError.message }, 500);
    }

    const allowsGenericCommunityBootstrap = !isBJFU && currentLink?.edu_id === eduID && currentLink.campus_id !== "bjfu";
    if (
      currentLink &&
      (currentLink.edu_id !== eduID || currentLink.campus_id !== campusID) &&
      !allowsGenericCommunityBootstrap &&
      (!existingProfileByEduID || existingProfileByEduID.id !== currentLink.profile_id)
    ) {
      return json({ error: "当前社区会话已绑定其他学号，请退出后重新登录。" }, 409);
    }

    if (
      !currentLink &&
      currentProfile &&
      (currentProfile.edu_id !== eduID || currentProfile.campus_id !== campusID) &&
      !(!isBJFU && currentProfile.edu_id === eduID && currentProfile.campus_id !== "bjfu") &&
      (!existingProfileByEduID || existingProfileByEduID.id !== currentProfile.id)
    ) {
      return json({ error: "当前社区会话已绑定其他学号，请退出后重新登录。" }, 409);
    }

    const sourceProfile = existingProfileByEduID ?? currentProfile ?? null;
    const preservedStatus = normalizeText(sourceProfile?.community_access_status);
    const preservedCommunityCampusID = normalizeText(sourceProfile?.community_campus_id);
    const shouldKeepApprovedCommunity = !isBJFU && preservedStatus === "approved" && preservedCommunityCampusID;
    const communityPayload = isBJFU
      ? {
        campus_id: "bjfu",
        community_campus_id: "bjfu",
        community_access_status: "approved",
        community_school_name: "北京林业大学",
        community_rejection_reason: null,
      }
      : {
        campus_id: shouldKeepApprovedCommunity ? preservedCommunityCampusID : "general",
        community_campus_id: shouldKeepApprovedCommunity ? preservedCommunityCampusID : null,
        community_access_status: preservedStatus === "pending" || preservedStatus === "rejected" || preservedStatus === "approved"
          ? preservedStatus
          : "general",
        community_school_name: sourceProfile?.community_school_name ?? null,
        community_rejection_reason: preservedStatus === "rejected" ? sourceProfile?.community_rejection_reason ?? null : null,
      };

    const profilePayload = {
      ...communityPayload,
      edu_id: eduID,
      display_name: displayName,
      updated_at: now,
    };
    const isNewUser = !existingProfileByEduID && !currentProfile;
    let targetProfileID = currentLink?.profile_id ?? existingProfileByEduID?.id ?? currentProfile?.id ?? user.id;

    if (existingProfileByEduID) {
      targetProfileID = existingProfileByEduID.id;
      const { error: updateProfileError } = await adminClient
        .from("profiles")
        .update(profilePayload)
        .eq("id", targetProfileID);

      if (updateProfileError) {
        return json({ error: updateProfileError.message }, 500);
      }
    } else {
      const { error: upsertError } = await adminClient
        .from("profiles")
        .upsert({
          ...profilePayload,
          id: targetProfileID,
          nickname: currentProfile?.nickname ?? "",
          avatar_path: currentProfile?.avatar_path ?? null,
          cover_path: currentProfile?.cover_path ?? null,
          major: currentProfile?.major ?? null,
          grade: currentProfile?.grade ?? null,
          bound_email: currentProfile?.bound_email ?? null,
          pending_bound_email: currentProfile?.pending_bound_email ?? null,
          email_verification_sent_at: currentProfile?.email_verification_sent_at ?? null,
          profile_edited_at: currentProfile?.profile_edited_at ?? null,
          is_profile_complete: currentProfile?.is_profile_complete ?? false,
          created_at: currentProfile?.created_at ?? now,
        }, {
          onConflict: "id",
        });

      if (upsertError) {
        return json({ error: upsertError.message }, 500);
      }
    }

    const { error: linkError } = await adminClient
      .from("profile_auth_links")
      .upsert({
        auth_user_id: user.id,
        profile_id: targetProfileID,
        campus_id: profilePayload.campus_id,
        edu_id: eduID,
        last_seen_at: now,
      }, {
        onConflict: "auth_user_id",
      });

    if (linkError) {
      return json({ error: linkError.message }, 500);
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
      is_new_user: isNewUser,
      is_profile_complete: profile.is_profile_complete,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error";
    return json({ error: message }, 500);
  }
});

async function readRequestBody(request: Request): Promise<BootstrapRequest> {
  try {
    return (await request.json()) as BootstrapRequest;
  } catch {
    return {};
  }
}

function normalizeText(value: string | null | undefined): string | null {
  const trimmed = value?.trim() ?? "";
  return trimmed.length > 0 ? trimmed : null;
}

function normalizeCampusID(value: string | null | undefined): string {
  const normalized = normalizeText(value)?.toLowerCase() ?? "bjfu";
  return normalized.length > 0 ? normalized : "bjfu";
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
