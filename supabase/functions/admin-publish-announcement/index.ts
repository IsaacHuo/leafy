import {
  corsHeaders,
  createAdminContext,
  errorResponse,
  json,
  normalizeDate,
  normalizeLevel,
  normalizeStatus,
  normalizeText,
  readJSON,
} from "../_shared/admin-announcements.ts";

type PublishRequest = {
  title?: string | null;
  body?: string | null;
  level?: string | null;
  status?: string | null;
  published_at?: string | null;
  expires_at?: string | null;
};

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (request.method !== "POST") {
    return errorResponse(405, "method_not_allowed", "Method not allowed.", { retryable: false });
  }

  const context = await createAdminContext(request);
  if (context instanceof Response) {
    return context;
  }

  const body = await readJSON<PublishRequest>(request);
  const title = normalizeText(body.title);
  const content = normalizeText(body.body);
  const status = normalizeStatus(body.status);
  const level = normalizeLevel(body.level);
  const publishedAt = normalizeDate(body.published_at) ?? (status === "published" ? new Date().toISOString() : null);
  const expiresAt = normalizeDate(body.expires_at);

  if (!title) {
    return errorResponse(400, "bad_request", "标题不能为空。");
  }

  if (!content) {
    return errorResponse(400, "bad_request", "正文不能为空。");
  }

  if (title.length > 120) {
    return errorResponse(400, "bad_request", "标题最多 120 个字符。");
  }

  if (content.length > 4000) {
    return errorResponse(400, "bad_request", "正文最多 4000 个字符。");
  }

  if (expiresAt && publishedAt && new Date(expiresAt).getTime() <= new Date(publishedAt).getTime()) {
    return errorResponse(400, "bad_request", "过期时间必须晚于发布时间。");
  }

  const { data, error } = await context.adminClient
    .from("site_announcements")
    .insert({
      title,
      body: content,
      level,
      status,
      published_at: publishedAt,
      expires_at: expiresAt,
      created_by: context.userID,
    })
    .select()
    .single();

  if (error) {
    console.error(JSON.stringify({ event: "admin_publish_announcement_failed", error: error.message }));
    return errorResponse(500, "backend_unavailable", "后台暂时不可用，请稍后重试。");
  }

  return json({ announcement: data });
});
