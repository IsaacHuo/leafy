import {
  campusAIResponseFormat,
  deepSeekPayload,
  drainDeepSeekSSEBuffer,
  handler,
  processDeepSeekSSEBlock,
  redactProviderError,
  systemPrompt,
} from "./index.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) {
    throw new Error(message);
  }
}

async function responseJSON(
  response: Response,
): Promise<Record<string, unknown>> {
  return await response.json() as Record<string, unknown>;
}

Deno.test("campus-ai-assistant rejects non-POST requests", async () => {
  const response = await handler(
    new Request("http://local.test/campus-ai-assistant", { method: "GET" }),
  );

  assert(response.status === 405, `expected 405, got ${response.status}`);
});

Deno.test("campus-ai-assistant rejects requests without a Supabase Auth JWT", async () => {
  const response = await handler(
    new Request("http://local.test/campus-ai-assistant", {
      method: "POST",
      body: JSON.stringify({ message: "明天上什么课？" }),
    }),
  );
  const payload = await responseJSON(response);

  assert(response.status === 401, `expected 401, got ${response.status}`);
  assert(
    payload.error === "缺少登录凭证。",
    "expected missing credential error",
  );
});

Deno.test("campus-ai-assistant declares DeepSeek V4 Flash streaming Markdown payload", () => {
  const payload = deepSeekPayload({
    app_transaction_id: "app-tx-1",
    user_system_prompt: "请用列表回答",
    context: { campusID: "bjfu", timetable: { allCourses: [] } },
    context_settings: { includesTimetable: true },
    recent_messages: [{ role: "assistant", text: "你好" }],
  }, "明天上什么课？") as Record<string, unknown>;
  const messages = payload.messages as Array<Record<string, unknown>>;

  assert(
    campusAIResponseFormat() === null,
    "JSON output mode should be disabled",
  );
  assert(payload.model === "deepseek-v4-flash", "expected DeepSeek V4 Flash");
  assert(payload.stream === true, "expected stream true");
  assert(
    JSON.stringify(payload.stream_options) ===
      JSON.stringify({ include_usage: true }),
    "expected include_usage stream option",
  );
  assert(
    JSON.stringify(payload.thinking) === JSON.stringify({ type: "enabled" }),
    "expected thinking enabled",
  );
  assert(
    String(messages[0].content).includes("中文 Markdown"),
    "expected Markdown system prompt",
  );
  assert(
    String(messages[0].content).includes("请用列表回答"),
    "expected custom prompt to be appended",
  );
  assert(
    typeof payload.user === "string" &&
      !String(payload.user).includes("app-tx-1"),
    "provider user cache key should not expose raw app transaction ID",
  );
});

Deno.test("campus-ai-assistant prompt keeps file bodies out of scope and allows ledger organization only", () => {
  const prompt = systemPrompt();

  assert(prompt.includes("本机缓存"), "expected local cached scope");
  assert(
    prompt.includes("中文 Markdown"),
    "expected explicit Markdown instruction",
  );
  assert(
    prompt.includes("PDF") && prompt.includes("本地文件路径"),
    "expected uploaded file body boundary",
  );
  assert(
    prompt.includes("不提供诊断"),
    "medical diagnosis advice should remain out of scope",
  );
});

Deno.test("campus-ai-assistant normalizes DeepSeek SSE deltas, reasoning, finish reason, and usage", () => {
  const deltas: string[] = [];
  const reasoning: string[] = [];
  const finishReasons: Array<string | null> = [];
  const usages: Array<Record<string, unknown>> = [];
  const result = drainDeepSeekSSEBuffer(
    [
      ": KEEPALIVE",
      "",
      'data: {"choices":[{"delta":{"reasoning_content":"先看课表"},"finish_reason":null}]}',
      "",
      'data: {"choices":[{"delta":{"content":"# 标题"},"finish_reason":null}]}',
      "",
      'data: {"choices":[{"delta":{"content":"\\n- 内容"},"finish_reason":"stop"}]}',
      "",
      'data: {"choices":[],"usage":{"prompt_tokens":12,"prompt_cache_hit_tokens":3,"prompt_cache_miss_tokens":9,"completion_tokens":4,"reasoning_tokens":2,"total_tokens":16}}',
      "",
      "data: [DONE]",
      "",
    ].join("\n"),
    {
      onDelta: (delta) => deltas.push(delta),
      onReasoningDelta: (delta) => reasoning.push(delta),
      onFinishReason: (finishReason) => finishReasons.push(finishReason),
      onUsage: (usage) => usages.push(usage as Record<string, unknown>),
    },
    true,
  );

  assert(result.remainder === "", "expected empty remainder");
  assert(deltas.join("") === "# 标题\n- 内容", "expected Markdown deltas");
  assert(reasoning.join("") === "先看课表", "expected reasoning delta");
  assert(finishReasons.includes("stop"), "expected finish reason");
  assert(usages.length === 1, "expected usage chunk");
  assert(
    usages[0].prompt_cache_miss_tokens === 9,
    "expected cache miss tokens",
  );
});

Deno.test("campus-ai-assistant surfaces DeepSeek stream errors", () => {
  let threw = false;
  try {
    processDeepSeekSSEBlock(
      'data: {"error":{"message":"provider failed with sk-secret_key"}}',
      {
        onDelta: () => {},
        onReasoningDelta: () => {},
        onFinishReason: () => {},
        onUsage: () => {},
      },
    );
  } catch (error) {
    threw = true;
    assert(
      error instanceof Error && error.message.includes("sk-redacted"),
      "expected redacted stream error",
    );
  }
  assert(threw, "expected stream error to throw");
});

Deno.test("campus-ai-assistant redacts provider secrets from errors", () => {
  const message = redactProviderError(
    "provider failed with sk-test_secret_123 and a long body",
  );

  assert(message.includes("sk-redacted"), "expected provider secret redaction");
  assert(
    !message.includes("sk-test_secret_123"),
    "raw provider secret must not leak",
  );
});
