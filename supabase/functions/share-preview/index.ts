import { createClient } from "npm:@supabase/supabase-js@2";

const siteOrigin = "https://myleafy.space";
const appIconURL = `${siteOrigin}/app-icon.png`;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
};

type SharePreviewStatus = "ok" | "not_found" | "expired" | "used" | "invalid";

type SharePreview = {
  kind: "community-post" | "timetable-invite";
  status: SharePreviewStatus;
  title: string;
  description: string;
  canonicalURL: string;
  imageURL: string;
};
type ServiceClient = ReturnType<typeof createClient>;

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (request.method !== "GET") {
    return json({ error: "Method not allowed." }, 405);
  }

  try {
    const url = new URL(request.url);
    const kind = normalizeText(url.searchParams.get("kind"));

    if (kind === "community-post") {
      return json(await communityPostPreview(url.searchParams.get("id")));
    }

    if (kind === "timetable-invite") {
      return json(await timetableInvitePreview(url.searchParams.get("code")));
    }

    return json({ error: "Invalid share preview kind." }, 400);
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error";
    console.error("share-preview: request failed", message);
    return json({ error: "Share preview unavailable." }, 500);
  }
});

async function communityPostPreview(idValue: string | null): Promise<SharePreview> {
  const postID = normalizeText(idValue);
  const canonicalURL = `${siteOrigin}/share/community/post/${postID ?? ""}`;
  if (!postID || !/^[0-9a-fA-F-]{36}$/.test(postID)) {
    return fallbackPreview("community-post", "invalid", canonicalURL);
  }

  const client = requireServiceClient();
  const { data, error } = await client
    .from("posts")
    .select("id,title,body,category,comment_count,like_count,status")
    .eq("id", postID)
    .eq("status", "published")
    .limit(1)
    .maybeSingle();

  if (error) {
    console.error("share-preview: post query failed", error.message);
    return fallbackPreview("community-post", "not_found", canonicalURL);
  }

  if (!data) {
    return fallbackPreview("community-post", "not_found", canonicalURL);
  }

  const title = normalizeText(data.title) ?? "MyLeafy 社区帖子";
  const body = normalizeText(data.body) ?? "";
  const category = normalizeText(data.category) ?? "社区";
  const stats = `${category} · ${data.comment_count ?? 0} 条评论 · ${data.like_count ?? 0} 个赞`;
  const description = body.length > 0 ? `${truncate(body, 110)} · ${stats}` : stats;

  return {
    kind: "community-post",
    status: "ok",
    title,
    description,
    canonicalURL,
    imageURL: appIconURL,
  };
}

async function timetableInvitePreview(codeValue: string | null): Promise<SharePreview> {
  const code = normalizeInviteCode(codeValue);
  const canonicalURL = `${siteOrigin}/share/timetable/${code}`;
  if (code.length !== 12) {
    return fallbackPreview("timetable-invite", "invalid", canonicalURL);
  }

  const client = requireServiceClient();
  const codeHash = await sha256Hex(code);
  const { data: invite, error } = await client
    .from("timetable_invites")
    .select("id,campus_id,owner_id,semester_id,expires_at,accepted_by,accepted_at,created_at")
    .eq("code_hash", codeHash)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (error) {
    console.error("share-preview: invite query failed", error.message);
    return fallbackPreview("timetable-invite", "not_found", canonicalURL);
  }

  if (!invite) {
    return fallbackPreview("timetable-invite", "not_found", canonicalURL);
  }

  const expiresAt = new Date(invite.expires_at);
  const status: SharePreviewStatus = invite.accepted_by
    ? "used"
    : expiresAt.getTime() <= Date.now()
      ? "expired"
      : "ok";

  const [profile, snapshot] = await Promise.all([
    fetchProfile(client, invite.owner_id),
    fetchSnapshot(client, invite.owner_id, invite.semester_id, invite.campus_id),
  ]);
  const ownerName = limitedDisplayName(profile?.nickname ?? profile?.display_name) ?? "同学";
  const courseCount = typeof snapshot?.course_count === "number" ? snapshot.course_count : undefined;
  const courseText = courseCount === undefined ? "课程快照" : `${courseCount} 门课程`;

  return {
    kind: "timetable-invite",
    status,
    title: `${ownerName} 邀请你查看共享课表`,
    description: timetableInviteDescription(status, code, courseText),
    canonicalURL,
    imageURL: appIconURL,
  };
}

async function fetchProfile(client: ServiceClient, ownerID: string) {
  const { data, error } = await client
    .from("profiles")
    .select("nickname,display_name")
    .eq("id", ownerID)
    .limit(1)
    .maybeSingle();

  if (error) {
    console.error("share-preview: profile query failed", error.message);
  }
  return data;
}

async function fetchSnapshot(
  client: ServiceClient,
  ownerID: string,
  semesterID: string,
  campusID: string | null,
) {
  let query = client
    .from("timetable_snapshots")
    .select("course_count,published_at")
    .eq("owner_id", ownerID)
    .eq("semester_id", semesterID)
    .limit(1);

  if (campusID) {
    query = query.eq("campus_id", campusID);
  }

  const { data, error } = await query.maybeSingle();
  if (error) {
    console.error("share-preview: timetable snapshot query failed", error.message);
  }
  return data;
}

function fallbackPreview(
  kind: SharePreview["kind"],
  status: SharePreviewStatus,
  canonicalURL: string,
): SharePreview {
  if (kind === "community-post") {
    return {
      kind,
      status,
      title: "MyLeafy 社区帖子",
      description: "这条帖子已不存在、不可见，或链接格式不正确。",
      canonicalURL,
      imageURL: appIconURL,
    };
  }

  return {
    kind,
    status,
    title: "MyLeafy 共享课表邀请",
    description: "复制邀请码，在 MyLeafy 的共享课表页面中接受邀请。",
    canonicalURL,
    imageURL: appIconURL,
  };
}

function timetableInviteDescription(status: SharePreviewStatus, code: string, courseText: string): string {
  switch (status) {
  case "ok":
    return `邀请码 ${code} · ${courseText} · 7 天内有效且只能被一位同学接受。`;
  case "used":
    return `邀请码 ${code} 已被接受。请让对方重新生成共享课表邀请。`;
  case "expired":
    return `邀请码 ${code} 已过期。请让对方重新生成共享课表邀请。`;
  default:
    return "复制邀请码，在 MyLeafy 的共享课表页面中接受邀请。";
  }
}

function requireServiceClient() {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    throw new Error("Missing Supabase environment variables.");
  }

  return createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false },
  });
}

function normalizeText(value: string | null | undefined): string | null {
  const trimmed = value?.replace(/\s+/g, " ").trim() ?? "";
  return trimmed.length > 0 ? trimmed : null;
}

function normalizeInviteCode(value: string | null): string {
  return (value ?? "")
    .toUpperCase()
    .replace(/[^A-Z2-7]/g, "");
}

function truncate(value: string, maxCharacters: number): string {
  const characters = Array.from(value);
  if (characters.length <= maxCharacters) {
    return value;
  }
  return `${characters.slice(0, maxCharacters).join("")}...`;
}

function limitedDisplayName(value: string | null | undefined): string | null {
  const normalized = normalizeText(value);
  if (!normalized) {
    return null;
  }
  return Array.from(normalized).slice(0, 8).join("");
}

async function sha256Hex(value: string): Promise<string> {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function json(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": status === 200 ? "public, max-age=300" : "no-store",
      ...corsHeaders,
    },
  });
}
