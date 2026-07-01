import { createClient } from "npm:@supabase/supabase-js@2";
import {
  normalizeText,
  verifyAppTransactionJWS,
} from "../_shared/campus-ai-billing.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const deepSeekChatCompletionsURL = "https://api.deepseek.com/chat/completions";
const providerName = "deepseek";
const defaultModel = "deepseek-v4-flash";
const maxMessageLength = 1200;
const maxRecentMessages = 10;
const maxUserSystemPromptLength = 3000;
const inputCacheMissCostPerMillion = 0.14;
const outputCostPerMillion = 0.28;
const encoder = new TextEncoder();

type CampusAIRequest = {
  request_id?: string;
  app_transaction_id?: string;
  app_transaction_jws?: string;
  service_mode?: string;
  message?: string;
  context?: unknown;
  recent_messages?: Array<{ role?: string; text?: string }>;
  recentMessages?: Array<{ role?: string; text?: string }>;
  user_system_prompt?: string;
  userSystemPrompt?: string;
  context_settings?: unknown;
  contextSettings?: unknown;
};

type DeepSeekUsage = {
  prompt_tokens?: number;
  prompt_cache_hit_tokens?: number;
  prompt_cache_miss_tokens?: number;
  completion_tokens?: number;
  reasoning_tokens?: number;
  total_tokens?: number;
};

type UsageCompletion = {
  requestUUID: string;
  status: "success" | "error";
  counted: boolean;
  requestCharCount: number;
  responseCharCount: number;
  usage: DeepSeekUsage;
  errorCode: string | null;
};

export async function handler(request: Request): Promise<Response> {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (request.method !== "POST") {
    return json({ error: "Method not allowed." }, 405);
  }

  if (!bearerToken(request)) {
    return json({ error: "缺少登录凭证。" }, 401);
  }

  const adminClient = makeAdminClient();
  if (!adminClient) {
    return json({ error: "AI 服务配置不完整。" }, 500);
  }

  const authResult = await authenticateUser(adminClient, request);
  if (!authResult.ok) {
    return json({ error: authResult.error }, authResult.status);
  }

  const body = await readJSON<CampusAIRequest>(request);
  const requestUUID = normalizeUUID(body.request_id);
  if (!requestUUID) {
    return json({ error: "请求标识无效。" }, 400);
  }

  if (body.service_mode !== "leafyManaged") {
    return json({ error: "托管服务只接受 Leafy 托管模式请求。" }, 400);
  }

  const message = normalizeText(body.message);
  if (!message) {
    return json({ error: "请先输入想问的问题。" }, 400);
  }
  if (message.length > maxMessageLength) {
    return json({ error: "问题太长了，请拆成更短的一次提问。" }, 400);
  }

  let appTransactionID: string | null = null;
  try {
    const appTransaction = await verifyAppTransactionJWS(
      body.app_transaction_jws,
      body.app_transaction_id,
    );
    appTransactionID = appTransaction?.appTransactionID ??
      normalizeText(body.app_transaction_id);
  } catch (error) {
    console.error(
      "campus-ai-assistant: app transaction verification failed",
      errorMessage(error),
    );
    return json({ error: "App Store 安装记录验证失败，请稍后重试。" }, 401);
  }

  if (!appTransactionID) {
    return json({ error: "缺少 App Store 安装标识。" }, 400);
  }

  const campusID = campusIDFromContext(body.context);
  const reservation = await reserveQuota(adminClient, {
    requestUUID,
    authUserID: authResult.userID,
    appTransactionID,
    campusID,
  });

  if (!reservation.allowed) {
    const status = reservation.error === "quota_exhausted" ? 402 : 429;
    const error = reservation.error === "quota_exhausted"
      ? "本月 Leafy AI 次数已用完。"
      : "AI 助手请求太频繁了，稍后再试。";
    return json({ error, quota: reservation.quota }, status);
  }

  const requestCharCount = safeJSONStringify(body).length;
  return streamResponse(async (controller, signal) => {
    let answer = "";
    let reasoning = "";
    let firstTokenSeen = false;
    let usage: DeepSeekUsage = {};
    let completed = false;

    try {
      if (reservation.quota) {
        enqueueSSE(controller, { type: "quota", quota: reservation.quota });
      }

      const result = await streamDeepSeek(body, message, signal, {
        onDelta(delta) {
          if (delta.length > 0) {
            firstTokenSeen = true;
            answer += delta;
            enqueueSSE(controller, { type: "delta", text: delta });
          }
        },
        onReasoningDelta(delta) {
          if (delta.length > 0) {
            reasoning += delta;
            enqueueSSE(controller, { type: "reasoning_delta", text: delta });
          }
        },
        onUsage(nextUsage) {
          usage = nextUsage;
        },
      });

      completed = true;
      enqueueSSE(controller, {
        type: "done",
        answer: result.answer,
        reasoning: result.reasoning,
        finish_reason: result.finishReason,
        suggested_title: shortTitle(message),
        summary: "",
      });

      await completeUsage(adminClient, {
        requestUUID,
        status: "success",
        counted: result.answer.length > 0,
        requestCharCount,
        responseCharCount: result.answer.length,
        usage,
        errorCode: null,
      });
      const quota = await quotaSnapshot(
        adminClient,
        authResult.userID,
        appTransactionID,
      );
      enqueueSSE(controller, { type: "quota", quota });
    } catch (error) {
      console.error("campus-ai-assistant: request failed", errorMessage(error));
      enqueueSSE(controller, {
        type: "error",
        error: "AI 助手暂时不可用，请稍后重试。",
      });
      await completeUsage(adminClient, {
        requestUUID,
        status: "error",
        counted: firstTokenSeen,
        requestCharCount,
        responseCharCount: answer.length + reasoning.length,
        usage,
        errorCode: signal.aborted
          ? "client_aborted"
          : completed
          ? null
          : "provider_error",
      });
      const quota = await quotaSnapshot(
        adminClient,
        authResult.userID,
        appTransactionID,
      );
      enqueueSSE(controller, { type: "quota", quota });
    }
  });
}

if (import.meta.main) {
  Deno.serve(handler);
}

async function streamDeepSeek(
  body: CampusAIRequest,
  message: string,
  signal: AbortSignal,
  callbacks: {
    onDelta: (delta: string) => void;
    onReasoningDelta: (delta: string) => void;
    onUsage: (usage: DeepSeekUsage) => void;
  },
): Promise<{ answer: string; reasoning: string; finishReason: string | null }> {
  const apiKey = Deno.env.get("DEEPSEEK_API_KEY")?.trim();
  if (!apiKey) {
    throw new Error("Missing DEEPSEEK_API_KEY.");
  }

  const response = await fetch(deepSeekChatCompletionsURL, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
      Accept: "text/event-stream",
    },
    body: JSON.stringify(deepSeekPayload(body, message)),
    signal,
  });

  if (!response.ok) {
    const responseText = await response.text();
    throw new Error(
      `DeepSeek returned ${response.status}: ${
        redactProviderError(responseText)
      }`,
    );
  }
  if (!response.body) {
    throw new Error("DeepSeek response did not include a stream body.");
  }

  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  let answer = "";
  let reasoning = "";
  let finishReason: string | null = null;

  const process = (value: string, includeRemainder = false) => {
    const result = drainDeepSeekSSEBuffer(value, {
      onDelta(delta) {
        answer += delta;
        callbacks.onDelta(delta);
      },
      onReasoningDelta(delta) {
        reasoning += delta;
        callbacks.onReasoningDelta(delta);
      },
      onFinishReason(nextFinishReason) {
        if (nextFinishReason) finishReason = nextFinishReason;
      },
      onUsage: callbacks.onUsage,
    }, includeRemainder);
    return result.remainder;
  };

  while (true) {
    const { value, done } = await reader.read();
    if (done) break;
    buffer += decoder.decode(value, { stream: true });
    buffer = process(buffer);
  }

  buffer += decoder.decode();
  process(buffer, true);
  return { answer, reasoning, finishReason };
}

export function deepSeekPayload(body: CampusAIRequest, message: string) {
  const recentMessages = recentMessagesFromBody(body)
    .slice(-maxRecentMessages)
    .map((item) => ({
      role: item.role === "assistant" ? "assistant" : "user",
      text: normalizeText(item.text) ?? "",
    }))
    .filter((item) => item.text.length > 0);

  return {
    model: defaultModel,
    messages: [
      {
        role: "system",
        content: systemPrompt(
          normalizeText(body.user_system_prompt) ??
            normalizeText(body.userSystemPrompt),
        ),
      },
      {
        role: "user",
        content: safeJSONStringify({
          message,
          context: body.context ?? {},
          context_settings: body.context_settings ?? body.contextSettings ?? {},
          recent_messages: recentMessages,
        }),
      },
    ],
    stream: true,
    stream_options: { include_usage: true },
    thinking: { type: "enabled" },
    temperature: 0.2,
    max_tokens: 1800,
    user: userCacheKey(body.app_transaction_id),
  };
}

export function systemPrompt(userSystemPrompt?: string | null) {
  const customPrompt = normalizeText(userSystemPrompt)
    ?.slice(0, maxUserSystemPromptLength);
  return [
    "你是 MyLeafy 的校园学习与生活助手，当前是测试功能。",
    "优先根据请求中提供的本机缓存或本地保存上下文回答；可以补充明确标注为一般建议的常识，但不要把常识伪装成本机数据。",
    "数据不足时直接说明缺少哪些上下文。",
    "不要声称读取了未提供的数据，不要声称读取了用户上传文件正文、图片像素、OCR、PDF、Word、PPT、表格或本地文件路径。",
    "社区内容只可当作用户当前设备已缓存的公开 feed 摘要，不要推断私信、身份资料或未缓存远端内容。",
    "医疗台账只能做整理、提醒、流程梳理和材料核对，不提供诊断、治疗、用药或医疗决策建议。",
    "回复必须是中文 Markdown。优先使用短标题、列表、加粗和清晰分段；不要输出 JSON，不要输出动作草稿。",
    customPrompt ? `用户自定义偏好：\n${customPrompt}` : "",
  ].filter(Boolean).join("\n");
}

export function campusAIResponseFormat() {
  return null;
}

export function drainDeepSeekSSEBuffer(
  value: string,
  callbacks: {
    onDelta: (delta: string) => void;
    onReasoningDelta: (delta: string) => void;
    onFinishReason: (finishReason: string | null) => void;
    onUsage: (usage: DeepSeekUsage) => void;
  },
  includeRemainder = false,
): { remainder: string } {
  let buffer = value;
  while (true) {
    const newlineIndex = buffer.indexOf("\n\n");
    const carriageIndex = buffer.indexOf("\r\n\r\n");
    const indexes = [newlineIndex, carriageIndex].filter((index) => index >= 0);
    if (indexes.length === 0) break;
    const index = Math.min(...indexes);
    const separatorLength = buffer.startsWith("\r\n\r\n", index) ? 4 : 2;
    const block = buffer.slice(0, index);
    buffer = buffer.slice(index + separatorLength);
    processDeepSeekSSEBlock(block, callbacks);
  }

  if (includeRemainder && buffer.trim().length > 0) {
    processDeepSeekSSEBlock(buffer, callbacks);
    buffer = "";
  }
  return { remainder: buffer };
}

export function processDeepSeekSSEBlock(
  block: string,
  callbacks: {
    onDelta: (delta: string) => void;
    onReasoningDelta: (delta: string) => void;
    onFinishReason: (finishReason: string | null) => void;
    onUsage: (usage: DeepSeekUsage) => void;
  },
) {
  const dataText = block
    .replaceAll("\r\n", "\n")
    .split("\n")
    .filter((line) => !line.startsWith(":"))
    .filter((line) => line.startsWith("data:"))
    .map((line) => line.slice(5).trim())
    .join("\n")
    .trim();
  if (!dataText || dataText === "[DONE]") return;

  const payload = JSON.parse(dataText) as Record<string, unknown>;
  const topLevelError = payload.error;
  if (topLevelError && typeof topLevelError === "object") {
    const message =
      normalizeText((topLevelError as Record<string, unknown>).message) ??
        "DeepSeek stream error.";
    throw new Error(redactProviderError(message));
  }

  const usage = objectValue(payload.usage);
  if (usage) callbacks.onUsage(deepSeekUsage(usage));

  const choices = Array.isArray(payload.choices) ? payload.choices : [];
  for (const choice of choices) {
    if (!choice || typeof choice !== "object") continue;
    const choiceRecord = choice as Record<string, unknown>;
    const finishReason = normalizeText(choiceRecord.finish_reason);
    if (finishReason) callbacks.onFinishReason(finishReason);

    const delta = objectValue(choiceRecord.delta);
    if (!delta) continue;
    const reasoning = stringValue(delta.reasoning_content);
    if (reasoning) callbacks.onReasoningDelta(reasoning);
    const content = stringValue(delta.content);
    if (content) callbacks.onDelta(content);
  }
}

function deepSeekUsage(payload: Record<string, unknown>): DeepSeekUsage {
  return {
    prompt_tokens: integerValue(payload.prompt_tokens) ?? 0,
    prompt_cache_hit_tokens: integerValue(payload.prompt_cache_hit_tokens) ?? 0,
    prompt_cache_miss_tokens: integerValue(payload.prompt_cache_miss_tokens) ??
      0,
    completion_tokens: integerValue(payload.completion_tokens) ?? 0,
    reasoning_tokens: integerValue(payload.reasoning_tokens) ?? 0,
    total_tokens: integerValue(payload.total_tokens) ?? 0,
  };
}

async function reserveQuota(adminClient: any, params: {
  requestUUID: string;
  authUserID: string;
  appTransactionID: string;
  campusID: string;
}) {
  const { data, error } = await adminClient.schema("private").rpc(
    "reserve_campus_ai_quota",
    {
      p_request_uuid: params.requestUUID,
      p_auth_user_id: params.authUserID,
      p_app_transaction_id: params.appTransactionID,
      p_campus_id: params.campusID,
    },
  );
  if (error) {
    console.error("campus-ai-assistant: quota reserve failed", error.message);
    return { allowed: false, error: "quota_error", quota: null };
  }
  return data as {
    allowed: boolean;
    error?: string;
    quota?: Record<string, unknown>;
  };
}

async function completeUsage(adminClient: any, event: UsageCompletion) {
  const estimatedCost = estimatedCostUSD(event.usage);
  const { error } = await adminClient.schema("private").rpc(
    "complete_campus_ai_usage",
    {
      p_request_uuid: event.requestUUID,
      p_status: event.status,
      p_counted: event.counted,
      p_request_char_count: event.requestCharCount,
      p_response_char_count: event.responseCharCount,
      p_input_tokens: event.usage.prompt_tokens ?? 0,
      p_input_cache_hit_tokens: event.usage.prompt_cache_hit_tokens ?? 0,
      p_input_cache_miss_tokens: event.usage.prompt_cache_miss_tokens ?? 0,
      p_output_tokens: event.usage.completion_tokens ?? 0,
      p_reasoning_tokens: event.usage.reasoning_tokens ?? 0,
      p_total_tokens: event.usage.total_tokens ?? 0,
      p_estimated_cost_usd: estimatedCost,
      p_error_code: event.errorCode,
    },
  );
  if (error) {
    console.error(
      "campus-ai-assistant: usage completion failed",
      error.message,
    );
  }
}

async function quotaSnapshot(
  adminClient: any,
  authUserID: string,
  appTransactionID: string,
) {
  const { data, error } = await adminClient.schema("private").rpc(
    "campus_ai_quota_snapshot",
    {
      p_auth_user_id: authUserID,
      p_app_transaction_id: appTransactionID,
    },
  );
  if (error) {
    console.error("campus-ai-assistant: quota snapshot failed", error.message);
    return null;
  }
  return data;
}

async function authenticateUser(adminClient: any, request: Request) {
  const token = bearerToken(request);
  if (!token) {
    return { ok: false as const, status: 401, error: "缺少登录凭证。" };
  }

  const { data, error } = await adminClient.auth.getUser(token);
  if (error || !data?.user?.id) {
    return {
      ok: false as const,
      status: 401,
      error: "登录状态已失效，请稍后重试。",
    };
  }
  return { ok: true as const, userID: data.user.id as string };
}

function streamResponse(
  producer: (
    controller: ReadableStreamDefaultController<Uint8Array>,
    signal: AbortSignal,
  ) => Promise<void>,
) {
  const abortController = new AbortController();
  const stream = new ReadableStream<Uint8Array>({
    async start(controller) {
      try {
        await producer(controller, abortController.signal);
      } finally {
        controller.close();
      }
    },
    cancel() {
      abortController.abort();
    },
  });

  return new Response(stream, {
    headers: {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache, no-transform",
      Connection: "keep-alive",
      ...corsHeaders,
    },
  });
}

function enqueueSSE(
  controller: ReadableStreamDefaultController<Uint8Array>,
  payload: Record<string, unknown>,
) {
  controller.enqueue(encoder.encode(`data: ${JSON.stringify(payload)}\n\n`));
}

function makeAdminClient() {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    return null;
  }
  return createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false },
  });
}

async function readJSON<T>(request: Request): Promise<T> {
  try {
    return await request.json() as T;
  } catch {
    return {} as T;
  }
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

function bearerToken(request: Request): string | null {
  const authHeader = request.headers.get("Authorization");
  if (!authHeader) return null;
  const [scheme, token] = authHeader.split(/\s+/, 2);
  return scheme?.toLowerCase() === "bearer" && token ? token : null;
}

function recentMessagesFromBody(body: CampusAIRequest) {
  if (Array.isArray(body.recent_messages)) return body.recent_messages;
  if (Array.isArray(body.recentMessages)) return body.recentMessages;
  return [];
}

function userCacheKey(appTransactionID: unknown): string | null {
  const value = normalizeText(appTransactionID);
  if (!value) return null;
  return `leafy-${hashString(value)}`;
}

function hashString(value: string) {
  let hash = 5381;
  for (const char of value) {
    hash = ((hash << 5) + hash + char.charCodeAt(0)) >>> 0;
  }
  return hash.toString(16);
}

function estimatedCostUSD(usage: DeepSeekUsage) {
  const cacheMissInput = usage.prompt_cache_miss_tokens ??
    usage.prompt_tokens ??
    0;
  const output = usage.completion_tokens ?? 0;
  return (cacheMissInput * inputCacheMissCostPerMillion +
    output * outputCostPerMillion) / 1_000_000;
}

function campusIDFromContext(context: unknown): string {
  if (context && typeof context === "object") {
    const campusID = normalizeText(
      (context as Record<string, unknown>).campusID,
    );
    if (campusID) return campusID;
  }
  return "unknown";
}

function shortTitle(message: string) {
  const compact = message
    .replace(/\s+/g, "")
    .trim();
  if (!compact) return "新的对话";
  return compact.length <= 10 ? compact : `${compact.slice(0, 9)}…`;
}

function normalizeUUID(value: unknown): string | null {
  const text = normalizeText(value);
  if (!text) return null;
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(text)
    ? text
    : null;
}

function safeJSONStringify(value: unknown): string {
  try {
    return JSON.stringify(value);
  } catch {
    return "{}";
  }
}

function objectValue(value: unknown): Record<string, unknown> | null {
  return value && typeof value === "object"
    ? value as Record<string, unknown>
    : null;
}

function stringValue(value: unknown): string | null {
  return typeof value === "string" && value.length > 0 ? value : null;
}

function integerValue(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) {
    return Math.trunc(value);
  }
  if (typeof value === "string" && value.trim().length > 0) {
    const parsed = Number.parseInt(value, 10);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

export function redactProviderError(value: string) {
  return value.replace(/sk-[A-Za-z0-9_-]+/g, "sk-redacted").slice(0, 500);
}

function errorMessage(error: unknown) {
  return error instanceof Error ? error.message : String(error);
}
