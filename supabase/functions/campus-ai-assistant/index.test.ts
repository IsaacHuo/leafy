import {
  actionPlannerPayload,
  actionPlannerSystemPrompt,
  agentSynthesisPayload,
  agentToolPlannerPayload,
  campusAIResponseFormat,
  deepSeekAPIKeys,
  deepSeekPayload,
  drainDeepSeekSSEBuffer,
  handler,
  normalizeAgentToolCalls,
  parseActionPlannerActions,
  parseActionPlannerProviderResponse,
  parseAgentToolCallsFromProviderResponse,
  parseBochaSearchResponse,
  parseDeepSeekAPIKeys,
  processDeepSeekSSEBlock,
  redactProviderError,
  shouldRunManagedAgent,
  systemPrompt,
  webSearch,
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

Deno.test("campus-ai-assistant builds non-stream JSON-only action planner payload", () => {
  const payload = actionPlannerPayload(
    {
      app_transaction_id: "app-tx-1",
      context: { campusID: "bjfu", currentWeek: 2 },
      context_settings: { includesTimetable: true },
    },
    "帮我打开培养方案",
    "可以查看培养方案。",
  ) as Record<string, unknown>;
  const messages = payload.messages as Array<Record<string, unknown>>;

  assert(payload.model === "deepseek-v4-flash", "expected DeepSeek V4 Flash");
  assert(payload.stream === false, "expected non-stream planner request");
  assert(payload.temperature === 0, "expected deterministic planner");
  assert(
    String(messages[0].content).includes("只能输出 JSON"),
    "expected JSON-only planner prompt",
  );
  assert(
    String(messages[1].content).includes("supported_actions"),
    "expected supported action schema",
  );
});

Deno.test("campus-ai-assistant enables managed agent only for search or multi-step requests", () => {
  assert(
    shouldRunManagedAgent(
      { web_search_enabled: true },
      "帮我搜索一下北林最近通知",
    ),
    "expected search request to use agent mode",
  );
  assert(
    !shouldRunManagedAgent(
      { web_search_enabled: false },
      "帮我搜索一下北林最近通知",
    ),
    "disabled web search should force fast path",
  );
  assert(
    !shouldRunManagedAgent({ agent_mode: "off" }, "最近有什么通知？"),
    "agent_mode off should force fast path",
  );
});

Deno.test("campus-ai-assistant builds DeepSeek tool planner payload", () => {
  const payload = agentToolPlannerPayload(
    {
      app_transaction_id: "app-tx-1",
      context: { campusID: "bjfu", currentWeek: 2 },
      context_settings: { includesTimetable: true },
      recent_messages: [{ role: "user", text: "你好" }],
    },
    "帮我查一下北林最近通知并结合课表安排",
  ) as Record<string, unknown>;
  const tools = payload.tools as Array<Record<string, unknown>>;

  assert(payload.model === "deepseek-v4-flash", "expected DeepSeek V4 Flash");
  assert(payload.stream === false, "expected non-stream planner");
  assert(payload.tool_choice === "auto", "expected automatic tool choice");
  assert(tools.length === 3, "expected three agent tools");
  assert(
    JSON.stringify(tools).includes("web_search") &&
      JSON.stringify(tools).includes("delegate_subtask") &&
      JSON.stringify(tools).includes("action_plan"),
    "expected tool definitions",
  );
});

Deno.test("campus-ai-assistant parses and limits agent tool calls", () => {
  const parsed = parseAgentToolCallsFromProviderResponse(JSON.stringify({
    choices: [
      {
        message: {
          tool_calls: [
            {
              function: {
                name: "web_search",
                arguments: JSON.stringify({ query: "北林通知", count: 20 }),
              },
            },
            {
              function: {
                name: "delegate_subtask",
                arguments: JSON.stringify({
                  role: "campusAnalyst",
                  task: "结合课表给出安排",
                }),
              },
            },
            {
              function: {
                name: "delegate_subtask",
                arguments: JSON.stringify({ role: "invalid", task: "bad" }),
              },
            },
          ],
        },
      },
    ],
  }));
  const normalized = normalizeAgentToolCalls(parsed, {
    allowWebSearch: true,
    message: "帮我查一下北林通知",
  });

  assert(normalized.length === 2, "expected invalid delegate to be filtered");
  assert(normalized[0].name === "web_search", "expected web search first");
  assert(normalized[0].arguments.count === 8, "expected count to clamp");
  assert(
    normalized[1].arguments.role === "campusAnalyst",
    "expected delegate role",
  );

  const disabled = normalizeAgentToolCalls(parsed, {
    allowWebSearch: false,
    message: "帮我查一下北林通知",
  });
  assert(
    disabled.every((call) => call.name !== "web_search"),
    "disabled web search should filter search calls",
  );
});

Deno.test("campus-ai-assistant parses Bocha search citations", () => {
  const citations = parseBochaSearchResponse(
    JSON.stringify({
      webPages: {
        value: [
          {
            name: "北京林业大学通知",
            url: "https://www.bjfu.edu.cn/notice/1",
            siteName: "北京林业大学",
            snippet: "通知摘要",
            summary: "通知总结",
            datePublished: "2026-07-02T00:00:00+08:00",
          },
          {
            name: "重复",
            url: "https://www.bjfu.edu.cn/notice/1",
          },
          {
            name: "坏链接",
            url: "javascript:alert(1)",
          },
        ],
      },
    }),
    "北林通知",
  );

  assert(citations.length === 1, "expected duplicate and unsafe URLs filtered");
  assert(citations[0].title === "北京林业大学通知", "expected title");
  assert(citations[0].siteName === "北京林业大学", "expected site name");
  assert(citations[0].publishedAt?.includes("2026"), "expected publish date");
});

Deno.test("campus-ai-assistant handles missing Bocha API key before network", async () => {
  const previous = Deno.env.get("BOCHA_API_KEY");
  try {
    Deno.env.delete("BOCHA_API_KEY");
    let threw = false;
    try {
      await webSearch("北林通知", "oneMonth", 3, new AbortController().signal);
    } catch (error) {
      threw = true;
      assert(
        error instanceof Error && error.message.includes("BOCHA_API_KEY"),
        "expected missing Bocha key error",
      );
    }
    assert(threw, "expected webSearch to reject without key");
  } finally {
    if (previous === undefined) {
      Deno.env.delete("BOCHA_API_KEY");
    } else {
      Deno.env.set("BOCHA_API_KEY", previous);
    }
  }
});

Deno.test("campus-ai-assistant synthesis payload carries citations and search results", () => {
  const payload = agentSynthesisPayload(
    { app_transaction_id: "app-tx-1", context: { campusID: "bjfu" } },
    "总结通知",
    [{
      query: "北林通知",
      citations: [{
        id: "web-1",
        title: "通知",
        url: "https://www.bjfu.edu.cn/notice",
      }],
    }],
    [{ role: "campusAnalyst", task: "安排建议", result: "周三处理。" }],
    [{
      id: "web-1",
      title: "通知",
      url: "https://www.bjfu.edu.cn/notice",
    }],
  ) as Record<string, unknown>;
  const messages = payload.messages as Array<Record<string, unknown>>;

  assert(payload.stream === true, "expected streamed synthesis");
  assert(
    String(messages[0].content).includes("Markdown 链接标注来源"),
    "expected citation instruction",
  );
  assert(
    String(messages[1].content).includes("web_search_results") &&
      String(messages[1].content).includes("subtask_results"),
    "expected agent inputs",
  );
});

Deno.test("campus-ai-assistant parses and validates action planner output", () => {
  const actions = parseActionPlannerActions(`
  \`\`\`json
  {
    "actions": [
      {"kind":"open_academic_route","title":"","payload":{"route":"trainingProgram"}},
      {"kind":"create_countdown","title":"创建倒计时","payload":{"countdown_title":"期末考试","target_date":"2026-07-01"}},
      {"kind":"open_academic_route","title":"打开医疗台账","payload":{"route":"medicalLedger"}}
    ]
  }
  \`\`\`
  `);

  assert(actions.length === 2, "expected invalid route to be filtered");
  assert(actions[0].kind === "openAcademicRoute", "expected normalized kind");
  assert(
    actions[0].payload?.route === "trainingProgram",
    "expected trainingProgram route",
  );
  assert(
    actions[1].payload?.countdownTitle === "期末考试",
    "expected snake_case payload to normalize",
  );
});

Deno.test("campus-ai-assistant parses planner usage from provider response", () => {
  const parsed = parseActionPlannerProviderResponse(JSON.stringify({
    choices: [
      {
        message: {
          content:
            '{"actions":[{"kind":"create_timetable_reminder","title":"","payload":{"week":2,"day_of_week":3,"period":5,"title":"提交实验报告","minutes_before":-5}}]}',
        },
      },
    ],
    usage: {
      prompt_tokens: 10,
      prompt_cache_miss_tokens: 7,
      completion_tokens: 4,
      total_tokens: 14,
    },
  }));

  assert(parsed.actions.length === 1, "expected one valid reminder action");
  assert(
    parsed.actions[0].payload?.minutesBefore === 0,
    "expected reminder minutes to clamp",
  );
  assert(parsed.usage.total_tokens === 14, "expected usage to parse");
});

Deno.test("campus-ai-assistant supports multiple DeepSeek API key secret formats", () => {
  const envKeys = [
    "DEEPSEEK_API_KEY",
    "DEEPSEEK_API_KEYS",
    "DEEPSEEK_API_KEY_1",
    "DEEPSEEK_API_KEY_2",
  ];
  const previous = Object.fromEntries(
    envKeys.map((key) => [key, Deno.env.get(key)]),
  );

  try {
    for (const key of envKeys) Deno.env.delete(key);
    Deno.env.set("DEEPSEEK_API_KEY", "sk-primary");
    Deno.env.set("DEEPSEEK_API_KEYS", '["sk-a", "sk-b", "sk-a"]');
    Deno.env.set("DEEPSEEK_API_KEY_1", "sk-c");
    Deno.env.set("DEEPSEEK_API_KEY_2", "sk-b");

    assert(
      JSON.stringify(deepSeekAPIKeys()) ===
        JSON.stringify(["sk-primary", "sk-a", "sk-b", "sk-c"]),
      "expected ordered unique DeepSeek keys",
    );
    assert(
      JSON.stringify(parseDeepSeekAPIKeys("sk-1, sk-2\nsk-3; sk-4")) ===
        JSON.stringify(["sk-1", "sk-2", "sk-3", "sk-4"]),
      "expected delimiter parsing",
    );
  } finally {
    for (const key of envKeys) {
      const value = previous[key];
      if (value === undefined) {
        Deno.env.delete(key);
      } else {
        Deno.env.set(key, value);
      }
    }
  }
});

Deno.test("campus-ai-assistant prompt keeps file bodies out of scope and allows ledger organization only", () => {
  const prompt = systemPrompt();
  const plannerPrompt = actionPlannerSystemPrompt();

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
  assert(
    plannerPrompt.includes("需要用户确认后执行") &&
      plannerPrompt.includes("不能输出 Markdown"),
    "expected action planner safety prompt",
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
