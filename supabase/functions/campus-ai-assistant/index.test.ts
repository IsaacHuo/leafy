import {
  actionPlannerPayload,
  actionPlannerSystemPrompt,
  agentSynthesisPayload,
  agentToolPlannerPayload,
  campusAIResponseFormat,
  deepSeekAPIKeys,
  deepSeekPayload,
  drainDeepSeekSSEBuffer,
  extractOfficialDocumentSourceFromHTML,
  fallbackActionDrafts,
  handler,
  hasExplicitCampusActionIntent,
  isSafePublicHTTPURL,
  localRetrievalDeliverables,
  normalizeAgentToolCalls,
  officialDocumentDeliverable,
  officialDocumentFreshness,
  officialDocumentTrustScore,
  parseActionPlannerActions,
  parseActionPlannerProviderResponse,
  parseAgentToolCallsFromProviderResponse,
  parseDeepSeekAPIKeys,
  parseSearchRoutingDecision,
  processDeepSeekSSEBlock,
  redactProviderError,
  safeAgentSearchQuery,
  searchRoutingPayload,
  shouldGenerateArtifact,
  shouldRunManagedAgent,
  systemPrompt,
  verifiedAppTransactionID,
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

Deno.test("campus-ai-assistant uses authenticated free quota when AppTransaction is unavailable", async () => {
  let verificationCalls = 0;
  const appTransactionID = await verifiedAppTransactionID(
    { app_transaction_id: "untrusted-client-id" },
    async () => {
      verificationCalls += 1;
      return { appTransactionID: "should-not-run", environment: "Sandbox" };
    },
  );

  assert(
    appTransactionID === null,
    "missing JWS must use auth-user quota identity",
  );
  assert(
    verificationCalls === 0,
    "missing JWS should not invoke Apple verification",
  );
});

Deno.test("campus-ai-assistant ignores invalid and bare AppTransaction identities", async () => {
  const appTransactionID = await verifiedAppTransactionID(
    {
      app_transaction_id: "untrusted-client-id",
      app_transaction_jws: "invalid-jws",
    },
    async () => {
      throw new Error("Invalid certificate chain.");
    },
  );

  assert(
    appTransactionID === null,
    "invalid JWS must not authorize a client-provided ID",
  );
});

Deno.test("campus-ai-assistant accepts only a verified AppTransaction identity", async () => {
  const appTransactionID = await verifiedAppTransactionID(
    {
      app_transaction_id: "verified-app-id",
      app_transaction_jws: "signed-jws",
    },
    async (_jws, expectedID) => {
      assert(
        expectedID === "verified-app-id",
        "expected ID should only corroborate the JWS",
      );
      return { appTransactionID: "verified-app-id", environment: "Sandbox" };
    },
  );

  assert(
    appTransactionID === "verified-app-id",
    "verified identity should be retained",
  );
});

Deno.test("campus-ai-assistant declares DeepSeek V4 Flash streaming Markdown payload", () => {
  const payload = deepSeekPayload({
    app_transaction_id: "app-tx-1",
    user_system_prompt: "请用列表回答",
    context: { campusID: "bjfu", timetable: { allCourses: [] } },
    context_settings: { includesTimetable: true },
    capabilities: { localSearchEnabled: true, webSearchEnabled: false },
    local_retrieval: {
      results: [{
        domain: "learning",
        title: "学习任务：刷题",
        summary: "每天 3 道",
        source_id: "learning.task.1",
      }],
    },
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
    !("max_tokens" in payload),
    "answer payload should not cap output tokens",
  );
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
  const userContent = JSON.parse(String(messages[1].content));
  assert(
    typeof userContent.current_local_time === "string" &&
      typeof userContent.time_zone_identifier === "string",
    "expected every answer request to include the current date and time zone",
  );
  assert(
    userContent.capabilities.localSearchEnabled === true,
    "expected capabilities in user content",
  );
  assert(
    userContent.local_retrieval.results[0].title === "学习任务：刷题",
    "expected local retrieval in user content",
  );
});

Deno.test("campus-ai-assistant omits personal context when routing does not select it", () => {
  const payload = deepSeekPayload(
    {
      context: {
        campusID: "bjfu",
        campusName: "北京林业大学",
        exams: [{ name: "高等数学" }],
      },
      context_settings: { includesExamsAndPlans: true },
      local_retrieval: { results: [{ title: "个人考试" }] },
    },
    "北京林业大学期末整体安排是什么？",
    false,
  ) as Record<string, unknown>;
  const messages = payload.messages as Array<Record<string, unknown>>;
  const content = JSON.parse(String(messages[1].content));

  assert(
    content.campus.name === "北京林业大学",
    "expected public campus context",
  );
  assert(
    typeof content.current_local_time === "string",
    "expected current date even without personal context",
  );
  assert(!("context" in content), "personal context should be omitted");
  assert(
    !("context_settings" in content),
    "context settings should be omitted",
  );
  assert(!("local_retrieval" in content), "local retrieval should be omitted");
});

Deno.test("campus-ai-assistant builds non-stream JSON-only action planner payload", () => {
  const payload = actionPlannerPayload(
    {
      app_transaction_id: "app-tx-1",
      context: { campusID: "bjfu", currentWeek: 2 },
      context_settings: { includesTimetable: true },
      capabilities: { actionPlanningEnabled: true },
      local_retrieval: {
        results: [{ title: "考试：高等数学", summary: "主楼 112" }],
      },
      current_local_time: "2026-07-16T09:30:00+09:00",
      time_zone_identifier: "Asia/Tokyo",
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
  assert(
    String(messages[1].content).includes("local_retrieval"),
    "expected local retrieval in action planner payload",
  );
  assert(
    String(messages[1].content).includes("medicalLedger"),
    "expected expanded route schema",
  );
  assert(
    String(messages[1].content).includes(
      '"current_local_time":"2026-07-16T09:30:00+09:00"',
    ) &&
      String(messages[1].content).includes(
        '"time_zone_identifier":"Asia/Tokyo"',
      ),
    "expected local time and timezone in planner input",
  );
  assert(
    String(messages[1].content).includes('"kind":"createSchedule"') &&
      !String(messages[1].content).includes('"kind":"createCountdown"'),
    "new planners should only receive the unified schedule action",
  );
  assert(
    payload.max_tokens === 700,
    "automatic mode should keep the compact planner",
  );
  assert(
    String(messages[0].content).includes("禁止返回 artifact"),
    "automatic mode must explicitly reject inferred cards",
  );
});

Deno.test("campus-ai-assistant enables card planning only for explicit artifact mode", () => {
  const payload = actionPlannerPayload(
    { output_mode: "artifact", app_transaction_id: "app-tx-1" },
    "整理复习计划",
    "先按章节复习。",
  ) as Record<string, unknown>;
  const messages = payload.messages as Array<Record<string, unknown>>;

  assert(payload.max_tokens === 4000, "card mode should allow a complete card");
  assert(
    String(messages[0].content).includes("手动开启生成卡片"),
    "expected explicit card instruction",
  );
  assert(
    String(messages[1].content).includes('"should_generate_card":true'),
    "expected the manual card flag in planner input",
  );
});

Deno.test("campus-ai-assistant enables model routing whenever managed research is available", () => {
  assert(
    shouldRunManagedAgent({ web_search_enabled: true }),
    "enabled web research should use the semantic router",
  );
  assert(
    !shouldRunManagedAgent({ web_search_enabled: false }),
    "disabled web search should force fast path",
  );
  assert(
    !shouldRunManagedAgent({ agent_mode: "off", web_search_enabled: true }),
    "agent_mode off should force fast path",
  );
  assert(
    !shouldRunManagedAgent({}),
    "missing web_search_enabled should default to fast path",
  );
});

Deno.test("campus-ai-assistant builds a bounded routing payload without personal context", () => {
  const payload = searchRoutingPayload(
    {
      context: {
        campusID: "bjfu",
        campusName: "北京林业大学",
        exams: [{ name: "不应进入路由的个人考试" }],
      },
      context_settings: { includesExamsAndPlans: true },
      local_retrieval: { results: [{ title: "不应进入路由的本地结果" }] },
      recent_messages: [
        { role: "user", text: "第一轮" },
        { role: "assistant", text: "第二轮" },
      ],
      web_search_enabled: true,
    },
    "北京林业大学期末整体安排是什么？",
  ) as Record<string, unknown>;
  const content = String(
    (payload.messages as Array<Record<string, unknown>>)[1].content,
  );

  assert(
    payload.tool_choice === "required",
    "router must return a structured decision",
  );
  assert(
    content.includes("北京林业大学期末整体安排是什么"),
    "expected question",
  );
  assert(content.includes("北京林业大学"), "expected public campus descriptor");
  assert(!content.includes("个人考试"), "router must exclude personal exams");
  assert(!content.includes("本地结果"), "router must exclude local retrieval");
  assert(
    !content.includes("context_settings"),
    "router must exclude context settings",
  );
});

Deno.test("campus-ai-assistant parses semantic routing decisions", () => {
  const response = JSON.stringify({
    choices: [{
      message: {
        tool_calls: [{
          function: {
            name: "route_search",
            arguments: JSON.stringify({
              route: "officialResearch",
              query: "2026 北京林业大学 推免 政策",
              use_personal_context: false,
              reason_code: "public_institutional",
            }),
          },
        }],
      },
    }],
  });
  const decision = parseSearchRoutingDecision(
    response,
    "2026 年北京林业大学保研政策",
  );

  assert(decision.route === "officialResearch", "expected official research");
  assert(
    !decision.usePersonalContext,
    "public policy should not use personal context",
  );
  assert(decision.query.includes("2026"), "expected year anchor");
});

Deno.test("campus-ai-assistant builds DeepSeek tool planner payload", () => {
  const payload = agentToolPlannerPayload(
    {
      app_transaction_id: "app-tx-1",
      context: { campusID: "bjfu", currentWeek: 2 },
      context_settings: { includesTimetable: true },
      capabilities: { localSearchEnabled: true },
      local_retrieval: { results: [{ title: "本周考试", summary: "周三" }] },
      recent_messages: [{ role: "user", text: "你好" }],
    },
    "帮我查一下北林最近通知并结合课表安排",
  ) as Record<string, unknown>;
  const tools = payload.tools as Array<Record<string, unknown>>;

  assert(payload.model === "deepseek-v4-flash", "expected DeepSeek V4 Flash");
  assert(payload.stream === false, "expected non-stream planner");
  assert(payload.tool_choice === "auto", "expected automatic tool choice");
  assert(tools.length === 4, "expected four agent tools");
  assert(
    JSON.stringify(tools).includes("web_search") &&
      JSON.stringify(tools).includes("official_document_search") &&
      JSON.stringify(tools).includes("delegate_subtask") &&
      JSON.stringify(tools).includes("action_plan"),
    "expected tool definitions",
  );
  const plannerContent = String(
    (payload.messages as Array<Record<string, unknown>>)[1].content,
  );
  assert(
    plannerContent.includes("recent_messages") &&
      !plannerContent.includes("local_retrieval") &&
      !plannerContent.includes("context_settings"),
    "tool planner should only receive the current question and bounded recent messages",
  );
});

Deno.test("campus-ai-assistant preserves search intent anchors", () => {
  assert(
    safeAgentSearchQuery(
      "2026 北京林业大学推荐免试工作方案",
      "2026 年工学院保研政策",
    ) === "2026 北京林业大学推荐免试工作方案",
    "campus synonym should preserve the planner query",
  );
  assert(
    safeAgentSearchQuery(
      "师生健康与学位论文",
      "2026 年工学院保研政策",
    ) === "2026 年工学院保研政策",
    "unrelated planner query should fall back to the user question",
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
  assert(normalized[0].name === "web_search", "expected explicit web search");
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
    disabled.every((call) =>
      call.name !== "web_search" && call.name !== "official_document_search"
    ),
    "disabled web search should filter search calls",
  );
});

Deno.test("campus-ai-assistant keeps official document freshness bounded", () => {
  assert(
    officialDocumentFreshness("今天最新的教务处通知") === "oneMonth",
    "recent official requests should use freshness",
  );
  assert(
    officialDocumentFreshness("查教务处论文格式") === "noLimit",
    "default official search should be noLimit",
  );
});

Deno.test("campus-ai-assistant filters unsafe official document URLs", () => {
  assert(
    isSafePublicHTTPURL("https://jwc.bjfu.edu.cn/info/1012/1234.htm"),
    "expected public official URL",
  );
  assert(!isSafePublicHTTPURL("ftp://jwc.bjfu.edu.cn/a.pdf"), "reject ftp");
  assert(!isSafePublicHTTPURL("http://127.0.0.1/a"), "reject localhost ipv4");
  assert(!isSafePublicHTTPURL("http://10.1.2.3/a"), "reject private ipv4");
  assert(!isSafePublicHTTPURL("http://[::1]/a"), "reject localhost ipv6");
});

Deno.test("campus-ai-assistant scores BJFU official domains higher", () => {
  const officialScore = officialDocumentTrustScore({
    id: "web-1",
    title: "北京林业大学教务处论文格式",
    url: "https://jwc.bjfu.edu.cn/info/1012/1234.htm",
    siteName: "北京林业大学教务处",
  }, { campusID: "bjfu", campusName: "北京林业大学" });
  const genericScore = officialDocumentTrustScore({
    id: "web-2",
    title: "论文格式经验",
    url: "https://example.com/bjfu-thesis",
    siteName: "Example",
  }, { campusID: "bjfu", campusName: "北京林业大学" });

  assert(officialScore > genericScore, "expected BJFU official host boost");
  assert(officialScore >= 0.8, "expected high official trust score");
});

Deno.test("campus-ai-assistant extracts official HTML metadata and attachments", () => {
  const source = extractOfficialDocumentSourceFromHTML(
    `
    <!doctype html>
    <html>
      <head>
        <title>本科毕业论文格式要求</title>
        <link rel="canonical" href="/info/1012/5678.htm">
        <meta name="description" content="北京林业大学本科毕业论文格式、模板与附件下载。">
      </head>
      <body>
        <main>
          <p>请下载论文格式模板和封面附件。</p>
          <a href="/files/thesis-template.docx">论文模板</a>
          <a href="https://jwc.bjfu.edu.cn/files/format.pdf">格式说明 PDF</a>
          <a href="/files/unsafe.exe">不应出现</a>
        </main>
      </body>
    </html>
    `,
    "https://jwc.bjfu.edu.cn/info/1012/1234.htm",
    {
      id: "web-1",
      title: "本科毕业论文格式要求",
      url: "https://jwc.bjfu.edu.cn/info/1012/1234.htm",
      siteName: "北京林业大学教务处",
    },
    0.96,
  );

  assert(source !== null, "expected source");
  assert(source.title === "本科毕业论文格式要求", "expected title");
  assert(
    source.url === "https://jwc.bjfu.edu.cn/info/1012/5678.htm",
    "expected canonical URL",
  );
  assert(source.attachments.length === 2, "expected allowed attachments only");
  assert(source.attachments[0].fileType === "DOCX", "expected docx type");
  assert(source.attachments[1].fileType === "PDF", "expected pdf type");
});

Deno.test("campus-ai-assistant builds official document deliverable", () => {
  const deliverable = officialDocumentDeliverable("北京林业大学 论文格式", [{
    id: "official-1",
    title: "本科毕业论文格式要求",
    url: "https://jwc.bjfu.edu.cn/info/1012/5678.htm",
    siteName: "北京林业大学教务处",
    summary: "页面含论文格式模板。",
    trustScore: 0.96,
    attachments: [{
      title: "论文模板",
      url: "https://jwc.bjfu.edu.cn/files/thesis-template.docx",
      fileType: "DOCX",
    }],
  }]);
  const donePayload = JSON.stringify({
    type: "done",
    deliverables: [deliverable],
  });

  assert(
    deliverable.formats.join(",") === "html",
    "unspecified artifact format should default to html",
  );
  const explicitFormats = officialDocumentDeliverable(
    "北京林业大学 论文格式 Markdown TXT",
    deliverable.sources,
  );
  assert(
    explicitFormats.formats.join(",") === "markdown,txt",
    "explicit artifact formats should be preserved",
  );
  assert(
    donePayload.includes("official-1") &&
      donePayload.includes("thesis-template.docx"),
    "expected done payload to serialize deliverables",
  );
});

Deno.test("campus-ai-assistant builds local retrieval deliverable", () => {
  const automaticBody = {
    local_retrieval: {
      results: [{
        domain: "learning",
        title: "学习任务：整理论文提纲",
        summary: "周五前完成",
        source_id: "learning.task.1",
      }],
    },
  };
  assert(
    localRetrievalDeliverables(
      automaticBody,
      "请导出 HTML Markdown TXT 资料包",
      "已整理。",
    ).length === 0,
    "automatic mode must not infer a card from keywords",
  );
  assert(
    !shouldGenerateArtifact(automaticBody),
    "missing output mode should default to no card",
  );

  const deliverables = localRetrievalDeliverables(
    {
      output_mode: "artifact",
      local_retrieval: {
        results: [{
          domain: "learning",
          title: "学习任务：整理论文提纲",
          summary: "周五前完成 <初稿>",
          source_id: "learning.task.1",
        }],
      },
    },
    "请导出 HTML Markdown TXT 资料包",
    "已整理 <任务>。",
  );

  assert(deliverables.length === 1, "expected one local deliverable");
  assert(
    deliverables[0].formats.join(",") === "html,markdown,txt",
    "expected all artifact formats",
  );
  assert(
    deliverables[0].sources[0].url.startsWith("leafy://local/learning/"),
    "expected local source URL",
  );
  assert(
    deliverables[0].sources[0].siteName === "Leafy 学习资料",
    "expected local domain title",
  );
  const defaultDeliverables = localRetrievalDeliverables(
    {
      output_mode: "artifact",
      local_retrieval: {
        results: [{
          domain: "learning",
          title: "学习任务：整理论文提纲",
          summary: "周五前完成",
          source_id: "learning.task.1",
        }],
      },
    },
    "请导出资料包",
    "已整理。",
  );
  assert(
    defaultDeliverables[0].formats.join(",") === "html",
    "unspecified local artifact format should default to html",
  );
});

Deno.test("campus-ai-assistant handles missing tool signing secret before network", async () => {
  const previous = Deno.env.get("CAMPUS_AI_TOOL_SIGNING_SECRET");
  try {
    Deno.env.delete("CAMPUS_AI_TOOL_SIGNING_SECRET");
    let threw = false;
    try {
      await webSearch("北林通知", "oneMonth", 3, new AbortController().signal);
    } catch (error) {
      threw = true;
      assert(
        error instanceof Error &&
          error.message.includes("CAMPUS_AI_TOOL_SIGNING_SECRET"),
        "expected missing tool signing secret error",
      );
    }
    assert(threw, "expected webSearch to reject without key");
  } finally {
    if (previous === undefined) {
      Deno.env.delete("CAMPUS_AI_TOOL_SIGNING_SECRET");
    } else {
      Deno.env.set("CAMPUS_AI_TOOL_SIGNING_SECRET", previous);
    }
  }
});

Deno.test("campus-ai-assistant synthesis payload carries citations and search results", () => {
  const payload = agentSynthesisPayload(
    {
      app_transaction_id: "app-tx-1",
      context: { campusID: "bjfu" },
      local_retrieval: {
        results: [{ title: "学习任务：刷题", summary: "每天 3 道" }],
      },
    },
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
    !("max_tokens" in payload),
    "synthesis payload should not cap output tokens",
  );
  assert(
    String(messages[0].content).includes("不要在正文中输出来源标题") &&
      !String(messages[0].content).includes("Markdown 链接标注来源"),
    "expected sources to stay outside the answer body",
  );
  assert(
    String(messages[1].content).includes("web_search_results") &&
      String(messages[1].content).includes("subtask_results"),
    "expected agent inputs",
  );
  assert(
    String(messages[1].content).includes("local_retrieval"),
    "expected local retrieval in synthesis payload",
  );

  const publicPayload = agentSynthesisPayload(
    {
      context: { campusID: "bjfu", campusName: "北京林业大学" },
      local_retrieval: { results: [{ title: "个人考试" }] },
    },
    "北京林业大学期末整体安排是什么？",
    [],
    [],
    [],
    [],
    false,
  ) as Record<string, unknown>;
  const publicMessages = publicPayload.messages as Array<
    Record<string, unknown>
  >;
  const publicContent = JSON.parse(String(publicMessages[1].content));
  assert(
    !("local_retrieval" in publicContent),
    "public synthesis should omit local retrieval",
  );
});

Deno.test("campus-ai-assistant parses and validates action planner output", () => {
  const actions = parseActionPlannerActions(`
  \`\`\`json
  {
    "actions": [
      {"kind":"open_academic_route","title":"","payload":{"route":"trainingProgram"}},
      {"kind":"create_countdown","title":"创建倒计时","payload":{"countdown_title":"期末考试","target_date":"2026-07-01"}},
      {"kind":"open_academic_route","title":"打开医疗台账","payload":{"route":"medicalLedger"}},
      {"kind":"open_academic_route","title":"打开未知页面","payload":{"route":"communityPost"}}
    ]
  }
  \`\`\`
  `);

  assert(actions.length === 3, "expected invalid route to be filtered");
  assert(actions[0].kind === "openAcademicRoute", "expected normalized kind");
  assert(
    actions[0].payload?.route === "trainingProgram",
    "expected trainingProgram route",
  );
  assert(
    actions[1].payload?.countdownTitle === "期末考试",
    "expected snake_case payload to normalize",
  );
  assert(
    actions[2].payload?.route === "medicalLedger",
    "expected expanded medical route",
  );
});

Deno.test("campus-ai-assistant falls back to schedule action cards", () => {
  const actions = fallbackActionDrafts(
    {
      web_search_enabled: false,
      current_local_time: "2026-07-16T23:30:00+09:00",
      time_zone_identifier: "Asia/Tokyo",
    },
    "帮我设置一个明天早上十点的日程",
    "已准备日程，请确认保存。",
  );

  assert(actions.length === 1, "expected one fallback action");
  assert(
    actions[0].kind === "createSchedule",
    "expected unified schedule action",
  );
  assert(
    actions[0].payload?.startsAt === "2026-07-17T10:00:00+09:00",
    "expected tomorrow morning ten with the device timezone",
  );
});

Deno.test("campus-ai-assistant never infers actions from its own answer", () => {
  assert(
    !hasExplicitCampusActionIntent("Hi"),
    "expected a greeting to stay a normal answer",
  );
  const actions = fallbackActionDrafts(
    { web_search_enabled: false },
    "Hi",
    "你可以添加日程或查看考试安排。",
  );
  assert(
    actions.length === 0,
    "expected answer suggestions to create no action",
  );
});

Deno.test("campus-ai-assistant accepts incomplete unified schedule drafts", () => {
  const actions = parseActionPlannerActions(JSON.stringify({
    actions: [{
      kind: "create_schedule",
      title: "",
      payload: { location: "图书馆", minutes_before: -5 },
    }],
  }));

  assert(actions.length === 1, "expected incomplete schedule draft");
  assert(actions[0].kind === "createSchedule", "expected normalized kind");
  assert(actions[0].title === "添加日程", "expected default title");
  assert(actions[0].payload?.location === "图书馆", "expected location");
  assert(actions[0].payload?.minutesBefore === 0, "expected reminder clamp");
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
  assert(
    parsed.artifact === null,
    "automatic planner response should not invent a card",
  );
});

Deno.test("campus-ai-assistant parses a validated manual card", () => {
  const parsed = parseActionPlannerProviderResponse(JSON.stringify({
    choices: [{
      message: {
        content: JSON.stringify({
          actions: [],
          artifact: {
            title: "期末复习卡片",
            summary: "按三阶段完成复习。",
            markdown:
              "# 期末复习\n\n| 阶段 | 任务 |\n| --- | --- |\n| 一 | 梳理 |",
          },
        }),
      },
    }],
  }));

  assert(parsed.artifact?.title === "期末复习卡片", "expected card title");
  assert(
    parsed.artifact?.markdown.includes("| --- | --- |") === true,
    "expected complete card markdown",
  );
});

Deno.test("campus-ai-assistant prefers the managed DeepSeek API key list", () => {
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
        JSON.stringify(["sk-a", "sk-b"]),
      "expected the managed list to ignore legacy key secrets",
    );
    assert(
      JSON.stringify(parseDeepSeekAPIKeys("sk-1, sk-2\nsk-3; sk-4")) ===
        JSON.stringify(["sk-1", "sk-2", "sk-3", "sk-4"]),
      "expected delimiter parsing",
    );

    Deno.env.delete("DEEPSEEK_API_KEYS");
    assert(
      JSON.stringify(deepSeekAPIKeys()) ===
        JSON.stringify(["sk-primary", "sk-c", "sk-b"]),
      "expected legacy key secrets to remain available as a fallback",
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

  assert(
    prompt.includes("不要反复解释内部数据来源"),
    "expected user-facing source wording",
  );
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
  assert(
    plannerPrompt.includes("新建、添加、设置日程或提醒时生成 createSchedule") &&
      prompt.includes("用户在表单中保存前，不得声称已经添加、设置或执行"),
    "expected pending unified schedule instruction",
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
