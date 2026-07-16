import {
  isSafePublicHTTPURL,
  parseBJFUSearchHTML,
  parseDuckDuckGoLiteHTML,
  rankSearchResultsByRelevance,
  searchBJFUOfficial,
  searchDuckDuckGoLite,
  signReadReceipt,
  verifyReadReceipt,
} from "./campus-ai-web-tools.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

Deno.test("campus ai web tools parse and normalize BJFU CMS results", () => {
  const results = parseBJFUSearchHTML(`
    <ul class="Listheight">
      <li>
        <div class="search01">
          <a href="http&#x3a;&#x2f;&#x2f;jwc.bjfu.edu.cn&#x2f;jwkx&#x2f;notice.html">
            北京林业大学推荐2026届优秀毕业生免试工作方案
          </a>
        </div>
        <div class="search02">教务处发布的正式工作方案</div>
      </li>
      <li>
        <div class="search01">
          <a href="http://jwc.bjfu.edu.cn/jwkx/notice.html">重复结果</a>
        </div>
      </li>
      <li>
        <div class="search01">
          <a href="https://example.com/not-official">站外结果</a>
        </div>
      </li>
    </ul>
  `);

  assert(
    results.length === 1,
    "expected duplicate and non-BJFU results filtered",
  );
  assert(
    results[0].url === "https://jwc.bjfu.edu.cn/jwkx/notice.html",
    "expected official URL upgraded to HTTPS",
  );
  assert(results[0].snippet?.includes("正式工作方案"), "expected snippet");
});

Deno.test("campus ai search relevance keeps recommendation policy and drops screenshot noise", () => {
  const ranked = rankSearchResultsByRelevance([
    {
      title: "携手同心，守护师生健康",
      url: "https://www.bjfu.edu.cn/health",
      snippet: "守护师生身体健康和生命安全",
    },
    {
      title: "我校 3 篇学位论文获评优秀论文",
      url: "https://graduate.bjfu.edu.cn/thesis",
      snippet: "学位论文评选结果",
    },
    {
      title: "北京林业大学推荐 2026 届优秀应届本科毕业生免试攻读研究生工作方案",
      url: "https://jwc.bjfu.edu.cn/recommendation-2026",
      snippet: "推免申请资格和综合成绩办法",
    },
    {
      title: "北京林业大学章程",
      url: "https://www.bjfu.edu.cn/charter",
      snippet: "学校章程",
    },
  ], "2026 年工学院保研政策");

  assert(ranked.length === 1, "expected only the recommendation policy result");
  assert(
    ranked[0].url.endsWith("recommendation-2026"),
    "expected recommendation policy ranked first",
  );
});

Deno.test("campus ai search relevance recognizes recommendation synonyms and stable ties", () => {
  const ranked = rankSearchResultsByRelevance([
    { title: "推免工作方案", url: "https://jwc.bjfu.edu.cn/1" },
    { title: "推荐免试实施办法", url: "https://jwc.bjfu.edu.cn/2" },
  ], "保研政策");

  assert(ranked.length === 2, "expected recommendation synonyms to remain");
  assert(
    ranked[0].url.endsWith("/1"),
    "expected stable ordering for equal scores",
  );
});

Deno.test("campus ai search relevance rejects explicitly stale years", () => {
  const ranked = rankSearchResultsByRelevance([
    {
      title: "北京林业大学 2022 年春季学期期末考试总体安排",
      url: "https://jwc.bjfu.edu.cn/final-2022",
      snippet: "2021-2022 学年公共课考试通知",
    },
    {
      title: "北京林业大学 16-17 学年期末考试安排",
      url: "https://jwc.bjfu.edu.cn/final-2016",
    },
    {
      title: "北京林业大学 2025-2026 学年期末考试总体安排",
      url: "https://jwc.bjfu.edu.cn/final-2026",
      snippet: "教务处发布公共课考试安排",
    },
    {
      title: "北京林业大学期末考试安排",
      url: "https://jwc.bjfu.edu.cn/final-undated",
      snippet: "教务处通知",
    },
  ], "2026 北京林业大学 期末考试 总体安排");

  assert(
    ranked.some((item) => item.url.endsWith("final-2026")),
    "expected the matching academic year",
  );
  assert(
    ranked.some((item) => item.url.endsWith("final-undated")),
    "undated but relevant official results may remain",
  );
  assert(
    !ranked.some((item) => item.url.endsWith("final-2022")) &&
      !ranked.some((item) => item.url.endsWith("final-2016")),
    "explicitly stale years must be rejected",
  );
});

Deno.test("campus ai web tools distinguish empty results from provider structure changes", async () => {
  const originalFetch = globalThis.fetch;
  try {
    globalThis.fetch = () =>
      Promise.resolve(new Response("<html><body>暂无相关结果</body></html>"));
    const empty = await searchDuckDuckGoLite(
      "不存在的查询",
      8,
      "user-a",
      "test-secret",
    );
    assert(empty.length === 0, "expected an explicit provider empty state");

    globalThis.fetch = () =>
      Promise.resolve(
        new Response("<html><body>unexpected layout</body></html>"),
      );
    let webParseFailed = false;
    try {
      await searchDuckDuckGoLite("结构变化", 8, "user-a", "test-secret");
    } catch (error) {
      webParseFailed =
        (error as { code?: string }).code === "web_search_parse_failed";
    }
    assert(
      webParseFailed,
      "expected DuckDuckGo structure change to be explicit",
    );

    let officialParseFailed = false;
    try {
      await searchBJFUOfficial("结构变化", 8, "user-a", "test-secret");
    } catch (error) {
      officialParseFailed =
        (error as { code?: string }).code === "official_search_parse_failed";
    }
    assert(
      officialParseFailed,
      "expected all official provider parse failures to be explicit",
    );
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("campus ai official search queries all registered sites and deduplicates", async () => {
  const originalFetch = globalThis.fetch;
  const requestedSiteIDs: string[] = [];
  try {
    globalThis.fetch = (_input, init) => {
      const body = new URLSearchParams(String(init?.body ?? ""));
      requestedSiteIDs.push(body.get("siteID") ?? "");
      assert(body.get("matchType") === "1", "expected fuzzy CMS search");
      return Promise.resolve(
        new Response(`
        <div class="searchInfoList"><ul><li><div class="search01">
          <a href="https://jwc.bjfu.edu.cn/notice/1"><h2>推免通知</h2></a>
          <p>正式通知摘要</p>
        </div></li></ul></div>
      `),
      );
    };
    const results = await searchBJFUOfficial(
      "推免 2026",
      8,
      "user-a",
      "test-secret",
    );
    assert(
      JSON.stringify(requestedSiteIDs.sort()) ===
        JSON.stringify(["121", "292", "369"]),
      "expected all registered CMS site IDs",
    );
    assert(results.length === 1, "expected URL deduplication across sites");
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("campus ai web tools parse DuckDuckGo Lite redirect results", () => {
  const results = parseDuckDuckGoLiteHTML(`
    <table>
      <tr>
        <td>
          <a rel="nofollow" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fgraduate.bjfu.edu.cn%2Fpolicy.pdf&amp;rut=abc">
            北林推免办法
          </a>
        </td>
      </tr>
      <tr><td>北京林业大学正式文件</td></tr>
      <tr>
        <td><a href="javascript:alert(1)">坏链接</a></td>
      </tr>
      <tr>
        <td><a href="//duckduckgo.com/y.js?ad_domain=example.com&amp;uddg=https%3A%2F%2Fexample.com">广告</a></td>
      </tr>
    </table>
  `);

  assert(results.length === 1, "expected one safe result");
  assert(
    results[0].url === "https://graduate.bjfu.edu.cn/policy.pdf",
    "expected uddg destination decoded",
  );
  assert(results[0].snippet?.includes("正式文件"), "expected adjacent snippet");
});

Deno.test("campus ai web tools sign and verify scoped read receipts", async () => {
  const secret = "test-secret-with-enough-entropy";
  const receipt = await signReadReceipt({
    user_id: "user-a",
    result_id: "web-1",
    url: "https://www.bjfu.edu.cn/notice/1",
    expires_at: Math.floor(Date.now() / 1000) + 60,
    content_kind: "html",
  }, secret);
  const payload = await verifyReadReceipt(receipt, "user-a", secret);
  assert(payload.result_id === "web-1", "expected receipt payload");

  let rejectedCrossUser = false;
  try {
    await verifyReadReceipt(receipt, "user-b", secret);
  } catch {
    rejectedCrossUser = true;
  }
  assert(rejectedCrossUser, "expected cross-user receipt rejection");

  let rejectedTamper = false;
  try {
    await verifyReadReceipt(`${receipt}x`, "user-a", secret);
  } catch {
    rejectedTamper = true;
  }
  assert(rejectedTamper, "expected tampered receipt rejection");

  const expired = await signReadReceipt({
    user_id: "user-a",
    result_id: "web-expired",
    url: "https://www.bjfu.edu.cn/notice/expired",
    expires_at: Math.floor(Date.now() / 1000) - 1,
    content_kind: "html",
  }, secret);
  let rejectedExpired = false;
  try {
    await verifyReadReceipt(expired, "user-a", secret);
  } catch {
    rejectedExpired = true;
  }
  assert(rejectedExpired, "expected expired receipt rejection");
});

Deno.test("campus ai web tools reject unsafe fetch targets", () => {
  assert(
    isSafePublicHTTPURL("https://jwc.bjfu.edu.cn/a"),
    "expected public URL",
  );
  assert(!isSafePublicHTTPURL("http://127.0.0.1/a"), "reject IPv4 literal");
  assert(!isSafePublicHTTPURL("http://[::1]/a"), "reject IPv6 literal");
  assert(
    !isSafePublicHTTPURL("http://service.internal/a"),
    "reject internal host",
  );
  assert(!isSafePublicHTTPURL("ftp://example.com/a"), "reject non-HTTP URL");
  assert(
    !isSafePublicHTTPURL("https://example.com:8443/a"),
    "reject unusual port",
  );
});
