import {
  corsHeaders,
  createAdminContext,
  errorResponse,
  json,
} from "../_shared/admin-announcements.ts";

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

  const { data, error } = await context.adminClient
    .from("site_announcements")
    .select("*")
    .order("created_at", { ascending: false })
    .limit(100);

  if (error) {
    console.error(JSON.stringify({ event: "admin_list_announcements_failed", error: error.message }));
    return errorResponse(500, "backend_unavailable", "后台暂时不可用，请稍后重试。");
  }

  return json({ announcements: data ?? [] });
});
