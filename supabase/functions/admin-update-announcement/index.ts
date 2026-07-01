import {
  corsHeaders,
  createAdminContext,
  json,
  normalizeText,
  readJSON,
} from "../_shared/admin-announcements.ts";

type UpdateRequest = {
  id?: string | null;
  status?: string | null;
};

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (request.method !== "POST") {
    return json({ error: "Method not allowed." }, 405);
  }

  const context = await createAdminContext(request);
  if (context instanceof Response) {
    return context;
  }

  const body = await readJSON<UpdateRequest>(request);
  const id = normalizeText(body.id);
  const status = normalizeText(body.status);

  if (!id) {
    return json({ error: "公告 ID 不能为空。" }, 400);
  }

  if (status !== "archived") {
    return json({ error: "当前仅支持下线公告。" }, 400);
  }

  const { data, error } = await context.adminClient
    .from("site_announcements")
    .update({ status })
    .eq("id", id)
    .select()
    .single();

  if (error) {
    return json({ error: error.message }, 500);
  }

  return json({ announcement: data });
});
