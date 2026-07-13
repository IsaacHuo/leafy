import { createClient } from "npm:@supabase/supabase-js@2";
import {
  CampusAIWebToolError,
  CampusAIWebToolName,
  fetchDocument,
  maxPDFBytes,
  readWebPage,
  searchBJFUOfficial,
  searchDuckDuckGoLite,
} from "../_shared/campus-ai-web-tools.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type ToolRequest = {
  request_id?: string;
  tool?: CampusAIWebToolName;
  arguments?: Record<string, unknown>;
};

export async function handler(request: Request): Promise<Response> {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return errorResponse("method_not_allowed", "只支持 POST 请求。", 405);
  }

  const adminClient = makeAdminClient();
  const signingSecret = Deno.env.get("CAMPUS_AI_TOOL_SIGNING_SECRET")?.trim();
  if (!adminClient || !signingSecret) {
    return errorResponse(
      "service_not_configured",
      "联网研究服务配置不完整。",
      500,
    );
  }
  const auth = await authenticateUser(adminClient, request);
  if (!auth.ok) return errorResponse("unauthorized", auth.error, 401);

  const body = await readJSON<ToolRequest>(request);
  const requestID = normalizedUUID(body.request_id);
  const tool = normalizedToolName(body.tool);
  if (!requestID || !tool) {
    return errorResponse(
      "invalid_request",
      "缺少有效的 request_id 或 tool。",
      400,
    );
  }
  if (Deno.env.get("CAMPUS_AI_WEB_SEARCH_ENABLED") === "false") {
    return errorResponse(
      "service_disabled",
      "联网研究已临时关闭，请稍后重试。",
      503,
      true,
    );
  }

  const reservation = await reserveToolCall(
    adminClient,
    auth.userID,
    requestID,
    tool,
  );
  if (!reservation.allowed) {
    const status = reservation.error === "rate_limited" ? 429 : 500;
    return errorResponse(
      reservation.error ?? "rate_limit_error",
      status === 429
        ? "联网工具调用过于频繁，请稍后重试。"
        : "联网工具暂时不可用。",
      status,
      status === 429,
    );
  }

  const startedAt = performance.now();
  let resultCount = 0;
  try {
    const args = body.arguments ?? {};
    if (tool === "official.search") {
      const result = await searchBJFUOfficial(
        stringArgument(args.query),
        integerArgument(args.count, 5),
        auth.userID,
        signingSecret,
        request.signal,
      );
      resultCount = result.length;
      await completeToolCall(
        adminClient,
        requestID,
        "success",
        elapsedMilliseconds(startedAt),
        resultCount,
        null,
      );
      return successResponse(requestID, tool, { results: result });
    }
    if (tool === "web.search") {
      const result = await searchDuckDuckGoLite(
        stringArgument(args.query),
        integerArgument(args.count, 5),
        auth.userID,
        signingSecret,
        request.signal,
      );
      resultCount = result.length;
      await completeToolCall(
        adminClient,
        requestID,
        "success",
        elapsedMilliseconds(startedAt),
        resultCount,
        null,
      );
      return successResponse(requestID, tool, { results: result });
    }
    if (tool === "web.read") {
      const result = await readWebPage(
        stringArgument(args.read_receipt),
        auth.userID,
        signingSecret,
        request.signal,
      );
      resultCount = 1;
      await completeToolCall(
        adminClient,
        requestID,
        "success",
        elapsedMilliseconds(startedAt),
        1,
        null,
      );
      return successResponse(requestID, tool, result);
    }

    const response = await fetchDocument(
      stringArgument(args.read_receipt),
      auth.userID,
      signingSecret,
      request.signal,
    );
    await completeToolCall(
      adminClient,
      requestID,
      "success",
      elapsedMilliseconds(startedAt),
      1,
      null,
    );
    const headers = new Headers(response.headers);
    headers.set("Access-Control-Allow-Origin", "*");
    headers.set("Cache-Control", "no-store");
    headers.set("Content-Type", "application/pdf");
    headers.delete("set-cookie");
    headers.delete("content-length");
    return new Response(boundedPDFStream(response.body), {
      status: 200,
      headers,
    });
  } catch (error) {
    const toolError = normalizeToolError(error);
    await completeToolCall(
      adminClient,
      requestID,
      "error",
      elapsedMilliseconds(startedAt),
      resultCount,
      toolError.code,
    );
    console.error(JSON.stringify({
      event: "campus_ai_tool_failed",
      tool,
      code: toolError.code,
      latency_ms: elapsedMilliseconds(startedAt),
    }));
    return errorResponse(
      toolError.code,
      toolError.message,
      toolError.status,
      toolError.retryable,
    );
  }
}

function boundedPDFStream(body: ReadableStream<Uint8Array> | null) {
  if (!body) return null;
  let received = 0;
  return body.pipeThrough(
    new TransformStream<Uint8Array, Uint8Array>({
      transform(chunk, controller) {
        received += chunk.byteLength;
        if (received > maxPDFBytes) {
          controller.error(
            new CampusAIWebToolError(
              "document_too_large",
              "PDF 超过 10 MB，无法分析正文。",
              413,
            ),
          );
          return;
        }
        controller.enqueue(chunk);
      },
    }),
  );
}

if (import.meta.main) {
  Deno.serve(handler);
}

async function authenticateUser(adminClient: any, request: Request) {
  const token = bearerToken(request);
  if (!token) return { ok: false as const, error: "缺少登录凭证。" };
  const { data, error } = await adminClient.auth.getUser(token);
  if (error || !data?.user?.id) {
    return { ok: false as const, error: "登录状态已失效，请稍后重试。" };
  }
  return { ok: true as const, userID: data.user.id as string };
}

function makeAdminClient() {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) return null;
  return createClient(url, key, { auth: { persistSession: false } });
}

async function reserveToolCall(
  adminClient: any,
  userID: string,
  requestID: string,
  tool: CampusAIWebToolName,
) {
  const { data, error } = await adminClient.rpc(
    "reserve_campus_ai_tool_call",
    {
      p_auth_user_id: userID,
      p_request_uuid: requestID,
      p_tool_name: tool,
    },
  );
  if (error) {
    console.error("campus-ai-tools: rate limit reserve failed", error.message);
    return { allowed: false, error: "rate_limit_error" };
  }
  return (data ?? { allowed: false, error: "rate_limit_error" }) as {
    allowed: boolean;
    error?: string;
  };
}

async function completeToolCall(
  adminClient: any,
  requestID: string,
  status: "success" | "error",
  latencyMilliseconds: number,
  resultCount: number,
  errorCode: string | null,
) {
  const { error } = await adminClient.rpc(
    "complete_campus_ai_tool_call",
    {
      p_request_uuid: requestID,
      p_status: status,
      p_latency_ms: latencyMilliseconds,
      p_result_count: resultCount,
      p_error_code: errorCode,
    },
  );
  if (error) {
    console.error("campus-ai-tools: usage completion failed", error.message);
  }
}

function normalizedToolName(value: unknown): CampusAIWebToolName | null {
  switch (value) {
    case "official.search":
    case "web.search":
    case "web.read":
    case "document.fetch":
      return value;
    default:
      return null;
  }
}

function normalizedUUID(value: unknown) {
  if (typeof value !== "string") return null;
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(value)
    ? value
    : null;
}

function bearerToken(request: Request) {
  const authorization = request.headers.get("Authorization") ?? "";
  return authorization.startsWith("Bearer ")
    ? authorization.slice("Bearer ".length).trim()
    : null;
}

function stringArgument(value: unknown) {
  return typeof value === "string" ? value.trim() : "";
}

function integerArgument(value: unknown, fallback: number) {
  return typeof value === "number" && Number.isFinite(value)
    ? Math.trunc(value)
    : fallback;
}

function elapsedMilliseconds(startedAt: number) {
  return Math.max(0, Math.round(performance.now() - startedAt));
}

function normalizeToolError(error: unknown) {
  if (error instanceof CampusAIWebToolError) return error;
  console.error("campus-ai-tools: unexpected failure", error);
  return new CampusAIWebToolError(
    "tool_failed",
    "联网工具执行失败，请稍后重试。",
    502,
    true,
  );
}

async function readJSON<T>(request: Request): Promise<T> {
  try {
    return await request.json() as T;
  } catch {
    return {} as T;
  }
}

function successResponse(
  requestID: string,
  tool: CampusAIWebToolName,
  result: unknown,
) {
  return json({ ok: true, request_id: requestID, tool, result });
}

function errorResponse(
  code: string,
  message: string,
  status: number,
  retryable = false,
) {
  return json({ ok: false, error: { code, message, retryable } }, status);
}

function json(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
    },
  });
}
