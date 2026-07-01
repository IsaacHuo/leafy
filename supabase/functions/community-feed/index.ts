import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
};

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (request.method !== "GET") {
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

    const url = new URL(request.url);
    const category = normalizeText(url.searchParams.get("category"));
    const search = normalizeText(url.searchParams.get("search"));
    const mode = normalizeText(url.searchParams.get("mode"));
    const requestedCampusID = normalizeCampusID(url.searchParams.get("campus_id"));
    const campusID = await resolveFeedCampusID(client, requestedCampusID);
    const days = normalizedDays(url.searchParams.get("days"));
    const limit = normalizedLimit(url.searchParams.get("limit"));

    const { data, error } = mode === "hot"
      ? await client.rpc("community_hot_posts_v1", {
        p_campus_id: campusID,
        p_days: days,
        p_limit: Math.min(limit, 10),
      })
      : await client.rpc("community_feed_v1", {
        p_campus_id: campusID,
        p_category: category,
        p_search: search,
        p_limit: limit,
      });

    if (error) {
      console.error("community-feed: rpc failed", error.message);
      return json({ error: error.message }, 500);
    }

    return json(data ?? { generated_at: new Date().toISOString(), posts: [] });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error";
    return json({ error: message }, 500);
  }
});

function normalizeText(value: string | null): string | null {
  const trimmed = value?.trim() ?? "";
  return trimmed.length > 0 ? trimmed : null;
}

function normalizeCampusID(value: string | null): string {
  return normalizeText(value)?.toLowerCase() ?? "bjfu";
}

async function resolveFeedCampusID(client: any, requestedCampusID: string): Promise<string> {
  if (requestedCampusID !== "custom" && requestedCampusID !== "general") {
    return requestedCampusID;
  }

  const { data, error } = await client.rpc("current_profile_campus_id");
  if (error) {
    console.error("community-feed: current_profile_campus_id failed", error.message);
    return requestedCampusID;
  }
  const currentCampusID = typeof data === "string" ? data.trim().toLowerCase() : "";
  return currentCampusID.length > 0 ? currentCampusID : requestedCampusID;
}

function normalizedLimit(value: string | null): number {
  const parsed = Number.parseInt(value ?? "", 10);
  if (!Number.isFinite(parsed)) {
    return 20;
  }

  return Math.max(1, Math.min(parsed, 50));
}

function normalizedDays(value: string | null): number {
  const parsed = Number.parseInt(value ?? "", 10);
  if (!Number.isFinite(parsed)) {
    return 7;
  }

  return Math.max(1, Math.min(parsed, 90));
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
