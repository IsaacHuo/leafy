import {
  corsHeaders,
  createAdminContext,
  json,
} from "../_shared/admin-announcements.ts";

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

  const { data, error } = await context.adminClient
    .from("site_announcements")
    .select("*")
    .order("created_at", { ascending: false })
    .limit(100);

  if (error) {
    return json({ error: error.message }, 500);
  }

  return json({ announcements: data ?? [] });
});
