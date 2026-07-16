import { parse as parseHTML } from "npm:node-html-parser@6.1.13";
import ExcelJS from "npm:exceljs@4.4.0";

export const maxSearchResults = 8;
export const maxHTMLBytes = 2 * 1024 * 1024;
export const maxPDFBytes = 10 * 1024 * 1024;
export const maxSpreadsheetBytes = 8 * 1024 * 1024;
export const maxSpreadsheetCharacters = 30_000;
const maxSpreadsheetSheets = 5;
const maxSpreadsheetRowsPerSheet = 200;
const maxSpreadsheetColumnsPerRow = 30;
const fetchTimeoutMs = 10_000;
const receiptLifetimeSeconds = 10 * 60;
const encoder = new TextEncoder();
const decoder = new TextDecoder();

export type CampusAIWebToolName =
  | "official.search"
  | "web.search"
  | "web.read"
  | "document.fetch"
  | "spreadsheet.read";

export type CampusAISearchResult = {
  id: string;
  title: string;
  url: string;
  display_host: string;
  snippet?: string;
  published_at?: string;
  source_kind: "bjfu_official" | "public_web";
  trust_score: number;
  read_receipt: string;
};

export type CampusAIAttachmentResult = {
  id: string;
  title: string;
  url: string;
  file_type: string;
  read_receipt: string;
};

export type CampusAIReadResult = {
  id: string;
  title: string;
  url: string;
  display_host: string;
  text: string;
  published_at?: string;
  source_kind: "bjfu_official" | "public_web";
  trust_score: number;
  attachments: CampusAIAttachmentResult[];
};

export type CampusAISpreadsheetReadResult = {
  id: string;
  title: string;
  url: string;
  file_type: "XLSX";
  text: string;
  sheet_count: number;
  row_count: number;
  truncated: boolean;
};

type ReceiptPayload = {
  user_id: string;
  result_id: string;
  url: string;
  expires_at: number;
  content_kind: "html" | "document";
};

export class CampusAIWebToolError extends Error {
  constructor(
    readonly code: string,
    message: string,
    readonly status = 502,
    readonly retryable = false,
  ) {
    super(message);
  }
}

export async function searchBJFUOfficial(
  query: string,
  count: number,
  userID: string,
  signingSecret: string,
  signal?: AbortSignal,
): Promise<CampusAISearchResult[]> {
  const normalizedQuery = normalizedSearchQuery(query);
  const limit = boundedCount(count);
  const siteIDs = ["369", "121", "292"];
  const responses = await Promise.allSettled(
    siteIDs.map((siteID) => fetchBJFUSearch(normalizedQuery, siteID, signal)),
  );
  const raw = responses.flatMap((response) =>
    response.status === "fulfilled" ? response.value : []
  );
  const parseFailure = responses.find((response) =>
    response.status === "rejected" &&
    response.reason instanceof CampusAIWebToolError &&
    response.reason.code === "official_search_parse_failed"
  );
  if (raw.length === 0 && parseFailure?.status === "rejected") {
    throw parseFailure.reason;
  }
  if (responses.every((response) => response.status === "rejected")) {
    throw new CampusAIWebToolError(
      "official_search_failed",
      "北林官方检索暂时不可用，请稍后重试。",
      502,
      true,
    );
  }
  if (raw.length === 0) return [];
  const unique = deduplicateRawResults(raw)
    .filter((item) => isBJFUOfficialURL(item.url));
  const ranked = rankSearchResultsByRelevance(unique, normalizedQuery);
  console.info(JSON.stringify({
    event: "campus_ai_search_filtered",
    provider: "bjfu_official",
    raw_result_count: unique.length,
    returned_result_count: Math.min(ranked.length, limit),
  }));
  const selected = ranked.slice(0, limit);
  return await Promise.all(selected.map(async (item) => {
    const id = stableID("official", item.url);
    return {
      id,
      title: item.title,
      url: item.url,
      display_host: new URL(item.url).hostname.toLowerCase(),
      snippet: item.snippet,
      source_kind: "bjfu_official" as const,
      trust_score: officialTrustScore(item.url),
      read_receipt: await signReadReceipt({
        user_id: userID,
        result_id: id,
        url: item.url,
        expires_at: epochSeconds() + receiptLifetimeSeconds,
        content_kind: attachmentFileType(item.url) ? "document" : "html",
      }, signingSecret),
    };
  }));
}

export async function searchDuckDuckGoLite(
  query: string,
  count: number,
  userID: string,
  signingSecret: string,
  signal?: AbortSignal,
): Promise<CampusAISearchResult[]> {
  const normalizedQuery = normalizedSearchQuery(query);
  const url = new URL("https://lite.duckduckgo.com/lite/");
  url.searchParams.set("q", normalizedQuery);
  const response = await fetchWithTimeout(url, {
    headers: searchHeaders("https://duckduckgo.com/"),
    redirect: "follow",
  }, signal);
  if (response.status === 403 || response.status === 429) {
    throw new CampusAIWebToolError(
      "provider_rate_limited",
      "免费搜索暂时受到限制，请稍后重试。",
      429,
      true,
    );
  }
  if (!response.ok) {
    throw new CampusAIWebToolError(
      "web_search_failed",
      `免费搜索返回了 ${response.status} 错误。`,
      502,
      true,
    );
  }
  const html = await boundedResponseText(response, maxHTMLBytes);
  const parsed = parseDuckDuckGoLiteHTML(html, normalizedQuery);
  if (parsed.length === 0 && looksLikeChallenge(html)) {
    throw new CampusAIWebToolError(
      "provider_rate_limited",
      "免费搜索要求额外验证，请稍后重试。",
      429,
      true,
    );
  }
  if (parsed.length === 0 && !looksLikeNoResults(html)) {
    throw new CampusAIWebToolError(
      "web_search_parse_failed",
      "免费搜索页面结构发生变化，暂时无法解析结果。",
      502,
      true,
    );
  }
  const limit = boundedCount(count);
  const ranked = rankSearchResultsByRelevance(parsed, normalizedQuery);
  console.info(JSON.stringify({
    event: "campus_ai_search_filtered",
    provider: "duckduckgo_lite",
    raw_result_count: parsed.length,
    returned_result_count: Math.min(ranked.length, limit),
  }));
  return await Promise.all(
    ranked.slice(0, limit).map(async (item) => {
      const id = stableID("web", item.url);
      return {
        id,
        title: item.title,
        url: item.url,
        display_host: new URL(item.url).hostname.toLowerCase(),
        snippet: item.snippet,
        source_kind: isBJFUOfficialURL(item.url)
          ? "bjfu_official" as const
          : "public_web" as const,
        trust_score: isBJFUOfficialURL(item.url)
          ? officialTrustScore(item.url)
          : publicTrustScore(item.url),
        read_receipt: await signReadReceipt({
          user_id: userID,
          result_id: id,
          url: item.url,
          expires_at: epochSeconds() + receiptLifetimeSeconds,
          content_kind: attachmentFileType(item.url) ? "document" : "html",
        }, signingSecret),
      };
    }),
  );
}

export function parseBJFUSearchHTML(html: string) {
  const root = parseHTML(html);
  const results: Array<{ title: string; url: string; snippet?: string }> = [];
  for (const titleNode of root.querySelectorAll(".search01 a")) {
    const title = normalizeText(titleNode.textContent);
    const href = decodeHTMLEntities(titleNode.getAttribute("href") ?? "");
    const url = normalizeOfficialURL(href);
    if (!title || !url) continue;
    const listItem = titleNode.closest("li");
    const snippet = normalizeText(
      listItem?.querySelector(".search02")?.textContent ??
        listItem?.querySelector("p")?.textContent,
    );
    results.push({ title, url, snippet: snippet || undefined });
  }
  return deduplicateRawResults(results);
}

export function parseDuckDuckGoLiteHTML(html: string, query = "") {
  const root = parseHTML(html);
  const results: Array<{ title: string; url: string; snippet?: string }> = [];
  for (const anchor of root.querySelectorAll("a")) {
    const title = normalizeText(anchor.textContent);
    const href = decodeHTMLEntities(anchor.getAttribute("href") ?? "");
    const hrefLower = href.toLowerCase();
    if (
      ["ad_provider", "ad_domain", "ad_type", "/y.js"].some((marker) =>
        hrefLower.includes(marker)
      )
    ) {
      continue;
    }
    const url = duckDuckGoDestination(href);
    if (!title || !url || title.toLowerCase() === "duckduckgo") continue;
    const row = anchor.closest("tr");
    const rowText = normalizeText(row?.textContent).toLowerCase();
    if (
      rowText === "ad" || rowText.startsWith("ad ") || rowText.includes("广告")
    ) continue;
    const nextRow = row?.nextElementSibling;
    const snippet = normalizeText(nextRow?.textContent);
    results.push({
      title,
      url,
      snippet: snippet && snippet !== query ? snippet : undefined,
    });
  }
  return deduplicateRawResults(results);
}

export function rankSearchResultsByRelevance<
  T extends { title: string; url: string; snippet?: string },
>(results: T[], query: string): T[] {
  const queryConcepts = relevanceConcepts(query);
  if (queryConcepts.size === 0) return results;
  const compactQuery = relevanceText(query).replaceAll(" ", "");
  const queryYears = explicitYears(query);
  return results
    .map((result, index) => {
      const titleConcepts = relevanceConcepts(result.title);
      const snippetConcepts = relevanceConcepts(result.snippet ?? "");
      let score = intersectionCount(queryConcepts, titleConcepts) * 6 +
        intersectionCount(queryConcepts, snippetConcepts) * 2;
      const compactTitle = relevanceText(result.title).replaceAll(" ", "");
      const compactSnippet = relevanceText(result.snippet ?? "").replaceAll(
        " ",
        "",
      );
      if (compactQuery.length >= 4 && compactTitle.includes(compactQuery)) {
        score += 24;
      } else if (
        compactQuery.length >= 4 && compactSnippet.includes(compactQuery)
      ) {
        score += 8;
      }
      const candidateYears = explicitYears(
        `${result.title} ${result.snippet ?? ""}`,
      );
      const hasMatchingYear = queryYears.size === 0 ||
        candidateYears.size === 0 ||
        [...queryYears].some((year) => candidateYears.has(year));
      if (queryYears.size > 0 && candidateYears.size > 0 && hasMatchingYear) {
        score += 30;
      }
      return { result, index, score, hasMatchingYear };
    })
    .filter((candidate) => candidate.score > 0 && candidate.hasMatchingYear)
    .sort((left, right) => right.score - left.score || left.index - right.index)
    .map((candidate) => candidate.result);
}

function explicitYears(value: string) {
  const years = new Set<number>();
  for (const match of value.matchAll(/(?:19|20)\d{2}/g)) {
    years.add(Number(match[0]));
  }
  for (
    const match of value.matchAll(
      /(?<!\d)(\d{2})\s*(?:[-–—~～至]|到)\s*(\d{2})(?=\s*(?:学年|年|届))/g,
    )
  ) {
    const first = Number(match[1]);
    const second = Number(match[2]);
    years.add(first >= 70 ? 1900 + first : 2000 + first);
    years.add(second >= 70 ? 1900 + second : 2000 + second);
  }
  for (const match of value.matchAll(/(?<!\d)(\d{2})(?=\s*(?:年|届))/g)) {
    const year = Number(match[1]);
    years.add(year >= 70 ? 1900 + year : 2000 + year);
  }
  return years;
}

export async function readWebPage(
  receipt: string,
  userID: string,
  signingSecret: string,
  signal?: AbortSignal,
): Promise<CampusAIReadResult> {
  const receiptPayload = await verifyReadReceipt(
    receipt,
    userID,
    signingSecret,
  );
  if (receiptPayload.content_kind !== "html") {
    throw new CampusAIWebToolError(
      "wrong_content_kind",
      "该结果不是可读取的网页。",
      400,
    );
  }
  const response = await fetchFollowingSafeRedirects(
    receiptPayload.url,
    "text/html,application/xhtml+xml",
    signal,
  );
  const contentType = response.headers.get("content-type")?.toLowerCase() ?? "";
  if (
    contentType && !contentType.includes("text/html") &&
    !contentType.includes("application/xhtml")
  ) {
    throw new CampusAIWebToolError(
      "unsupported_content_type",
      "该链接不是可读取的网页。",
      415,
    );
  }
  const html = await boundedResponseText(response, maxHTMLBytes);
  const finalURL = response.url || receiptPayload.url;
  return await extractWebPage(
    html,
    finalURL,
    receiptPayload.result_id,
    userID,
    signingSecret,
  );
}

export async function fetchDocument(
  receipt: string,
  userID: string,
  signingSecret: string,
  signal?: AbortSignal,
) {
  const receiptPayload = await verifyReadReceipt(
    receipt,
    userID,
    signingSecret,
  );
  if (receiptPayload.content_kind !== "document") {
    throw new CampusAIWebToolError(
      "wrong_content_kind",
      "该结果不是可读取的附件。",
      400,
    );
  }
  const response = await fetchFollowingSafeRedirects(
    receiptPayload.url,
    "application/pdf,application/octet-stream",
    signal,
  );
  const contentType = response.headers.get("content-type")?.toLowerCase() ?? "";
  const fileType = attachmentFileType(response.url || receiptPayload.url);
  if (fileType !== "PDF" && !contentType.includes("application/pdf")) {
    throw new CampusAIWebToolError(
      "unsupported_document_type",
      "第一版只支持读取 PDF 正文。",
      415,
    );
  }
  const declaredLength = Number(response.headers.get("content-length") ?? "0");
  if (declaredLength > maxPDFBytes) {
    throw new CampusAIWebToolError(
      "document_too_large",
      "PDF 超过 10 MB，无法分析正文。",
      413,
    );
  }
  return response;
}

export async function readSpreadsheet(
  receipt: string,
  userID: string,
  signingSecret: string,
  signal?: AbortSignal,
): Promise<CampusAISpreadsheetReadResult> {
  const receiptPayload = await verifyReadReceipt(
    receipt,
    userID,
    signingSecret,
  );
  if (receiptPayload.content_kind !== "document") {
    throw new CampusAIWebToolError(
      "wrong_content_kind",
      "该结果不是可读取的附件。",
      400,
    );
  }
  return await readSpreadsheetURL(
    receiptPayload.url,
    receiptPayload.result_id,
    signal,
  );
}

export async function readSpreadsheetURL(
  value: string,
  resultID: string,
  signal?: AbortSignal,
): Promise<CampusAISpreadsheetReadResult> {
  const response = await fetchFollowingSafeRedirects(
    value,
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet,application/vnd.ms-excel,application/octet-stream",
    signal,
  );
  const finalURL = response.url || value;
  const fileType = attachmentFileType(finalURL);
  if (fileType !== "XLSX") {
    throw new CampusAIWebToolError(
      "unsupported_spreadsheet_type",
      "目前只支持读取 XLSX 表格，旧版 XLS 可下载后查看。",
      415,
    );
  }
  const declaredLength = Number(response.headers.get("content-length") ?? "0");
  if (declaredLength > maxSpreadsheetBytes) {
    throw new CampusAIWebToolError(
      "spreadsheet_too_large",
      "Excel 文件超过 8 MB，无法分析。",
      413,
    );
  }
  const data = await boundedResponseBytes(response, maxSpreadsheetBytes);
  return await parseSpreadsheetData(data, {
    id: resultID,
    title: filenameFromURL(finalURL),
    url: finalURL,
    fileType,
  });
}

export async function parseSpreadsheetData(
  data: Uint8Array,
  metadata: {
    id: string;
    title: string;
    url: string;
    fileType: "XLSX";
  },
): Promise<CampusAISpreadsheetReadResult> {
  if (data.byteLength > maxSpreadsheetBytes) {
    throw new CampusAIWebToolError(
      "spreadsheet_too_large",
      "Excel 文件超过 8 MB，无法分析。",
      413,
    );
  }

  const workbook = new ExcelJS.Workbook();
  try {
    await workbook.xlsx.load(data as never);
  } catch {
    throw new CampusAIWebToolError(
      "spreadsheet_parse_failed",
      "Excel 表格无法解析，文件可能已损坏或受到加密保护。",
      422,
    );
  }

  const sections: string[] = [];
  let rowCount = 0;
  let characterCount = 0;
  let truncated = workbook.worksheets.length > maxSpreadsheetSheets;
  for (const sheet of workbook.worksheets.slice(0, maxSpreadsheetSheets)) {
    const lines: string[] = [];
    const lastRow = Math.min(sheet.rowCount, maxSpreadsheetRowsPerSheet);
    for (let rowNumber = 1; rowNumber <= lastRow; rowNumber += 1) {
      const row = sheet.getRow(rowNumber);
      const lastColumn = Math.min(row.cellCount, maxSpreadsheetColumnsPerRow);
      const cells: string[] = [];
      for (let column = 1; column <= lastColumn; column += 1) {
        cells.push(normalizedSpreadsheetCell(row.getCell(column).text));
      }
      if (row.cellCount > maxSpreadsheetColumnsPerRow) truncated = true;
      const line = cells.join("\t").trimEnd();
      if (!line) continue;
      if (characterCount + line.length > maxSpreadsheetCharacters) {
        truncated = true;
        break;
      }
      lines.push(line);
      rowCount += 1;
      characterCount += line.length + 1;
    }
    if (sheet.rowCount > maxSpreadsheetRowsPerSheet) truncated = true;
    if (lines.length > 0) {
      sections.push(
        `[工作表: ${normalizedSpreadsheetCell(sheet.name)}]\n${
          lines.join("\n")
        }`,
      );
    }
    if (characterCount >= maxSpreadsheetCharacters) break;
  }

  if (sections.length === 0) {
    throw new CampusAIWebToolError(
      "spreadsheet_empty",
      "Excel 表格中没有可读取的数据。",
      422,
    );
  }
  return {
    id: metadata.id,
    title: metadata.title,
    url: metadata.url,
    file_type: metadata.fileType,
    text: sections.join("\n\n"),
    sheet_count: Math.min(workbook.worksheets.length, maxSpreadsheetSheets),
    row_count: rowCount,
    truncated,
  };
}

export async function signReadReceipt(
  payload: ReceiptPayload,
  signingSecret: string,
) {
  if (!signingSecret.trim()) {
    throw new CampusAIWebToolError(
      "missing_signing_secret",
      "联网研究服务配置不完整。",
      500,
    );
  }
  const encodedPayload = base64URLEncode(
    encoder.encode(JSON.stringify(payload)),
  );
  const signature = await hmac(encodedPayload, signingSecret);
  return `${encodedPayload}.${signature}`;
}

export async function verifyReadReceipt(
  receipt: string,
  expectedUserID: string,
  signingSecret: string,
): Promise<ReceiptPayload> {
  const [encodedPayload, signature, extra] = receipt.split(".");
  if (!encodedPayload || !signature || extra) {
    throw invalidReceipt();
  }
  const expectedSignature = await hmac(encodedPayload, signingSecret);
  if (!timingSafeEqual(signature, expectedSignature)) throw invalidReceipt();
  let payload: ReceiptPayload;
  try {
    payload = JSON.parse(decoder.decode(base64URLDecode(encodedPayload)));
  } catch {
    throw invalidReceipt();
  }
  if (
    payload.user_id !== expectedUserID || !payload.result_id ||
    !isSafePublicHTTPURL(payload.url) || payload.expires_at < epochSeconds()
  ) {
    throw invalidReceipt();
  }
  return payload;
}

export function isSafePublicHTTPURL(value: string) {
  try {
    const url = new URL(value);
    if (url.protocol !== "http:" && url.protocol !== "https:") return false;
    if (url.username || url.password) return false;
    if (url.port && url.port !== "80" && url.port !== "443") return false;
    const hostname = url.hostname.replace(/^\[|\]$/g, "").toLowerCase();
    if (
      !hostname || hostname === "localhost" || hostname.endsWith(".localhost")
    ) {
      return false;
    }
    if (hostname.endsWith(".local") || hostname.endsWith(".internal")) {
      return false;
    }
    if (isIPAddress(hostname)) return false;
    return true;
  } catch {
    return false;
  }
}

async function fetchBJFUSearch(
  query: string,
  siteID: string,
  signal?: AbortSignal,
) {
  const body = new URLSearchParams({
    siteID,
    query,
    matchType: "1",
    combinedSearch: "0",
  });
  const response = await fetchWithTimeout(
    new URL("https://www.bjfu.edu.cn/cms/web/search/index.jsp"),
    {
      method: "POST",
      headers: {
        ...searchHeaders("https://www.bjfu.edu.cn/"),
        "Content-Type": "application/x-www-form-urlencoded;charset=UTF-8",
      },
      body,
      redirect: "follow",
    },
    signal,
  );
  if (!response.ok) {
    throw new CampusAIWebToolError(
      "official_search_failed",
      `北林官方检索返回了 ${response.status} 错误。`,
      502,
      true,
    );
  }
  const html = await boundedResponseText(response, maxHTMLBytes);
  const parsed = parseBJFUSearchHTML(html);
  if (parsed.length === 0 && !looksLikeNoResults(html)) {
    throw new CampusAIWebToolError(
      "official_search_parse_failed",
      "北林官方检索页面结构发生变化，暂时无法解析结果。",
      502,
      true,
    );
  }
  return parsed;
}

async function extractWebPage(
  html: string,
  url: string,
  resultID: string,
  userID: string,
  signingSecret: string,
): Promise<CampusAIReadResult> {
  const root = parseHTML(html);
  for (
    const selector of [
      "script",
      "style",
      "noscript",
      "nav",
      "header",
      "footer",
      "form",
      "iframe",
    ]
  ) {
    for (const node of root.querySelectorAll(selector)) node.remove();
  }
  const title = normalizeText(
    root.querySelector("meta[property='og:title']")?.getAttribute("content") ??
      root.querySelector("h1")?.textContent ??
      root.querySelector("title")?.textContent,
  ) || new URL(url).hostname;
  const contentNode = root.querySelector("article") ??
    root.querySelector("main") ??
    root.querySelector(".content") ??
    root.querySelector("body") ?? root;
  const text = normalizePageText(contentNode.textContent).slice(0, 40_000);
  if (!text) {
    throw new CampusAIWebToolError(
      "page_has_no_readable_text",
      "网页没有可提取的正文。",
      422,
    );
  }
  const sourceKind = isBJFUOfficialURL(url)
    ? "bjfu_official" as const
    : "public_web" as const;
  const attachments: CampusAIAttachmentResult[] = [];
  const seen = new Set<string>();
  for (const anchor of root.querySelectorAll("a")) {
    const href = anchor.getAttribute("href");
    if (!href) continue;
    let attachmentURL: string;
    try {
      attachmentURL = new URL(decodeHTMLEntities(href), url).toString();
    } catch {
      continue;
    }
    if (!isSafePublicHTTPURL(attachmentURL) || seen.has(attachmentURL)) {
      continue;
    }
    const fileType = attachmentFileType(attachmentURL);
    if (!fileType) continue;
    seen.add(attachmentURL);
    const id = stableID("attachment", attachmentURL);
    attachments.push({
      id,
      title: normalizeText(anchor.textContent) ||
        filenameFromURL(attachmentURL),
      url: attachmentURL,
      file_type: fileType,
      read_receipt: await signReadReceipt({
        user_id: userID,
        result_id: id,
        url: attachmentURL,
        expires_at: epochSeconds() + receiptLifetimeSeconds,
        content_kind: "document",
      }, signingSecret),
    });
  }
  return {
    id: resultID,
    title,
    url,
    display_host: new URL(url).hostname.toLowerCase(),
    text,
    published_at: extractPublishedAt(root.textContent),
    source_kind: sourceKind,
    trust_score: sourceKind === "bjfu_official"
      ? officialTrustScore(url)
      : publicTrustScore(url),
    attachments: attachments.slice(0, 12),
  };
}

async function fetchFollowingSafeRedirects(
  initialURL: string,
  accept: string,
  signal?: AbortSignal,
) {
  let currentURL = initialURL;
  for (let redirectCount = 0; redirectCount <= 5; redirectCount += 1) {
    await assertSafePublicTarget(currentURL);
    const response = await fetchWithTimeout(new URL(currentURL), {
      headers: { ...searchHeaders(currentURL), Accept: accept },
      redirect: "manual",
    }, signal);
    if (response.status >= 300 && response.status < 400) {
      const location = response.headers.get("location");
      if (!location || redirectCount === 5) {
        throw new CampusAIWebToolError(
          "redirect_limit_exceeded",
          "网页重定向次数过多。",
          422,
        );
      }
      currentURL = new URL(location, currentURL).toString();
      continue;
    }
    if (!response.ok) {
      throw new CampusAIWebToolError(
        "page_fetch_failed",
        `网页返回了 ${response.status} 错误。`,
        502,
        response.status >= 500,
      );
    }
    return response;
  }
  throw new CampusAIWebToolError(
    "redirect_limit_exceeded",
    "网页重定向次数过多。",
    422,
  );
}

async function assertSafePublicTarget(value: string) {
  if (!isSafePublicHTTPURL(value)) {
    throw new CampusAIWebToolError(
      "unsafe_url",
      "链接未通过安全检查。",
      400,
    );
  }
  const hostname = new URL(value).hostname.toLowerCase();
  let addresses: string[] = [];
  try {
    const resolved = await Promise.allSettled([
      Deno.resolveDns(hostname, "A"),
      Deno.resolveDns(hostname, "AAAA"),
    ]);
    addresses = resolved.flatMap((result) =>
      result.status === "fulfilled" ? result.value : []
    );
  } catch {
    addresses = [];
  }
  if (addresses.length === 0) {
    throw new CampusAIWebToolError(
      "dns_resolution_failed",
      "网页域名暂时无法解析。",
      502,
      true,
    );
  }
  if (addresses.some(isPrivateOrReservedAddress)) {
    throw new CampusAIWebToolError(
      "unsafe_url",
      "链接解析到了不可访问的网络地址。",
      400,
    );
  }
}

function isPrivateOrReservedAddress(address: string): boolean {
  const value = address.toLowerCase();
  if (value.includes(":")) {
    if (
      value === "::" || value === "::1" || value.startsWith("fc") ||
      value.startsWith("fd") || /^fe[89ab]/.test(value) ||
      value.startsWith("ff") || value.startsWith("2001:db8")
    ) return true;
    const mappedIPv4 = value.match(/::ffff:(\d+\.\d+\.\d+\.\d+)$/)?.[1];
    return mappedIPv4 ? isPrivateOrReservedAddress(mappedIPv4) : false;
  }
  const parts = value.split(".").map(Number);
  if (parts.length !== 4 || parts.some((part) => !Number.isInteger(part))) {
    return true;
  }
  const [a, b] = parts;
  return a === 0 || a === 10 || a === 127 || a >= 224 ||
    (a === 100 && b >= 64 && b <= 127) ||
    (a === 169 && b === 254) ||
    (a === 172 && b >= 16 && b <= 31) ||
    (a === 192 && b === 168);
}

async function fetchWithTimeout(
  url: URL,
  init: RequestInit,
  parentSignal?: AbortSignal,
) {
  const timeout = AbortSignal.timeout(fetchTimeoutMs);
  const signal = parentSignal && "any" in AbortSignal
    ? AbortSignal.any([parentSignal, timeout])
    : timeout;
  try {
    return await fetch(url, { ...init, signal });
  } catch (error) {
    if (signal.aborted) {
      throw new CampusAIWebToolError(
        "tool_timeout",
        "联网工具请求超时。",
        504,
        true,
      );
    }
    throw error;
  }
}

async function boundedResponseText(response: Response, maxBytes: number) {
  const declaredLength = Number(response.headers.get("content-length") ?? "0");
  if (declaredLength > maxBytes) {
    throw new CampusAIWebToolError(
      "response_too_large",
      "网页内容过大，无法安全读取。",
      413,
    );
  }
  const reader = response.body?.getReader();
  if (!reader) return "";
  const chunks: Uint8Array[] = [];
  let total = 0;
  while (true) {
    const { value, done } = await reader.read();
    if (done) break;
    if (!value) continue;
    total += value.byteLength;
    if (total > maxBytes) {
      await reader.cancel();
      throw new CampusAIWebToolError(
        "response_too_large",
        "网页内容过大，无法安全读取。",
        413,
      );
    }
    chunks.push(value);
  }
  const data = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    data.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return decoder.decode(data);
}

async function boundedResponseBytes(response: Response, maxBytes: number) {
  const reader = response.body?.getReader();
  if (!reader) return new Uint8Array();
  const chunks: Uint8Array[] = [];
  let total = 0;
  while (true) {
    const { value, done } = await reader.read();
    if (done) break;
    if (!value) continue;
    total += value.byteLength;
    if (total > maxBytes) {
      await reader.cancel();
      throw new CampusAIWebToolError(
        "spreadsheet_too_large",
        "Excel 文件超过 8 MB，无法分析。",
        413,
      );
    }
    chunks.push(value);
  }
  const data = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    data.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return data;
}

function duckDuckGoDestination(href: string) {
  if (!href) return null;
  try {
    const candidate = href.startsWith("//") ? `https:${href}` : href;
    const url = new URL(candidate, "https://lite.duckduckgo.com/");
    if (url.hostname.endsWith("duckduckgo.com") && url.pathname === "/l/") {
      const destination = url.searchParams.get("uddg");
      return destination && isSafePublicHTTPURL(destination)
        ? destination
        : null;
    }
    return isSafePublicHTTPURL(url.toString()) &&
        !url.hostname.endsWith("duckduckgo.com")
      ? url.toString()
      : null;
  } catch {
    return null;
  }
}

function normalizeOfficialURL(value: string) {
  try {
    const url = new URL(value);
    if (!isBJFUOfficialURL(url.toString())) return null;
    url.protocol = "https:";
    return url.toString();
  } catch {
    return null;
  }
}

function isBJFUOfficialURL(value: string) {
  try {
    const host = new URL(value).hostname.toLowerCase();
    return host === "bjfu.edu.cn" || host.endsWith(".bjfu.edu.cn");
  } catch {
    return false;
  }
}

function officialTrustScore(value: string) {
  const host = new URL(value).hostname.toLowerCase();
  return ["jwc.bjfu.edu.cn", "graduate.bjfu.edu.cn", "www.bjfu.edu.cn"]
      .includes(host)
    ? 100
    : 88;
}

function publicTrustScore(value: string) {
  const host = new URL(value).hostname.toLowerCase();
  if (host.endsWith(".gov.cn")) return 85;
  if (host.endsWith(".edu.cn") || host.endsWith(".edu")) return 70;
  return 45;
}

function attachmentFileType(value: string) {
  try {
    const pathname = new URL(value).pathname.toLowerCase();
    const ext = pathname.match(/\.([a-z0-9]+)$/)?.[1];
    if (!ext) return null;
    const allowed = new Set([
      "pdf",
      "doc",
      "docx",
      "xls",
      "xlsx",
      "ppt",
      "pptx",
    ]);
    return allowed.has(ext) ? ext.toUpperCase() : null;
  } catch {
    return null;
  }
}

function filenameFromURL(value: string) {
  try {
    return decodeURIComponent(
      new URL(value).pathname.split("/").at(-1) ?? "附件",
    );
  } catch {
    return "附件";
  }
}

function normalizedSpreadsheetCell(value: unknown) {
  if (value === null || value === undefined) return "";
  return String(value)
    .replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/g, "")
    .replace(/[\t\r\n]+/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, 500);
}

function extractPublishedAt(text: string) {
  const match = text.match(
    /(?:20\d{2})[-年/.](?:0?[1-9]|1[0-2])[-月/.](?:0?[1-9]|[12]\d|3[01])日?/,
  );
  return match?.[0];
}

function normalizedSearchQuery(value: string) {
  const normalized = normalizeText(value);
  if (!normalized) {
    throw new CampusAIWebToolError("invalid_query", "搜索词不能为空。", 400);
  }
  return normalized.slice(0, 180);
}

function boundedCount(value: number) {
  if (!Number.isFinite(value)) return 5;
  return Math.min(maxSearchResults, Math.max(1, Math.trunc(value)));
}

function deduplicateRawResults<T extends { url: string }>(values: T[]) {
  const seen = new Set<string>();
  return values.filter((value) => {
    const key = value.url.replace(/#.*$/, "");
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

function normalizeText(value: unknown) {
  return typeof value === "string" ? value.replace(/\s+/g, " ").trim() : "";
}

function relevanceText(value: string) {
  return value
    .toLowerCase()
    .replaceAll("北京林业大学", " ")
    .replaceAll("北林官网", " ")
    .replaceAll("北林", " ")
    .replace(/[^\p{L}\p{N}]+/gu, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function relevanceConcepts(value: string) {
  const normalized = relevanceText(value);
  const concepts = new Set<string>();
  for (
    const chunk of normalized.split(" ").filter((item) => item.length >= 2)
  ) {
    concepts.add(chunk);
    if (/\p{Script=Han}/u.test(chunk) && Array.from(chunk).length > 2) {
      const characters = Array.from(chunk);
      for (let index = 0; index < characters.length - 1; index += 1) {
        concepts.add(characters[index] + characters[index + 1]);
      }
    }
  }
  for (
    const generic of [
      "北京",
      "林业",
      "大学",
      "官网",
      "学校",
      "资料",
      "查询",
      "搜索",
    ]
  ) {
    concepts.delete(generic);
  }
  if (
    ["保研", "推免", "推荐免试", "免试攻读"].some((term) =>
      normalized.includes(term)
    )
  ) {
    concepts.add("__postgraduate_recommendation__");
  }
  return concepts;
}

function intersectionCount(left: Set<string>, right: Set<string>) {
  let count = 0;
  for (const value of left) {
    if (right.has(value)) count += 1;
  }
  return count;
}

function normalizePageText(value: string) {
  return value
    .replace(/\r/g, "")
    .split("\n")
    .map((line) => line.replace(/[\t ]+/g, " ").trim())
    .filter(Boolean)
    .join("\n");
}

function decodeHTMLEntities(value: string) {
  return value
    .replace(
      /&#x([0-9a-f]+);/gi,
      (_, hex) => String.fromCodePoint(parseInt(hex, 16)),
    )
    .replace(
      /&#([0-9]+);/g,
      (_, number) => String.fromCodePoint(parseInt(number, 10)),
    )
    .replaceAll("&amp;", "&")
    .replaceAll("&quot;", '"')
    .replaceAll("&lt;", "<")
    .replaceAll("&gt;", ">");
}

function looksLikeChallenge(html: string) {
  const value = html.toLowerCase();
  return value.includes("captcha") || value.includes("anomaly") ||
    value.includes("verify you are human");
}

function looksLikeNoResults(html: string) {
  const normalized = html.toLowerCase();
  return [
    "no results",
    "no more results",
    "没有找到",
    "没有发现你要找的内容",
    "未找到",
    "暂无相关",
    "搜索结果为空",
  ].some((marker) => normalized.includes(marker));
}

function searchHeaders(referer: string) {
  return {
    Accept: "text/html,application/xhtml+xml",
    "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.7",
    Referer: referer,
    "User-Agent":
      "Mozilla/5.0 (compatible; MyLeafy/1.0; +https://www.bjfu.edu.cn/)",
  };
}

function stableID(prefix: string, value: string) {
  let hash = 2166136261;
  for (let index = 0; index < value.length; index += 1) {
    hash ^= value.charCodeAt(index);
    hash = Math.imul(hash, 16777619);
  }
  return `${prefix}-${(hash >>> 0).toString(16)}`;
}

async function hmac(value: string, secret: string) {
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    encoder.encode(value),
  );
  return base64URLEncode(new Uint8Array(signature));
}

function base64URLEncode(value: Uint8Array) {
  let binary = "";
  for (const byte of value) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(
    /=+$/,
    "",
  );
}

function base64URLDecode(value: string) {
  const padding = "=".repeat((4 - value.length % 4) % 4);
  const binary = atob(
    value.replaceAll("-", "+").replaceAll("_", "/") + padding,
  );
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

function timingSafeEqual(lhs: string, rhs: string) {
  if (lhs.length !== rhs.length) return false;
  let mismatch = 0;
  for (let index = 0; index < lhs.length; index += 1) {
    mismatch |= lhs.charCodeAt(index) ^ rhs.charCodeAt(index);
  }
  return mismatch === 0;
}

function invalidReceipt() {
  return new CampusAIWebToolError(
    "receipt_invalid",
    "网页读取凭证无效或已过期，请重新搜索。",
    401,
  );
}

function isIPAddress(hostname: string) {
  return /^\d{1,3}(\.\d{1,3}){3}$/.test(hostname) || hostname.includes(":");
}

function epochSeconds() {
  return Math.floor(Date.now() / 1000);
}
