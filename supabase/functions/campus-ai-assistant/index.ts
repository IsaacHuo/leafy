import { createClient } from "npm:@supabase/supabase-js@2";
import { parse as parseHTML } from "npm:node-html-parser@6.1.13";
import {
  normalizeText,
  verifyAppTransactionJWS,
} from "../_shared/campus-ai-billing.ts";
import {
  searchBJFUOfficial,
  searchDuckDuckGoLite,
} from "../_shared/campus-ai-web-tools.ts";

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
const maxAgentToolCalls = 6;
const maxAgentSearchCalls = 3;
const maxAgentOfficialSearchCalls = 1;
const maxAgentSubtasks = 3;
const maxAgentSearchResults = 8;
const maxOfficialDocumentPages = 3;
const maxOfficialDocumentBytes = 2 * 1024 * 1024;
const officialDocumentFetchTimeoutMs = 8_000;
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
  agent_mode?: string;
  agentMode?: string;
  web_search_enabled?: boolean;
  webSearchEnabled?: boolean;
  capabilities?: unknown;
  local_retrieval?: unknown;
  localRetrieval?: unknown;
};

type CampusAIActionKind =
  | "openAcademicRoute"
  | "createCountdown"
  | "createTimetableReminder";

type CampusAIActionPayload = {
  route?: string;
  countdownTitle?: string;
  targetDate?: string;
  week?: number;
  dayOfWeek?: number;
  period?: number;
  endPeriod?: number;
  title?: string;
  location?: string;
  note?: string;
  minutesBefore?: number;
};

type CampusAIActionDraft = {
  id?: string;
  kind: CampusAIActionKind;
  title?: string;
  detail?: string;
  payload?: CampusAIActionPayload;
};

type AgentToolName =
  | "web_search"
  | "official_document_search"
  | "delegate_subtask"
  | "action_plan";

type AgentToolCall = {
  name: AgentToolName;
  arguments: Record<string, unknown>;
};

type AgentCitation = {
  id: string;
  title: string;
  url: string;
  siteName?: string;
  snippet?: string;
  summary?: string;
  publishedAt?: string;
};

type CampusAIDeliverableFormat = "html" | "markdown" | "txt";

type CampusAIDeliverableAttachment = {
  title: string;
  url: string;
  fileType: string;
};

type CampusAIDeliverableSource = {
  id: string;
  title: string;
  url: string;
  siteName?: string;
  summary?: string;
  excerpt?: string;
  trustScore: number;
  attachments: CampusAIDeliverableAttachment[];
};

type CampusAIDeliverable = {
  id: string;
  title: string;
  query: string;
  summary: string;
  generatedAt: string;
  sources: CampusAIDeliverableSource[];
  formats: CampusAIDeliverableFormat[];
};

type CampusAILocalRetrievalResult = {
  id?: string;
  domain?: string;
  title?: string;
  summary?: string;
  sourceID?: string;
  source_id?: string;
  routeHint?: string;
  route_hint?: string;
  updatedAt?: string;
  updated_at?: string;
  score?: number;
};

type AgentTraceStep = {
  id: string;
  kind: "planner" | "tool" | "delegate" | "synthesis" | "fallback";
  title: string;
  detail?: string;
  status: "running" | "completed" | "failed" | "skipped";
  tool?: string;
  role?: string;
  timestamp: string;
};

type AgentToolEvent = {
  name: string;
  status: "running" | "completed" | "failed" | "skipped";
  detail?: string;
  resultCount?: number;
};

type AgentSearchResult = {
  query: string;
  citations: AgentCitation[];
};

type AgentOfficialDocumentResult = {
  query: string;
  deliverable: CampusAIDeliverable;
};

type AgentSubtaskResult = {
  role: "researcher" | "campusAnalyst" | "operatorPlanner";
  task: string;
  result: string;
};

type DeepSeekStreamResult = {
  answer: string;
  reasoning: string;
  finishReason: string | null;
  usage?: DeepSeekUsage;
  citations?: AgentCitation[];
  agentTrace?: AgentTraceStep[];
  deliverables?: CampusAIDeliverable[];
};

type AgentCallbacks = {
  onDelta: (delta: string) => void;
  onReasoningDelta: (delta: string) => void;
  onUsage: (usage: DeepSeekUsage) => void;
  onAgentStatus?: (text: string) => void;
  onAgentStep?: (step: AgentTraceStep) => void;
  onAgentTool?: (tool: AgentToolEvent) => void;
  onAgentCitation?: (citation: AgentCitation) => void;
  onAgentSearchResults?: (results: AgentCitation[]) => void;
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

  const configuredDeepSeekKeys = deepSeekAPIKeys();
  console.info(JSON.stringify({
    event: "campus_ai_deepseek_key_count",
    count: configuredDeepSeekKeys.length,
  }));
  if (configuredDeepSeekKeys.length !== 4) {
    return json({ error: "AI 服务配置尚未完成。" }, 503);
  }

  const body = await readJSON<CampusAIRequest>(request);
  const requestUUID = normalizeUUID(body.request_id);
  if (!requestUUID) {
    return json({ error: "请求标识无效。" }, 400);
  }

  if (body.service_mode !== "leafyManaged") {
    return json({ error: "Leafy AI 服务请求模式无效。" }, 400);
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
    const isQuotaError = reservation.error === "daily_quota_exhausted" ||
      reservation.error === "period_quota_exhausted";
    const status = isQuotaError ? 402 : 429;
    const error = reservation.error === "daily_quota_exhausted"
      ? "今日次数已用完。"
      : reservation.error === "period_quota_exhausted"
      ? "本订阅周期次数已用完。"
      : "AI 助手请求太频繁了，稍后再试。";
    return json({ error, quota: reservation.quota }, status);
  }

  const requestCharCount = safeJSONStringify(body).length;
  return streamResponse(async (controller, signal) => {
    let answer = "";
    let reasoning = "";
    let firstTokenSeen = false;
    let usage: DeepSeekUsage = {};
    let citations: AgentCitation[] = [];
    let agentTrace: AgentTraceStep[] = [];
    let deliverables: CampusAIDeliverable[] = [];
    let completed = false;

    try {
      if (reservation.quota) {
        enqueueSSE(controller, { type: "quota", quota: reservation.quota });
      }

      const streamCallbacks: AgentCallbacks = {
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
        onAgentStatus(text: string) {
          enqueueSSE(controller, { type: "agent_status", text });
        },
        onAgentStep(step: AgentTraceStep) {
          agentTrace.push(step);
          enqueueSSE(controller, { type: "agent_step", step });
        },
        onAgentTool(tool: AgentToolEvent) {
          enqueueSSE(controller, { type: "agent_tool", tool });
        },
        onAgentCitation(citation: AgentCitation) {
          citations.push(citation);
          enqueueSSE(controller, { type: "agent_citation", citation });
        },
        onAgentSearchResults(results: AgentCitation[]) {
          enqueueSSE(controller, {
            type: "agent_search_results",
            results: results.map((result) => ({
              id: result.id,
              title: result.title,
              url: result.url,
              siteName: result.siteName,
            })),
          });
        },
      };

      const result = shouldRunManagedAgent(body, message)
        ? await runAgentDeepSeek(body, message, signal, streamCallbacks)
        : await streamDeepSeek(body, message, signal, streamCallbacks);
      usage = mergeUsage(usage, result.usage ?? {});
      citations = deduplicateCitations([
        ...citations,
        ...(result.citations ?? []),
      ]);
      agentTrace = deduplicateTrace([
        ...agentTrace,
        ...(result.agentTrace ?? []),
      ]);
      deliverables = deduplicateDeliverables(result.deliverables ?? []);
      if (deliverables.length === 0) {
        deliverables = deduplicateDeliverables(
          localRetrievalDeliverables(body, message, result.answer),
        );
      }

      const actionPlan = await planActions(
        body,
        message,
        result.answer,
        signal,
      );
      usage = mergeUsage(usage, actionPlan.usage);

      completed = true;
      enqueueSSE(controller, {
        type: "done",
        answer: result.answer,
        reasoning: result.reasoning,
        finish_reason: result.finishReason,
        suggested_title: shortTitle(message),
        summary: "",
        actions: actionPlan.actions,
        citations,
        deliverables,
        agentTrace,
        agent_trace: agentTrace,
      });

      await completeUsage(adminClient, {
        requestUUID,
        status: "success",
        counted: result.answer.length > 0,
        requestCharCount,
        responseCharCount: result.answer.length +
          safeJSONStringify(actionPlan.actions).length +
          safeJSONStringify(citations).length +
          safeJSONStringify(deliverables).length +
          safeJSONStringify(agentTrace).length,
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
        responseCharCount: answer.length + reasoning.length +
          safeJSONStringify(citations).length +
          safeJSONStringify(deliverables).length +
          safeJSONStringify(agentTrace).length,
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

export function shouldRunManagedAgent(body: CampusAIRequest, message: string) {
  const mode = normalizeText(body.agent_mode) ??
    normalizeText(body.agentMode) ?? "auto";
  if (mode === "off") return false;
  const allowWebSearch = webSearchEnabled(body);
  return (allowWebSearch &&
    (shouldSearchWeb(message) || shouldSearchOfficialDocument(message))) ||
    shouldDelegate(message);
}

function webSearchEnabled(body: CampusAIRequest) {
  if (typeof body.web_search_enabled === "boolean") {
    return body.web_search_enabled;
  }
  if (typeof body.webSearchEnabled === "boolean") return body.webSearchEnabled;
  return false;
}

export function shouldSearchWeb(message: string) {
  const text = message.toLowerCase();
  return [
    "搜索",
    "联网",
    "网上",
    "查一下",
    "查找",
    "最近",
    "最新",
    "新闻",
    "通知",
    "政策",
    "官网",
    "网页",
    "今天",
    "现在",
    "实时",
    "资料",
    "出处",
    "来源",
  ].some((keyword) => text.includes(keyword));
}

export function shouldSearchOfficialDocument(message: string) {
  const text = message.toLowerCase();
  const hasOfficialIntent = [
    "官网",
    "官方",
    "教务处",
    "学院",
    "政策",
    "保研",
    "推免",
    "论文",
    "格式",
    "附件",
    "模板",
    "下载",
    "通知",
    "办法",
    "规定",
  ].some((keyword) => text.includes(keyword));
  const hasDocumentIntent = [
    "网页",
    "链接",
    "入口",
    "资料",
    "文件",
    "查",
    "找",
    "搜索",
    "给我",
    "打开",
    "哪里",
    "在哪",
  ].some((keyword) => text.includes(keyword));
  return hasOfficialIntent && hasDocumentIntent;
}

function shouldDelegate(message: string) {
  const text = message.toLowerCase();
  return [
    "拆解",
    "规划",
    "计划",
    "比较",
    "分析",
    "结合",
    "安排",
    "方案",
    "多步",
  ].some((keyword) => text.includes(keyword));
}

async function runAgentDeepSeek(
  body: CampusAIRequest,
  message: string,
  signal: AbortSignal,
  callbacks: AgentCallbacks,
): Promise<DeepSeekStreamResult> {
  const agentSignal = agentTimeoutSignal(signal);
  const trace: AgentTraceStep[] = [];
  const citations: AgentCitation[] = [];
  const deliverables: CampusAIDeliverable[] = [];
  const searchResults: AgentSearchResult[] = [];
  const subtaskResults: AgentSubtaskResult[] = [];
  let usage: DeepSeekUsage = {};

  const emitStep = (step: AgentTraceStep) => {
    trace.push(step);
    callbacks.onAgentStep?.(step);
  };
  const emitTool = (tool: AgentToolEvent) => callbacks.onAgentTool?.(tool);
  const emitCitation = (citation: AgentCitation) => {
    citations.push(citation);
    callbacks.onAgentCitation?.(citation);
  };

  callbacks.onAgentStatus?.("正在拆解任务");
  emitStep(
    agentStep(
      "planner",
      "任务拆解",
      "判断是否需要搜索、委派或动作规划。",
      "running",
    ),
  );
  let toolCalls: AgentToolCall[] = [];
  try {
    const plan = await planAgentToolCalls(body, message, agentSignal);
    usage = mergeUsage(usage, plan.usage);
    toolCalls = plan.toolCalls;
    emitStep(agentStep(
      "planner",
      "任务拆解完成",
      toolCalls.length > 0
        ? `计划调用 ${toolCalls.length} 个工具。`
        : "未发现必须调用的外部工具。",
      "completed",
    ));
  } catch (error) {
    console.warn(
      "campus-ai-assistant: agent planner failed",
      redactProviderError(errorMessage(error)),
    );
    toolCalls = heuristicAgentToolCalls(message);
    emitStep(agentStep(
      "fallback",
      "任务拆解降级",
      toolCalls.length > 0 ? "已使用本地规则选择工具。" : "已回退为普通回答。",
      toolCalls.length > 0 ? "completed" : "skipped",
    ));
  }

  toolCalls = normalizeAgentToolCalls(toolCalls, {
    allowWebSearch: webSearchEnabled(body),
    message,
  });

  for (const toolCall of toolCalls) {
    if (agentSignal.aborted) {
      throw new DOMException("Agent timeout", "AbortError");
    }
    switch (toolCall.name) {
      case "web_search": {
        const query = normalizeText(toolCall.arguments.query) ?? message;
        const freshness = normalizeFreshness(toolCall.arguments.freshness);
        const count = boundedInteger(
          toolCall.arguments.count,
          1,
          maxAgentSearchResults,
          5,
        );
        callbacks.onAgentStatus?.("正在联网搜索");
        emitTool({ name: "web.search", status: "running", detail: query });
        try {
          const results = await webSearch(query, freshness, count, agentSignal);
          searchResults.push({ query, citations: results });
          callbacks.onAgentSearchResults?.(results);
          for (const citation of results) emitCitation(citation);
          emitTool({
            name: "web.search",
            status: "completed",
            detail: query,
            resultCount: results.length,
          });
          emitStep(agentStep(
            "tool",
            "联网搜索",
            results.length > 0
              ? `“${query}”返回 ${results.length} 条结果。`
              : `“${query}”没有返回可用结果。`,
            results.length > 0 ? "completed" : "skipped",
            { tool: "web.search" },
          ));
        } catch (error) {
          emitTool({
            name: "web.search",
            status: "failed",
            detail: redactProviderError(errorMessage(error)),
          });
          emitStep(agentStep(
            "tool",
            "联网搜索失败",
            "本次回答将不使用联网结果。",
            "failed",
            { tool: "web.search" },
          ));
        }
        break;
      }
      case "official_document_search": {
        const query = officialDocumentQuery(
          body,
          toolCall.arguments.query,
          message,
        );
        callbacks.onAgentStatus?.("正在查找官方资料");
        emitTool({
          name: "official.document.search",
          status: "running",
          detail: query,
        });
        try {
          const result = await officialDocumentSearch(
            body,
            query,
            message,
            agentSignal,
          );
          deliverables.push(result.deliverable);
          const resultCitations = citationsFromDeliverable(result.deliverable);
          searchResults.push({ query, citations: resultCitations });
          callbacks.onAgentSearchResults?.(resultCitations);
          for (const citation of resultCitations) emitCitation(citation);
          emitTool({
            name: "official.document.search",
            status: "completed",
            detail: query,
            resultCount: result.deliverable.sources.length,
          });
          emitStep(agentStep(
            "tool",
            "官方资料检索",
            result.deliverable.sources.length > 0
              ? `已找到 ${result.deliverable.sources.length} 个可信官方页面。`
              : "没有找到可信官方页面。",
            result.deliverable.sources.length > 0 ? "completed" : "skipped",
            { tool: "official.document.search" },
          ));
        } catch (error) {
          emitTool({
            name: "official.document.search",
            status: "failed",
            detail: redactProviderError(errorMessage(error)),
          });
          emitStep(agentStep(
            "tool",
            "官方资料检索失败",
            "本次回答将不生成资料包。",
            "failed",
            { tool: "official.document.search" },
          ));
        }
        break;
      }
      case "delegate_subtask": {
        const role = normalizeDelegateRole(toolCall.arguments.role);
        const task = normalizeText(toolCall.arguments.task);
        if (!role || !task) {
          emitStep(
            agentStep(
              "delegate",
              "委派任务跳过",
              "子任务参数不完整。",
              "skipped",
            ),
          );
          break;
        }
        callbacks.onAgentStatus?.("正在处理子任务");
        emitTool({ name: "delegate.subtask", status: "running", detail: task });
        try {
          const delegated = await runDelegatedSubtask(
            body,
            message,
            role,
            task,
            searchResults,
            agentSignal,
          );
          usage = mergeUsage(usage, delegated.usage);
          subtaskResults.push({ role, task, result: delegated.result });
          emitTool({
            name: "delegate.subtask",
            status: "completed",
            detail: task,
          });
          emitStep(agentStep(
            "delegate",
            delegateRoleTitle(role),
            task,
            "completed",
            { role },
          ));
        } catch (error) {
          emitTool({
            name: "delegate.subtask",
            status: "failed",
            detail: redactProviderError(errorMessage(error)),
          });
          emitStep(agentStep(
            "delegate",
            delegateRoleTitle(role),
            "子任务失败，已继续主回答。",
            "failed",
            { role },
          ));
        }
        break;
      }
      case "action_plan":
        emitStep(agentStep(
          "tool",
          "动作规划",
          "回答完成后会生成待确认动作卡片。",
          "completed",
          { tool: "action.plan" },
        ));
        break;
    }
  }

  callbacks.onAgentStatus?.("正在整合回答");
  emitStep(
    agentStep(
      "synthesis",
      "整合回答",
      "结合本机上下文、搜索结果和子任务结论生成最终回答。",
      "running",
    ),
  );
  const result = await streamDeepSeekAgentSynthesis(
    body,
    message,
    searchResults,
    subtaskResults,
    citations,
    deliverables,
    agentSignal,
    callbacks,
  );
  usage = mergeUsage(usage, result.usage ?? {});
  emitStep(agentStep("synthesis", "整合完成", "已生成最终回答。", "completed"));

  return {
    ...result,
    usage,
    citations: deduplicateCitations(citations),
    agentTrace: trace,
    deliverables: deduplicateDeliverables(deliverables),
  };
}

function agentTimeoutSignal(parent: AbortSignal) {
  const timeout = AbortSignal.timeout(30_000);
  return "any" in AbortSignal ? AbortSignal.any([parent, timeout]) : parent;
}

async function planAgentToolCalls(
  body: CampusAIRequest,
  message: string,
  signal: AbortSignal,
): Promise<{ toolCalls: AgentToolCall[]; usage: DeepSeekUsage }> {
  const payload = JSON.stringify(agentToolPlannerPayload(body, message));
  const response = await deepSeekJSONRequest(payload, signal, "agent planner");
  return {
    toolCalls: normalizeAgentToolCalls(
      parseAgentToolCallsFromProviderResponse(response.text),
      { allowWebSearch: webSearchEnabled(body), message },
    ),
    usage: response.usage,
  };
}

export function agentToolPlannerPayload(
  body: CampusAIRequest,
  message: string,
) {
  return {
    model: defaultModel,
    messages: [
      {
        role: "system",
        content: agentPlannerSystemPrompt(),
      },
      {
        role: "user",
        content: safeJSONStringify({
          message,
          recent_messages: recentMessagesFromBody(body).slice(-4).map((
            item,
          ) => ({
            role: item.role === "assistant" ? "assistant" : "user",
            text: (normalizeText(item.text) ?? "").slice(0, 500),
          })),
          available_tools: [
            "web.search",
            "official.document.search",
            "delegate.subtask",
            "action.plan",
          ],
          limits: {
            max_tool_calls: maxAgentToolCalls,
            max_search_calls: maxAgentSearchCalls,
            max_official_document_search_calls: maxAgentOfficialSearchCalls,
            max_subtasks: maxAgentSubtasks,
          },
        }),
      },
    ],
    tools: agentToolDefinitions(),
    tool_choice: "auto",
    stream: false,
    temperature: 0,
    max_tokens: 700,
    user: userCacheKey(body.app_transaction_id),
  };
}

function agentPlannerSystemPrompt() {
  return [
    "你是 MyLeafy 的 agent planner。你只负责决定是否调用工具，不直接回答用户。",
    "可用工具只有 web.search、official.document.search、delegate.subtask、action.plan；没有必要时不要调用工具。",
    "需要最新、最近、通知、政策、官网、出处或联网信息时调用 web.search。",
    "用户要找学校、学院、专业、教务处、政策、保研/推免、论文格式、附件、模板、下载、办法或规定的官方网页时，优先调用 official.document.search。",
    "需要拆解、比较、结合本机上下文安排方案时，可委派最多 3 个子任务。",
    "如果用户明确要求打开页面、设置倒计时或课表提醒，可调用 action.plan；最终动作仍由独立规划器生成。",
    "不要请求删除、修改成绩或课表原始数据、社区发帖评论、后台登录、医疗决策或自动远程抓取。",
  ].join("\n");
}

function agentToolDefinitions() {
  return [
    {
      type: "function",
      function: {
        name: "web_search",
        description: "Search the public web and return cited results.",
        parameters: {
          type: "object",
          properties: {
            query: { type: "string", description: "The search query." },
            freshness: {
              type: "string",
              enum: ["noLimit", "oneDay", "oneWeek", "oneMonth", "oneYear"],
              description: "Optional freshness window.",
            },
            count: {
              type: "integer",
              minimum: 1,
              maximum: maxAgentSearchResults,
              description: "Number of results to fetch.",
            },
          },
          required: ["query"],
          additionalProperties: false,
        },
      },
    },
    {
      type: "function",
      function: {
        name: "official_document_search",
        description:
          "Find trusted official school pages and attachments, then return a deliverable packet.",
        parameters: {
          type: "object",
          properties: {
            query: {
              type: "string",
              description: "The official document search query.",
            },
          },
          required: ["query"],
          additionalProperties: false,
        },
      },
    },
    {
      type: "function",
      function: {
        name: "delegate_subtask",
        description:
          "Delegate a focused reasoning subtask to a specialist role.",
        parameters: {
          type: "object",
          properties: {
            role: {
              type: "string",
              enum: ["researcher", "campusAnalyst", "operatorPlanner"],
            },
            task: { type: "string", description: "A focused subtask." },
          },
          required: ["role", "task"],
          additionalProperties: false,
        },
      },
    },
    {
      type: "function",
      function: {
        name: "action_plan",
        description:
          "Mark that a confirmable in-app action may be useful after the answer.",
        parameters: {
          type: "object",
          properties: {
            reason: { type: "string" },
          },
          required: ["reason"],
          additionalProperties: false,
        },
      },
    },
  ];
}

export function parseAgentToolCallsFromProviderResponse(responseText: string) {
  const payload = JSON.parse(responseText) as Record<string, unknown>;
  const choices = Array.isArray(payload.choices) ? payload.choices : [];
  const toolCalls: AgentToolCall[] = [];
  for (const choice of choices) {
    const message = objectValue(objectValue(choice)?.message);
    const rawToolCalls = Array.isArray(message?.tool_calls)
      ? message?.tool_calls as unknown[]
      : [];
    for (const rawToolCall of rawToolCalls) {
      const callRecord = objectValue(rawToolCall);
      const functionRecord = objectValue(callRecord?.function);
      const name = normalizeToolName(stringValue(functionRecord?.name));
      if (!name) continue;
      toolCalls.push({
        name,
        arguments: parseToolArguments(functionRecord?.arguments),
      });
    }

    const content = stringValue(message?.content);
    if (content) toolCalls.push(...parseAgentToolCallsFromContent(content));
  }
  return toolCalls;
}

function parseAgentToolCallsFromContent(content: string): AgentToolCall[] {
  for (const candidate of actionPlannerJSONCandidates(content)) {
    try {
      const parsed = JSON.parse(candidate);
      const rawCalls = Array.isArray(parsed)
        ? parsed
        : Array.isArray(parsed?.tool_calls)
        ? parsed.tool_calls
        : Array.isArray(parsed?.tools)
        ? parsed.tools
        : [];
      const parsedCalls: Array<AgentToolCall | null> = rawCalls.map(
        (item: unknown) => {
          const record = objectValue(item);
          const name = normalizeToolName(
            stringValue(record?.name) ?? stringValue(record?.tool),
          );
          if (!name) return null;
          return {
            name,
            arguments: objectValue(record?.arguments) ?? record ?? {},
          } satisfies AgentToolCall;
        },
      );
      return parsedCalls.filter((item): item is AgentToolCall => item !== null);
    } catch {
      // Try the next candidate.
    }
  }
  return [];
}

function parseToolArguments(value: unknown): Record<string, unknown> {
  if (typeof value === "string") {
    try {
      const parsed = JSON.parse(value);
      return objectValue(parsed) ?? {};
    } catch {
      return {};
    }
  }
  return objectValue(value) ?? {};
}

function normalizeToolName(value: string | null): AgentToolName | null {
  switch (value) {
    case "web_search":
    case "web.search":
      return "web_search";
    case "official_document_search":
    case "official.document.search":
      return "official_document_search";
    case "delegate_subtask":
    case "delegate.subtask":
      return "delegate_subtask";
    case "action_plan":
    case "action.plan":
      return "action_plan";
    default:
      return null;
  }
}

export function normalizeAgentToolCalls(
  toolCalls: AgentToolCall[],
  options: { allowWebSearch: boolean; message: string },
) {
  const normalized: AgentToolCall[] = [];
  let searchCount = 0;
  let officialSearchCount = 0;
  let subtaskCount = 0;
  for (const toolCall of toolCalls) {
    if (normalized.length >= maxAgentToolCalls) break;
    switch (toolCall.name) {
      case "web_search": {
        if (!options.allowWebSearch || searchCount >= maxAgentSearchCalls) {
          break;
        }
        const query = safeAgentSearchQuery(
          toolCall.arguments.query,
          options.message,
        );
        if (!query) break;
        searchCount += 1;
        normalized.push({
          name: "web_search",
          arguments: {
            query,
            freshness: normalizeFreshness(toolCall.arguments.freshness),
            count: boundedInteger(
              toolCall.arguments.count,
              1,
              maxAgentSearchResults,
              5,
            ),
          },
        });
        break;
      }
      case "official_document_search": {
        if (
          !options.allowWebSearch ||
          officialSearchCount >= maxAgentOfficialSearchCalls
        ) {
          break;
        }
        const query = safeAgentSearchQuery(
          toolCall.arguments.query,
          options.message,
        );
        if (!query) break;
        officialSearchCount += 1;
        normalized.push({
          name: "official_document_search",
          arguments: { query },
        });
        break;
      }
      case "delegate_subtask": {
        if (subtaskCount >= maxAgentSubtasks) break;
        const role = normalizeDelegateRole(toolCall.arguments.role);
        const task = normalizeText(toolCall.arguments.task);
        if (!role || !task) break;
        subtaskCount += 1;
        normalized.push({
          name: "delegate_subtask",
          arguments: { role, task },
        });
        break;
      }
      case "action_plan":
        normalized.push({
          name: "action_plan",
          arguments: {
            reason: normalizeText(toolCall.arguments.reason) ??
              "用户可能需要确认动作。",
          },
        });
        break;
    }
  }

  if (
    options.allowWebSearch &&
    officialSearchCount === 0 &&
    shouldSearchOfficialDocument(options.message) &&
    normalized.length < maxAgentToolCalls
  ) {
    normalized.unshift({
      name: "official_document_search",
      arguments: {
        query: normalizeSearchQuery(options.message) ?? options.message,
      },
    });
  }

  if (
    options.allowWebSearch &&
    searchCount === 0 &&
    shouldSearchWeb(options.message) &&
    normalized.length < maxAgentToolCalls
  ) {
    normalized.unshift({
      name: "web_search",
      arguments: {
        query: normalizeSearchQuery(options.message) ?? options.message,
        freshness: "oneMonth",
        count: 5,
      },
    });
  }
  return normalized
    .sort((left, right) => agentToolPriority(left) - agentToolPriority(right))
    .slice(0, maxAgentToolCalls);
}

function heuristicAgentToolCalls(message: string): AgentToolCall[] {
  const calls: AgentToolCall[] = [];
  if (shouldSearchOfficialDocument(message)) {
    calls.push({
      name: "official_document_search",
      arguments: {
        query: normalizeSearchQuery(message) ?? message,
      },
    });
  }
  if (shouldSearchWeb(message)) {
    calls.push({
      name: "web_search",
      arguments: {
        query: normalizeSearchQuery(message) ?? message,
        freshness: "oneMonth",
        count: 5,
      },
    });
  }
  if (shouldDelegate(message)) {
    calls.push({
      name: "delegate_subtask",
      arguments: {
        role: "campusAnalyst",
        task: "结合本机上下文和可用搜索结果，整理对用户最有用的校园安排建议。",
      },
    });
  }
  return calls;
}

function agentToolPriority(toolCall: AgentToolCall) {
  switch (toolCall.name) {
    case "official_document_search":
      return 0;
    case "web_search":
      return 1;
    case "delegate_subtask":
      return 2;
    case "action_plan":
      return 3;
    default:
      return 4;
  }
}

function normalizeSearchQuery(message: string) {
  return normalizeText(message)
    ?.replace(/^(帮我|请|麻烦你)?(联网)?(搜索|查一下|查找)/, "")
    .slice(0, 160)
    .trim();
}

export function safeAgentSearchQuery(candidate: unknown, original: string) {
  const originalQuery = normalizeSearchQuery(original) ??
    normalizeText(original);
  if (!originalQuery) return null;
  const candidateQuery = normalizeText(candidate);
  if (!candidateQuery) return originalQuery;

  const originalYears = originalQuery.match(/(?:19|20)\d{2}/g) ?? [];
  if (originalYears.some((year) => !candidateQuery.includes(year))) {
    return originalQuery;
  }

  const originalAnchors = substantiveSearchAnchors(originalQuery);
  if (originalAnchors.length === 0) return originalQuery;
  const candidateAnchors = new Set(substantiveSearchAnchors(candidateQuery));
  const preservesAnchor = originalAnchors.some((anchor) =>
    candidateAnchors.has(anchor) ||
    campusSearchSynonymMatch(anchor, candidateQuery)
  );
  return preservesAnchor ? candidateQuery.slice(0, 180) : originalQuery;
}

function substantiveSearchAnchors(value: string) {
  const normalized = value.toLowerCase()
    .replace(/[\p{P}\p{S}\s]+/gu, "")
    .replace(/(?:19|20)\d{2}/g, "")
    .replace(
      /(?:北京林业大学|北林|官网|官方|最新|最近|搜索|查找|查一下|资料|网页|通知|政策|链接|来源|出处)/g,
      "",
    );
  const anchors = new Set<string>();
  for (const word of value.toLowerCase().match(/[a-z0-9]{3,}/g) ?? []) {
    anchors.add(word);
  }
  for (let index = 0; index + 1 < normalized.length; index += 1) {
    anchors.add(normalized.slice(index, index + 2));
  }
  if (/(保研|推免|推荐免试|免试攻读)/.test(value)) anchors.add("推免");
  return [...anchors];
}

function campusSearchSynonymMatch(anchor: string, candidate: string) {
  return anchor === "推免" && /(保研|推免|推荐免试|免试攻读)/.test(candidate);
}

function normalizeFreshness(value: unknown) {
  const text = normalizeText(value);
  switch (text) {
    case "oneDay":
    case "oneWeek":
    case "oneMonth":
    case "oneYear":
    case "noLimit":
      return text;
    default:
      return "oneMonth";
  }
}

function normalizeDelegateRole(
  value: unknown,
): "researcher" | "campusAnalyst" | "operatorPlanner" | null {
  switch (normalizeText(value)) {
    case "researcher":
      return "researcher";
    case "campusAnalyst":
      return "campusAnalyst";
    case "operatorPlanner":
      return "operatorPlanner";
    default:
      return null;
  }
}

function delegateRoleTitle(role: string) {
  switch (role) {
    case "researcher":
      return "资料研究";
    case "campusAnalyst":
      return "校园分析";
    case "operatorPlanner":
      return "操作规划";
    default:
      return "子任务";
  }
}

export async function webSearch(
  query: string,
  _freshness: string,
  count: number,
  signal: AbortSignal,
) {
  const signingSecret = Deno.env.get("CAMPUS_AI_TOOL_SIGNING_SECRET")?.trim();
  if (!signingSecret) {
    throw new Error("CAMPUS_AI_TOOL_SIGNING_SECRET is not configured.");
  }
  const results = await searchDuckDuckGoLite(
    query,
    count,
    "managed-agent",
    signingSecret,
    signal,
  );
  return results.map((result) => ({
    id: result.id,
    title: result.title,
    url: result.url,
    siteName: result.source_kind === "bjfu_official"
      ? "北京林业大学"
      : result.display_host,
    snippet: result.snippet,
  } satisfies AgentCitation));
}

function officialDocumentQuery(
  body: CampusAIRequest,
  requestedQuery: unknown,
  message: string,
) {
  const query = normalizeText(requestedQuery) ??
    normalizeSearchQuery(message) ??
    message;
  const campusName = campusNameFromContext(body.context);
  if (!campusName || query.includes(campusName)) return query;
  return `${campusName} ${query}`.slice(0, 180);
}

async function officialDocumentSearch(
  body: CampusAIRequest,
  query: string,
  userMessage: string,
  signal: AbortSignal,
): Promise<AgentOfficialDocumentResult> {
  const signingSecret = Deno.env.get("CAMPUS_AI_TOOL_SIGNING_SECRET")?.trim();
  if (!signingSecret) {
    throw new Error("CAMPUS_AI_TOOL_SIGNING_SECRET is not configured.");
  }
  const officialResults = await searchBJFUOfficial(
    query,
    maxAgentSearchResults,
    "managed-agent",
    signingSecret,
    signal,
  );
  const citations = officialResults.map((result) => ({
    id: result.id,
    title: result.title,
    url: result.url,
    siteName: "北京林业大学",
    snippet: result.snippet,
  } satisfies AgentCitation));
  const candidates = citations
    .filter((citation) => isSafePublicHTTPURL(citation.url))
    .map((citation) => ({
      citation,
      trustScore: officialDocumentTrustScore(citation, body.context),
    }))
    .filter((candidate) => candidate.trustScore >= 45)
    .sort((lhs, rhs) => rhs.trustScore - lhs.trustScore)
    .slice(0, maxOfficialDocumentPages);

  const sources: CampusAIDeliverableSource[] = [];
  for (const candidate of candidates) {
    if (signal.aborted) throw new DOMException("Agent timeout", "AbortError");
    const source = await fetchOfficialDocumentSource(
      candidate.citation,
      candidate.trustScore,
      signal,
    );
    if (source) sources.push(source);
  }

  const deliverable = officialDocumentDeliverable(
    query,
    sources,
    artifactFormatsForMessage(userMessage),
  );
  return { query, deliverable };
}

export function officialDocumentFreshness(message: string) {
  const text = message.toLowerCase();
  if (
    ["最新", "最近", "今天", "现在", "实时", "近期"].some((keyword) =>
      text.includes(keyword)
    )
  ) {
    return "oneMonth";
  }
  return "noLimit";
}

async function fetchOfficialDocumentSource(
  citation: AgentCitation,
  trustScore: number,
  parentSignal: AbortSignal,
): Promise<CampusAIDeliverableSource | null> {
  const timeout = AbortSignal.timeout(officialDocumentFetchTimeoutMs);
  const signal = "any" in AbortSignal
    ? AbortSignal.any([parentSignal, timeout])
    : parentSignal;
  let response: Response;
  try {
    response = await fetch(citation.url, {
      headers: {
        Accept: "text/html,application/xhtml+xml",
        "User-Agent":
          "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 MyLeafy/1.0",
      },
      redirect: "follow",
      signal,
    });
  } catch {
    return fallbackOfficialSource(citation, trustScore);
  }

  if (!response.ok) return fallbackOfficialSource(citation, trustScore);
  const responseURL = response.url || citation.url;
  if (!isSafePublicHTTPURL(responseURL)) return null;
  const contentType = response.headers.get("content-type")?.toLowerCase() ?? "";
  if (
    contentType && !contentType.includes("text/html") &&
    !contentType.includes("application/xhtml")
  ) {
    return fallbackOfficialSource(citation, trustScore);
  }

  const html = await boundedResponseText(response, maxOfficialDocumentBytes);
  if (!html) return fallbackOfficialSource(citation, trustScore);
  return extractOfficialDocumentSourceFromHTML(
    html,
    responseURL,
    citation,
    trustScore,
  );
}

async function boundedResponseText(response: Response, maxBytes: number) {
  const body = response.body;
  if (!body) return "";
  const reader = body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  while (true) {
    const { value, done } = await reader.read();
    if (done) break;
    if (!value) continue;
    total += value.byteLength;
    if (total > maxBytes) {
      try {
        await reader.cancel();
      } catch {
        // Ignore cancellation failures.
      }
      break;
    }
    chunks.push(value);
  }

  const data = new Uint8Array(
    chunks.reduce((sum, chunk) => sum + chunk.byteLength, 0),
  );
  let offset = 0;
  for (const chunk of chunks) {
    data.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return new TextDecoder("utf-8", { fatal: false }).decode(data);
}

export function extractOfficialDocumentSourceFromHTML(
  html: string,
  pageURL: string,
  citation: AgentCitation,
  trustScore: number,
): CampusAIDeliverableSource | null {
  if (!isSafePublicHTTPURL(pageURL)) return null;
  const root = parseHTML(html);
  const canonicalURL = canonicalURLFromHTML(root, pageURL);
  const url = isSafePublicHTTPURL(canonicalURL) ? canonicalURL : pageURL;
  const title = normalizeText(root.querySelector("title")?.text) ??
    citation.title;
  const bodyText = normalizeText(root.querySelector("body")?.structuredText) ??
    normalizeText(root.structuredText) ??
    citation.summary ??
    citation.snippet ??
    "";
  const excerpt = bodyText.slice(0, 260);
  const attachments = extractOfficialDocumentAttachments(root, url);

  return {
    id: `official-${hashString(url)}`,
    title,
    url,
    siteName: citation.siteName,
    summary: citation.summary ?? citation.snippet,
    excerpt,
    trustScore,
    attachments,
  };
}

function canonicalURLFromHTML(
  root: ReturnType<typeof parseHTML>,
  pageURL: string,
) {
  for (const link of root.querySelectorAll("link")) {
    const rel = link.getAttribute("rel")?.toLowerCase() ?? "";
    if (!rel.split(/\s+/).includes("canonical")) continue;
    const href = link.getAttribute("href");
    if (!href) continue;
    const absolute = absoluteURL(href, pageURL);
    if (absolute) return absolute;
  }
  return pageURL;
}

function extractOfficialDocumentAttachments(
  root: ReturnType<typeof parseHTML>,
  pageURL: string,
) {
  const attachments: CampusAIDeliverableAttachment[] = [];
  const seen = new Set<string>();
  for (const anchor of root.querySelectorAll("a")) {
    const href = anchor.getAttribute("href");
    if (!href) continue;
    const url = absoluteURL(href, pageURL);
    if (!url || !isSafePublicHTTPURL(url)) continue;
    const fileType = attachmentFileType(url);
    if (!fileType) continue;
    if (seen.has(url)) continue;
    seen.add(url);
    attachments.push({
      title: normalizeText(anchor.structuredText) ??
        normalizeText(anchor.text) ??
        filenameFromURL(url) ??
        `${fileType} 附件`,
      url,
      fileType,
    });
    if (attachments.length >= 12) break;
  }
  return attachments;
}

function fallbackOfficialSource(
  citation: AgentCitation,
  trustScore: number,
): CampusAIDeliverableSource | null {
  if (!isSafePublicHTTPURL(citation.url)) return null;
  return {
    id: `official-${hashString(citation.url)}`,
    title: citation.title,
    url: citation.url,
    siteName: citation.siteName,
    summary: citation.summary ?? citation.snippet,
    excerpt: citation.summary ?? citation.snippet,
    trustScore,
    attachments: [],
  };
}

export function officialDocumentDeliverable(
  query: string,
  sources: CampusAIDeliverableSource[],
  formats: CampusAIDeliverableFormat[] = artifactFormatsForMessage(query),
): CampusAIDeliverable {
  const attachmentCount = sources.reduce(
    (sum, source) => sum + source.attachments.length,
    0,
  );
  const summary = sources.length > 0
    ? `已整理 ${sources.length} 个官方来源，包含 ${attachmentCount} 个附件链接。`
    : "未找到可信官方来源，请尝试补充学校、学院或政策名称。";
  return {
    id: `deliverable-${
      hashString(`${query}|${sources.map((source) => source.url).join("|")}`)
    }`,
    title: "官方资料包",
    query,
    summary,
    generatedAt: new Date().toISOString(),
    sources,
    formats,
  };
}

function citationsFromDeliverable(deliverable: CampusAIDeliverable) {
  return deliverable.sources.map((source, index) => ({
    id: `official-citation-${hashString(`${source.url}|${index}`)}`,
    title: source.title,
    url: source.url,
    siteName: source.siteName,
    summary: source.summary ?? source.excerpt,
  } satisfies AgentCitation));
}

export function localRetrievalDeliverables(
  body: CampusAIRequest,
  message: string,
  answer: string,
): CampusAIDeliverable[] {
  if (!shouldGenerateLocalArtifact(message)) return [];
  const results = localRetrievalResults(body);
  if (results.length === 0) return [];

  const sources = results.slice(0, 12).map((result, index) => {
    const domain = normalizeText(result.domain) ?? "local";
    const sourceID = normalizeText(result.sourceID) ??
      normalizeText(result.source_id) ??
      result.id ??
      `item-${index}`;
    const title = normalizeText(result.title) ?? localDomainTitle(domain);
    return {
      id: `local-${hashString(`${domain}|${sourceID}|${title}`)}`,
      title,
      url: `leafy://local/${encodeURIComponent(domain)}/${
        encodeURIComponent(sourceID)
      }`,
      siteName: `Leafy ${localDomainTitle(domain)}`,
      summary: normalizeText(result.summary)?.slice(0, 520),
      trustScore: 1,
      attachments: [],
    } satisfies CampusAIDeliverableSource;
  });

  return [{
    id: `local-deliverable-${
      hashString(`${message}|${sources.map((source) => source.id).join("|")}`)
    }`,
    title: `${normalizeText(message)?.slice(0, 32) || "本地资料"}资料包`,
    query: message,
    summary: normalizeText(answer)?.slice(0, 240) ??
      "已根据相关本地资料整理为可打开的本地文件。",
    generatedAt: new Date().toISOString(),
    sources,
    formats: artifactFormatsForMessage(message),
  }];
}

function artifactFormatsForMessage(
  message: string,
): CampusAIDeliverableFormat[] {
  const text = message.toLowerCase();
  const formats: CampusAIDeliverableFormat[] = [];
  if (
    ["html", "网页", "浏览器", "浏览", "网站"].some((keyword) =>
      text.includes(keyword)
    )
  ) {
    formats.push("html");
  }
  if (
    ["markdown", "md", "markdown 文件"].some((keyword) =>
      text.includes(keyword)
    )
  ) {
    formats.push("markdown");
  }
  if (
    ["txt", "文本", "纯文本"].some((keyword) => text.includes(keyword))
  ) {
    formats.push("txt");
  }
  return formats.length === 0
    ? ["html"]
    : (["html", "markdown", "txt"] as CampusAIDeliverableFormat[]).filter((
      format,
    ) => formats.includes(format));
}

function shouldGenerateLocalArtifact(message: string) {
  const text = message.toLowerCase();
  return [
    "资料包",
    "交付",
    "导出",
    "生成文件",
    "整理成文件",
    "html",
    "markdown",
    "txt",
    "md 文件",
    "文档",
  ].some((keyword) => text.includes(keyword));
}

function localRetrievalResults(body: CampusAIRequest) {
  const payload = objectValue(localRetrievalFromBody(body));
  const results = Array.isArray(payload?.results) ? payload.results : [];
  return results
    .map((item) => objectValue(item) as CampusAILocalRetrievalResult | null)
    .filter((item): item is CampusAILocalRetrievalResult => {
      if (!item) return false;
      const title = normalizeText(item.title);
      const summary = normalizeText(item.summary);
      return !!title || !!summary;
    });
}

function localDomainTitle(domain: string) {
  switch (domain) {
    case "schedule":
      return "时间日程";
    case "learning":
      return "学习资料";
    case "academics":
      return "学业成绩";
    case "postgraduateCareer":
      return "考研职业";
    case "fitnessSports":
      return "体育体测";
    case "honorsQuality":
      return "荣誉综测";
    case "medical":
      return "医疗台账";
    case "community":
      return "社区公开摘要";
    default:
      return "本地资料";
  }
}

async function runDelegatedSubtask(
  body: CampusAIRequest,
  message: string,
  role: "researcher" | "campusAnalyst" | "operatorPlanner",
  task: string,
  searchResults: AgentSearchResult[],
  signal: AbortSignal,
) {
  const payload = JSON.stringify({
    model: defaultModel,
    messages: [
      {
        role: "system",
        content: [
          `你是 MyLeafy 的 ${delegateRoleTitle(role)} 子代理。`,
          "只根据输入的本机上下文、搜索结果和任务要求输出中文要点。",
          "不要生成 JSON，不要声称执行了任何写入动作。",
        ].join("\n"),
      },
      {
        role: "user",
        content: safeJSONStringify({
          user_message: message,
          task,
          context: body.context ?? {},
          local_retrieval: localRetrievalFromBody(body),
          search_results: searchResults,
        }),
      },
    ],
    stream: false,
    temperature: 0.2,
    max_tokens: 700,
    user: userCacheKey(body.app_transaction_id),
  });
  const response = await deepSeekJSONRequest(
    payload,
    signal,
    "delegated subtask",
  );
  return {
    result: parseDeepSeekMessageContent(response.text).slice(0, 2400),
    usage: response.usage,
  };
}

async function streamDeepSeekAgentSynthesis(
  body: CampusAIRequest,
  message: string,
  searchResults: AgentSearchResult[],
  subtaskResults: AgentSubtaskResult[],
  citations: AgentCitation[],
  deliverables: CampusAIDeliverable[],
  signal: AbortSignal,
  callbacks: AgentCallbacks,
): Promise<DeepSeekStreamResult> {
  const apiKeys = deepSeekAPIKeys();
  if (apiKeys.length === 0) {
    throw new Error("Missing DEEPSEEK_API_KEY or DEEPSEEK_API_KEYS.");
  }

  const payload = JSON.stringify(agentSynthesisPayload(
    body,
    message,
    searchResults,
    subtaskResults,
    citations,
    deliverables,
  ));
  let lastError: Error | null = null;
  for (const [index, apiKey] of apiKeys.entries()) {
    const response = await fetch(deepSeekChatCompletionsURL, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
        Accept: "text/event-stream",
      },
      body: payload,
      signal,
    });
    if (!response.ok) {
      const responseText = await response.text();
      const error = new Error(
        `DeepSeek agent synthesis key ${
          index + 1
        }/${apiKeys.length} returned ${response.status}: ${
          redactProviderError(responseText)
        }`,
      );
      if (
        index < apiKeys.length - 1 &&
        shouldRetryDeepSeekStatus(response.status)
      ) {
        lastError = error;
        continue;
      }
      throw error;
    }
    return await readDeepSeekStream(response, callbacks);
  }
  throw lastError ?? new Error("DeepSeek agent synthesis failed.");
}

export function agentSynthesisPayload(
  body: CampusAIRequest,
  message: string,
  searchResults: AgentSearchResult[],
  subtaskResults: AgentSubtaskResult[],
  citations: AgentCitation[],
  deliverables: CampusAIDeliverable[] = [],
) {
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
        content: agentSynthesisSystemPrompt(
          normalizeText(body.user_system_prompt) ??
            normalizeText(body.userSystemPrompt),
          citations.length > 0,
        ),
      },
      {
        role: "user",
        content: safeJSONStringify({
          message,
          context: body.context ?? {},
          context_settings: body.context_settings ?? body.contextSettings ?? {},
          capabilities: body.capabilities ?? {},
          local_retrieval: localRetrievalFromBody(body),
          recent_messages: recentMessages,
          web_search_results: searchResults,
          subtask_results: subtaskResults,
          citations,
          official_document_deliverables: deliverables,
        }),
      },
    ],
    stream: true,
    stream_options: { include_usage: true },
    thinking: { type: "enabled" },
    temperature: 0.2,
    user: userCacheKey(body.app_transaction_id),
  };
}

function agentSynthesisSystemPrompt(
  userSystemPrompt: string | null,
  hasCitations: boolean,
) {
  return [
    systemPrompt(userSystemPrompt),
    "你现在处于 agent 模式。请整合本机上下文、联网搜索结果和子任务结论。",
    "如果输入包含 local_retrieval，优先使用其中最相关的本地结果；不需要说明内部检索流程。",
    hasCitations
      ? "使用联网结果时，必须在相关句子后用 Markdown 链接标注来源，优先引用输入 citations 中的 URL。"
      : "本次没有可用联网搜索结果；如果问题需要最新信息，请明确说明未使用联网结果。",
    "如果输入包含 official_document_deliverables，请简要说明已整理资料包；不要把 HTML、Markdown 或 TXT 文件全文复制到回答正文。",
    "不要输出工具调用 JSON、内部 trace 或动作草稿。",
  ].join("\n");
}

async function deepSeekJSONRequest(
  payload: string,
  signal: AbortSignal,
  label: string,
): Promise<{ text: string; usage: DeepSeekUsage }> {
  const apiKeys = deepSeekAPIKeys();
  let lastError: Error | null = null;
  for (const [index, apiKey] of apiKeys.entries()) {
    let response: Response;
    try {
      response = await fetch(deepSeekChatCompletionsURL, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${apiKey}`,
          "Content-Type": "application/json",
          Accept: "application/json",
        },
        body: payload,
        signal,
      });
    } catch (error) {
      if (signal.aborted || index === apiKeys.length - 1) throw error;
      lastError = new Error(redactProviderError(errorMessage(error)));
      continue;
    }
    const text = await response.text();
    if (!response.ok) {
      const error = new Error(
        `DeepSeek ${label} key ${
          index + 1
        }/${apiKeys.length} returned ${response.status}: ${
          redactProviderError(text)
        }`,
      );
      if (
        index < apiKeys.length - 1 &&
        shouldRetryDeepSeekStatus(response.status)
      ) {
        lastError = error;
        continue;
      }
      throw error;
    }
    const payloadObject = JSON.parse(text) as Record<string, unknown>;
    const usagePayload = objectValue(payloadObject.usage);
    return {
      text,
      usage: usagePayload ? deepSeekUsage(usagePayload) : {},
    };
  }
  throw lastError ?? new Error(`DeepSeek ${label} request failed.`);
}

function parseDeepSeekMessageContent(responseText: string) {
  const payload = JSON.parse(responseText) as Record<string, unknown>;
  const choices = Array.isArray(payload.choices) ? payload.choices : [];
  return choices
    .map((choice) => objectValue(choice))
    .map((choice) => objectValue(choice?.message))
    .map((message) => stringValue(message?.content))
    .find((value) => !!value) ?? "";
}

function agentStep(
  kind: AgentTraceStep["kind"],
  title: string,
  detail: string,
  status: AgentTraceStep["status"],
  extra: { tool?: string; role?: string } = {},
): AgentTraceStep {
  return {
    id: crypto.randomUUID(),
    kind,
    title,
    detail,
    status,
    tool: extra.tool,
    role: extra.role,
    timestamp: new Date().toISOString(),
  };
}

async function streamDeepSeek(
  body: CampusAIRequest,
  message: string,
  signal: AbortSignal,
  callbacks: AgentCallbacks,
): Promise<DeepSeekStreamResult> {
  const apiKeys = deepSeekAPIKeys();
  if (apiKeys.length === 0) {
    throw new Error("Missing DEEPSEEK_API_KEY or DEEPSEEK_API_KEYS.");
  }

  const payload = JSON.stringify(deepSeekPayload(body, message));
  let lastError: Error | null = null;
  for (const [index, apiKey] of apiKeys.entries()) {
    let response: Response;
    try {
      response = await fetch(deepSeekChatCompletionsURL, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${apiKey}`,
          "Content-Type": "application/json",
          Accept: "text/event-stream",
        },
        body: payload,
        signal,
      });
    } catch (error) {
      if (signal.aborted || index === apiKeys.length - 1) throw error;
      lastError = new Error(redactProviderError(errorMessage(error)));
      console.warn(
        `campus-ai-assistant: DeepSeek key ${
          index + 1
        }/${apiKeys.length} failed before stream; trying fallback`,
        lastError.message,
      );
      continue;
    }

    if (!response.ok) {
      const responseText = await response.text();
      const error = new Error(
        `DeepSeek key ${
          index + 1
        }/${apiKeys.length} returned ${response.status}: ${
          redactProviderError(responseText)
        }`,
      );
      if (
        index < apiKeys.length - 1 &&
        shouldRetryDeepSeekStatus(response.status)
      ) {
        lastError = error;
        console.warn(
          "campus-ai-assistant: DeepSeek key failed before stream; trying fallback",
          error.message,
        );
        continue;
      }
      throw error;
    }
    if (!response.body) {
      throw new Error("DeepSeek response did not include a stream body.");
    }
    return await readDeepSeekStream(response, callbacks);
  }

  throw lastError ?? new Error("DeepSeek request failed.");
}

async function planActions(
  body: CampusAIRequest,
  message: string,
  answer: string,
  signal: AbortSignal,
): Promise<{ actions: CampusAIActionDraft[]; usage: DeepSeekUsage }> {
  if (!answer.trim()) return { actions: [], usage: {} };

  try {
    const payload = JSON.stringify(actionPlannerPayload(body, message, answer));
    const apiKeys = deepSeekAPIKeys();
    let lastError: Error | null = null;
    for (const [index, apiKey] of apiKeys.entries()) {
      let response: Response;
      try {
        response = await fetch(deepSeekChatCompletionsURL, {
          method: "POST",
          headers: {
            Authorization: `Bearer ${apiKey}`,
            "Content-Type": "application/json",
            Accept: "application/json",
          },
          body: payload,
          signal,
        });
      } catch (error) {
        if (signal.aborted || index === apiKeys.length - 1) throw error;
        lastError = new Error(redactProviderError(errorMessage(error)));
        console.warn(
          `campus-ai-assistant: DeepSeek action planner key ${
            index + 1
          }/${apiKeys.length} failed before response; trying fallback`,
          lastError.message,
        );
        continue;
      }

      const responseText = await response.text();
      if (!response.ok) {
        const error = new Error(
          `DeepSeek action planner key ${
            index + 1
          }/${apiKeys.length} returned ${response.status}: ${
            redactProviderError(responseText)
          }`,
        );
        if (
          index < apiKeys.length - 1 &&
          shouldRetryDeepSeekStatus(response.status)
        ) {
          lastError = error;
          console.warn(
            "campus-ai-assistant: DeepSeek action planner key failed; trying fallback",
            error.message,
          );
          continue;
        }
        throw error;
      }

      const planned = parseActionPlannerProviderResponse(responseText);
      return {
        actions: planned.actions.length > 0
          ? planned.actions
          : fallbackActionDrafts(body, message, answer),
        usage: planned.usage,
      };
    }

    throw lastError ?? new Error("DeepSeek action planner failed.");
  } catch (error) {
    if (!signal.aborted) {
      console.warn(
        "campus-ai-assistant: action planning failed",
        redactProviderError(errorMessage(error)),
      );
    }
    return { actions: fallbackActionDrafts(body, message, answer), usage: {} };
  }
}

export function fallbackActionDrafts(
  _body: CampusAIRequest,
  message: string,
  answer = "",
): CampusAIActionDraft[] {
  const text = `${message}\n${answer}`.toLowerCase();
  const hasCreateIntent = ["新建", "添加", "创建", "设置", "安排"].some((
    keyword,
  ) => text.includes(keyword));
  const hasScheduleIntent = ["日程", "提醒", "事项", "待办", "安排"].some((
    keyword,
  ) => text.includes(keyword));
  if (!hasCreateIntent || !hasScheduleIntent) return [];

  const route = text.includes("倒计时") || text.includes("重要日期") ||
      text.includes("纪念日")
    ? "customCountdowns"
    : text.includes("推送") || text.includes("报告")
    ? "scheduleReports"
    : "examSchedule";
  const title = route === "customCountdowns"
    ? "打开自定义倒计时"
    : route === "scheduleReports"
    ? "打开日程推送"
    : "打开考试与日程";
  return [{
    kind: "openAcademicRoute",
    title,
    detail: `前往${title.replace(/^打开/, "")}继续创建或管理日程。`,
    payload: { route },
  }];
}

async function readDeepSeekStream(
  response: Response,
  callbacks: {
    onDelta: (delta: string) => void;
    onReasoningDelta: (delta: string) => void;
    onUsage: (usage: DeepSeekUsage) => void;
  },
): Promise<{ answer: string; reasoning: string; finishReason: string | null }> {
  const body = response.body;
  if (!body) {
    throw new Error("DeepSeek response did not include a stream body.");
  }
  const reader = body.getReader();
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
          capabilities: body.capabilities ?? {},
          local_retrieval: localRetrievalFromBody(body),
          recent_messages: recentMessages,
        }),
      },
    ],
    stream: true,
    stream_options: { include_usage: true },
    thinking: { type: "enabled" },
    temperature: 0.2,
    user: userCacheKey(body.app_transaction_id),
  };
}

export function actionPlannerPayload(
  body: CampusAIRequest,
  message: string,
  answer: string,
) {
  return {
    model: defaultModel,
    messages: [
      {
        role: "system",
        content: actionPlannerSystemPrompt(),
      },
      {
        role: "user",
        content: safeJSONStringify({
          message,
          answer,
          context: body.context ?? {},
          context_settings: body.context_settings ?? body.contextSettings ?? {},
          capabilities: body.capabilities ?? {},
          local_retrieval: localRetrievalFromBody(body),
          supported_actions: [
            {
              kind: "openAcademicRoute",
              required_payload_fields: ["route"],
              allowed_values: {
                route: academicRouteIDs(),
              },
            },
            {
              kind: "createCountdown",
              required_payload_fields: ["countdownTitle", "targetDate"],
              allowed_values: { targetDate: ["yyyy-MM-dd"] },
            },
            {
              kind: "createTimetableReminder",
              required_payload_fields: ["week", "dayOfWeek", "period", "title"],
              allowed_values: {
                week: ["1...30"],
                dayOfWeek: ["1...7"],
                period: ["1...12"],
              },
            },
          ],
          safety_boundary: [
            "所有动作都只生成待确认草稿，不会自动执行。",
            "不要生成修改成绩或课表原始数据、医疗决策、社区发帖评论、远程抓取、后台登录等动作。",
            "编辑或删除必须有 local_retrieval.sourceID 等明确目标 ID；缺少目标 ID 时改用 openAcademicRoute 或返回空 actions。",
            "删除类动作需要二次确认；当前 schema 未提供删除 kind 时不要输出删除动作。",
            "缺少 createTimetableReminder 必要字段时不要编造；如果用户是在新建或管理日程/提醒，改用 openAcademicRoute 打开对应页面。",
          ],
        }),
      },
    ],
    stream: false,
    temperature: 0,
    max_tokens: 700,
    user: userCacheKey(body.app_transaction_id),
  };
}

export function systemPrompt(userSystemPrompt?: string | null) {
  const customPrompt = normalizeText(userSystemPrompt)
    ?.slice(0, maxUserSystemPromptLength);
  return [
    "你是 MyLeafy 的校园学习与生活助手，当前是测试功能。",
    "回答要直接、具体、可执行；能给结论就先给结论，不要反复解释内部数据来源。",
    "可以结合已提供的课程、考试、学习、提醒和个人事项上下文，也可以补充合理的一般建议；不要把不确定内容说成事实。",
    "如果输入包含 local_retrieval，优先使用其中最相关的结果；不要把它作为工程细节反复解释给用户。",
    "缺少关键信息时，用一句话说明缺什么，并给出用户下一步能做的选择。",
    "不要声称读取了未提供的数据，不要声称读取了用户上传文件正文、图片像素、OCR、PDF、Word、PPT、表格或本地文件路径。",
    "不要推断私信、身份资料、未提供的远端内容或后台登录后的内容。",
    "医疗台账只能做整理、提醒、流程梳理和材料核对，不提供诊断、治疗、用药或医疗决策建议。",
    "回复必须是中文 Markdown。优先使用短标题、列表、加粗和清晰分段；不要在正文输出 JSON 或动作草稿，动作会由单独规划器生成。",
    customPrompt ? `用户自定义偏好：\n${customPrompt}` : "",
  ].filter(Boolean).join("\n");
}

export function actionPlannerSystemPrompt() {
  return [
    "你是 MyLeafy 的动作规划器，只能输出 JSON，不能输出 Markdown、解释、代码块或多余文本。",
    "根据用户问题、AI 已生成回答和本机上下文，最多生成 3 个需要用户确认后执行的动作。",
    "可以使用 local_retrieval 中的 routeHint 和 sourceID 判断动作目标；缺少明确目标 ID 时不要编造编辑或删除动作。",
    '只有用户明确想打开页面、设置倒计时、设置课表提醒，或回答中明显需要这一步时才生成动作；否则返回 {"actions":[]}。',
    "支持 kind：openAcademicRoute、createCountdown、createTimetableReminder。",
    "openAcademicRoute.payload.route 必须来自 supported_actions 中的 allowed_values.route。",
    "用户想新建、添加或管理日程/提醒，但缺少创建课表提醒所需的周次、星期、节次时，生成 openAcademicRoute：一般日程用 examSchedule，倒计时或重要日期用 customCountdowns，推送或报告用 scheduleReports。",
    "createCountdown.payload 必须包含 countdownTitle 和 targetDate，targetDate 使用 yyyy-MM-dd。",
    "createTimetableReminder.payload 必须包含 week、dayOfWeek、period、title；dayOfWeek 为 1 到 7，minutesBefore 必须大于等于 0。",
    "不要生成删除、修改成绩或课表原始数据、医疗决策、社区发帖评论、远程抓取、后台登录等动作。",
    '输出格式必须是 {"actions":[{"kind":"...","title":"...","detail":"...","payload":{...}}]}。',
  ].join("\n");
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

export function parseActionPlannerProviderResponse(
  responseText: string,
): { actions: CampusAIActionDraft[]; usage: DeepSeekUsage } {
  const payload = JSON.parse(responseText) as Record<string, unknown>;
  const usagePayload = objectValue(payload.usage);
  const usage = usagePayload ? deepSeekUsage(usagePayload) : {};
  const choices = Array.isArray(payload.choices) ? payload.choices : [];
  const content = choices
    .map((choice) => objectValue(choice))
    .map((choice) => objectValue(choice?.message))
    .map((message) => stringValue(message?.content))
    .find((value) => !!value) ?? "";

  return {
    actions: parseActionPlannerActions(content),
    usage,
  };
}

export function parseActionPlannerActions(content: string) {
  for (const candidate of actionPlannerJSONCandidates(content)) {
    try {
      const parsed = JSON.parse(candidate);
      const rawActions = Array.isArray(parsed)
        ? parsed
        : Array.isArray(parsed?.actions)
        ? parsed.actions
        : [];
      const actions = rawActions
        .map((item: unknown) => validateActionDraft(item))
        .filter((
          item: CampusAIActionDraft | null,
        ): item is CampusAIActionDraft => item !== null);
      if (actions.length > 0 || rawActions.length === 0) {
        return actions.slice(0, 3);
      }
    } catch {
      // Try the next candidate.
    }
  }
  return [];
}

function actionPlannerJSONCandidates(content: string) {
  let trimmed = content.trim();
  if (trimmed.startsWith("```")) {
    const lines = trimmed.replaceAll("\r\n", "\n").split("\n");
    if (lines.length > 1) {
      if (lines.at(-1)?.trim() === "```") lines.pop();
      lines.shift();
      trimmed = lines.join("\n").trim();
    }
  }

  const candidates = [trimmed];
  const objectStart = trimmed.indexOf("{");
  const objectEnd = trimmed.lastIndexOf("}");
  if (objectStart >= 0 && objectEnd >= objectStart) {
    candidates.push(trimmed.slice(objectStart, objectEnd + 1));
  }
  const arrayStart = trimmed.indexOf("[");
  const arrayEnd = trimmed.lastIndexOf("]");
  if (arrayStart >= 0 && arrayEnd >= arrayStart) {
    candidates.push(trimmed.slice(arrayStart, arrayEnd + 1));
  }
  return Array.from(new Set(candidates.filter(Boolean)));
}

function validateActionDraft(value: unknown): CampusAIActionDraft | null {
  const record = objectValue(value);
  if (!record) return null;
  const rawKind = stringValue(record.kind);
  const kind = normalizeActionKind(rawKind);
  if (!kind) return null;

  const payloadRecord = objectValue(record.payload) ?? {};
  const payload = normalizeActionPayload(payloadRecord);
  const draft: CampusAIActionDraft = {
    id: stringValue(record.id) ?? crypto.randomUUID(),
    kind,
    title: stringValue(record.title) ?? "",
    detail: stringValue(record.detail) ?? "",
    payload,
  };

  switch (kind) {
    case "openAcademicRoute":
      return validateOpenAcademicRoute(draft);
    case "createCountdown":
      return validateCreateCountdown(draft);
    case "createTimetableReminder":
      return validateCreateTimetableReminder(draft);
  }
}

function normalizeActionKind(value: string | null): CampusAIActionKind | null {
  switch (value) {
    case "openAcademicRoute":
    case "open_academic_route":
      return "openAcademicRoute";
    case "createCountdown":
    case "create_countdown":
      return "createCountdown";
    case "createTimetableReminder":
    case "create_timetable_reminder":
      return "createTimetableReminder";
    default:
      return null;
  }
}

function normalizeActionPayload(
  payload: Record<string, unknown>,
): CampusAIActionPayload {
  return {
    route: stringValue(payload.route) ?? undefined,
    countdownTitle: stringValue(payload.countdownTitle) ??
      stringValue(payload.countdown_title) ?? undefined,
    targetDate: stringValue(payload.targetDate) ??
      stringValue(payload.target_date) ?? undefined,
    week: integerValue(payload.week) ?? undefined,
    dayOfWeek: integerValue(payload.dayOfWeek) ??
      integerValue(payload.day_of_week) ?? undefined,
    period: integerValue(payload.period) ?? undefined,
    endPeriod: integerValue(payload.endPeriod) ??
      integerValue(payload.end_period) ?? undefined,
    title: stringValue(payload.title) ?? undefined,
    location: stringValue(payload.location) ?? undefined,
    note: stringValue(payload.note) ?? undefined,
    minutesBefore: integerValue(payload.minutesBefore) ??
      integerValue(payload.minutes_before) ?? undefined,
  };
}

function validateOpenAcademicRoute(
  draft: CampusAIActionDraft,
): CampusAIActionDraft | null {
  const route = draft.payload?.route;
  const allowedRoutes = new Set(academicRouteIDs());
  if (!route || !allowedRoutes.has(route)) return null;
  return {
    ...draft,
    title: normalizeText(draft.title) ?? `打开${academicRouteTitle(route)}`,
    payload: { route },
  };
}

function validateCreateCountdown(
  draft: CampusAIActionDraft,
): CampusAIActionDraft | null {
  const title = normalizeText(draft.payload?.countdownTitle) ??
    normalizeText(draft.payload?.title);
  const targetDate = normalizeText(draft.payload?.targetDate);
  if (!title || !targetDate || !/^\d{4}-\d{2}-\d{2}$/.test(targetDate)) {
    return null;
  }
  return {
    ...draft,
    title: normalizeText(draft.title) ?? "创建倒计时",
    payload: {
      countdownTitle: title,
      targetDate,
    },
  };
}

function validateCreateTimetableReminder(
  draft: CampusAIActionDraft,
): CampusAIActionDraft | null {
  const week = draft.payload?.week;
  const dayOfWeek = draft.payload?.dayOfWeek;
  const period = draft.payload?.period;
  const title = normalizeText(draft.payload?.title);
  if (
    !week || week < 1 || week > 30 ||
    !dayOfWeek || dayOfWeek < 1 || dayOfWeek > 7 ||
    !period || period < 1 || period > 12 ||
    !title
  ) {
    return null;
  }
  const endPeriod =
    draft.payload?.endPeriod && draft.payload.endPeriod >= period &&
      draft.payload.endPeriod <= 12
      ? draft.payload.endPeriod
      : undefined;
  return {
    ...draft,
    title: normalizeText(draft.title) ?? "创建课表提醒",
    payload: {
      week,
      dayOfWeek,
      period,
      endPeriod,
      title,
      location: normalizeText(draft.payload?.location) ?? undefined,
      note: normalizeText(draft.payload?.note) ?? undefined,
      minutesBefore: Math.max(0, draft.payload?.minutesBefore ?? 0),
    },
  };
}

function academicRouteIDs() {
  return [
    "grades",
    "gradeAnalytics",
    "examSchedule",
    "scheduleReports",
    "customCountdowns",
    "timetableProcessing",
    "honorRecords",
    "comprehensiveQuality",
    "teachingPlan",
    "trainingProgram",
    "emptyClassroom",
    "campusHeatmap",
    "studyTimeRecords",
    "sunshineRun",
    "fitnessTestRecords",
    "sportsVenues",
    "schoolCalendar",
    "countdowns",
    "medicalPolicy",
    "medicalScenarioAssistant",
    "medicalLedger",
  ];
}

function academicRouteTitle(route: string) {
  switch (route) {
    case "grades":
      return "成绩查询";
    case "gradeAnalytics":
      return "成绩分析";
    case "examSchedule":
      return "考试与日程";
    case "scheduleReports":
      return "日程推送";
    case "customCountdowns":
      return "自定义倒计时";
    case "timetableProcessing":
      return "课表导入";
    case "honorRecords":
      return "荣誉记录";
    case "comprehensiveQuality":
      return "综测记录";
    case "teachingPlan":
      return "教学计划";
    case "trainingProgram":
      return "培养方案";
    case "emptyClassroom":
      return "空教室";
    case "campusHeatmap":
      return "校园热力";
    case "studyTimeRecords":
      return "学习记录";
    case "sunshineRun":
      return "阳光长跑";
    case "fitnessTestRecords":
      return "体测记录";
    case "sportsVenues":
      return "体育场馆";
    case "schoolCalendar":
      return "校历";
    case "countdowns":
      return "倒计时";
    case "medicalPolicy":
      return "医保政策";
    case "medicalScenarioAssistant":
      return "医疗流程助手";
    case "medicalLedger":
      return "医疗台账";
    default:
      return "校园页面";
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

export function deepSeekAPIKeys() {
  const keys: string[] = [];
  appendDeepSeekAPIKeys(keys, Deno.env.get("DEEPSEEK_API_KEY"));
  appendDeepSeekAPIKeys(keys, Deno.env.get("DEEPSEEK_API_KEYS"));
  for (let index = 1; index <= 10; index += 1) {
    appendDeepSeekAPIKeys(keys, Deno.env.get(`DEEPSEEK_API_KEY_${index}`));
  }
  return Array.from(new Set(keys));
}

function appendDeepSeekAPIKeys(keys: string[], value: string | undefined) {
  for (const key of parseDeepSeekAPIKeys(value)) {
    if (key.length > 0) keys.push(key);
  }
}

export function parseDeepSeekAPIKeys(value: string | undefined) {
  const raw = value?.trim();
  if (!raw) return [];

  if (raw.startsWith("[")) {
    try {
      const parsed = JSON.parse(raw);
      if (Array.isArray(parsed)) {
        return parsed
          .map((item) => typeof item === "string" ? item.trim() : "")
          .filter(Boolean);
      }
    } catch {
      // Fall back to delimiter parsing below.
    }
  }

  return raw
    .split(/[\n,;]+/)
    .map((item) => item.trim())
    .filter(Boolean);
}

function shouldRetryDeepSeekStatus(status: number) {
  return status === 401 ||
    status === 403 ||
    status === 408 ||
    status === 409 ||
    status === 425 ||
    status === 429 ||
    status >= 500;
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

function localRetrievalFromBody(body: CampusAIRequest) {
  return body.local_retrieval ?? body.localRetrieval ?? null;
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

function deduplicateCitations(citations: AgentCitation[]) {
  const seen = new Set<string>();
  const result: AgentCitation[] = [];
  for (const citation of citations) {
    const key = citation.url.trim();
    if (!key || seen.has(key)) continue;
    seen.add(key);
    result.push(citation);
  }
  return result;
}

function deduplicateDeliverables(deliverables: CampusAIDeliverable[]) {
  const seen = new Set<string>();
  const result: CampusAIDeliverable[] = [];
  for (const deliverable of deliverables) {
    const key = deliverable.id || deliverable.query;
    if (!key || seen.has(key)) continue;
    seen.add(key);
    result.push(deliverable);
  }
  return result;
}

function deduplicateTrace(steps: AgentTraceStep[]) {
  const seen = new Set<string>();
  const result: AgentTraceStep[] = [];
  for (const step of steps) {
    const key = step.id;
    if (!key || seen.has(key)) continue;
    seen.add(key);
    result.push(step);
  }
  return result;
}

function boundedInteger(
  value: unknown,
  min: number,
  max: number,
  fallback: number,
) {
  const integer = integerValue(value);
  if (integer === null) return fallback;
  return Math.min(max, Math.max(min, integer));
}

function isHTTPURL(value: string) {
  try {
    const url = new URL(value);
    return url.protocol === "http:" || url.protocol === "https:";
  } catch {
    return false;
  }
}

export function isSafePublicHTTPURL(value: string) {
  try {
    const url = new URL(value);
    if (url.protocol !== "http:" && url.protocol !== "https:") return false;
    const hostname = url.hostname.toLowerCase();
    if (
      hostname === "localhost" ||
      hostname.endsWith(".localhost") ||
      hostname === "0.0.0.0" ||
      hostname === "::" ||
      hostname === "::1"
    ) {
      return false;
    }
    if (isPrivateIPv4(hostname) || isPrivateIPv6(hostname)) return false;
    return true;
  } catch {
    return false;
  }
}

function isPrivateIPv4(hostname: string) {
  if (!/^\d{1,3}(\.\d{1,3}){3}$/.test(hostname)) return false;
  const parts = hostname.split(".").map((part) => Number(part));
  if (parts.some((part) => !Number.isInteger(part) || part < 0 || part > 255)) {
    return true;
  }
  const [a, b] = parts;
  return a === 10 ||
    a === 127 ||
    a === 0 ||
    (a === 172 && b >= 16 && b <= 31) ||
    (a === 192 && b === 168) ||
    (a === 169 && b === 254);
}

function isPrivateIPv6(hostname: string) {
  const normalized = hostname.replace(/^\[|\]$/g, "").toLowerCase();
  return normalized === "::1" ||
    normalized.startsWith("fc") ||
    normalized.startsWith("fd") ||
    normalized.startsWith("fe80:");
}

export function officialDocumentTrustScore(
  citation: AgentCitation,
  context: unknown = {},
) {
  const host = safeHost(citation.url);
  if (!host) return 0;
  const campusID = campusIDFromContext(context);
  const campusName = campusNameFromContext(context);
  let score = 0;

  if (campusID === "bjfu") {
    if (bjfuOfficialHosts.has(host)) {
      score = 100;
    } else if (host.endsWith(".bjfu.edu.cn") || host === "bjfu.edu.cn") {
      score = 88;
    }
  }

  if (score === 0) {
    if (host.endsWith(".edu.cn") || host.endsWith(".edu")) score = 60;
    if (host.includes("edu")) score = Math.max(score, 45);
  }

  const haystack = [
    citation.title,
    citation.siteName,
    citation.summary,
    citation.snippet,
    citation.url,
  ].filter(Boolean).join(" ").toLowerCase();
  if (campusName && haystack.includes(campusName.toLowerCase())) {
    score += 8;
  }
  if (
    /(官方|教务处|研究生院|学院|通知|政策|办法|规定|附件|下载)/.test(haystack)
  ) {
    score += 6;
  }
  return Math.min(100, score);
}

const bjfuOfficialHosts = new Set([
  "jwc.bjfu.edu.cn",
  "graduate.bjfu.edu.cn",
  "www.bjfu.edu.cn",
  "news.bjfu.edu.cn",
  "zsb.bjfu.edu.cn",
  "it.bjfu.edu.cn",
  "nic.bjfu.edu.cn",
  "lib.bjfu.edu.cn",
  "xyy.bjfu.edu.cn",
  "sports.bjfu.edu.cn",
  "blzf.bjfu.edu.cn",
  "zhbzb.bjfu.edu.cn",
]);

function safeHost(value: string) {
  try {
    return new URL(value).hostname.toLowerCase();
  } catch {
    return "";
  }
}

function absoluteURL(href: string, baseURL: string) {
  try {
    const url = new URL(href, baseURL).toString();
    return isSafePublicHTTPURL(url) ? url : null;
  } catch {
    return null;
  }
}

function attachmentFileType(url: string) {
  try {
    const pathname = new URL(url).pathname.toLowerCase();
    const match = pathname.match(/\.([a-z0-9]+)$/);
    const ext = match?.[1];
    if (!ext) return null;
    const allowed = new Set([
      "pdf",
      "doc",
      "docx",
      "xls",
      "xlsx",
      "ppt",
      "pptx",
      "txt",
    ]);
    return allowed.has(ext) ? ext.toUpperCase() : null;
  } catch {
    return null;
  }
}

function filenameFromURL(url: string) {
  try {
    const pathname = new URL(url).pathname;
    const last = decodeURIComponent(
      pathname.split("/").filter(Boolean).at(-1) ?? "",
    );
    return normalizeText(last);
  } catch {
    return null;
  }
}

function estimatedCostUSD(usage: DeepSeekUsage) {
  const cacheMissInput = usage.prompt_cache_miss_tokens ??
    usage.prompt_tokens ??
    0;
  const output = usage.completion_tokens ?? 0;
  return (cacheMissInput * inputCacheMissCostPerMillion +
    output * outputCostPerMillion) / 1_000_000;
}

function mergeUsage(lhs: DeepSeekUsage, rhs: DeepSeekUsage): DeepSeekUsage {
  return {
    prompt_tokens: (lhs.prompt_tokens ?? 0) + (rhs.prompt_tokens ?? 0),
    prompt_cache_hit_tokens: (lhs.prompt_cache_hit_tokens ?? 0) +
      (rhs.prompt_cache_hit_tokens ?? 0),
    prompt_cache_miss_tokens: (lhs.prompt_cache_miss_tokens ?? 0) +
      (rhs.prompt_cache_miss_tokens ?? 0),
    completion_tokens: (lhs.completion_tokens ?? 0) +
      (rhs.completion_tokens ?? 0),
    reasoning_tokens: (lhs.reasoning_tokens ?? 0) +
      (rhs.reasoning_tokens ?? 0),
    total_tokens: (lhs.total_tokens ?? 0) + (rhs.total_tokens ?? 0),
  };
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

function campusNameFromContext(context: unknown): string {
  if (context && typeof context === "object") {
    const campusName = normalizeText(
      (context as Record<string, unknown>).campusName,
    );
    if (campusName) return campusName;
  }
  return "";
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
