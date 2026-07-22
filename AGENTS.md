## Project Context

This is MyLeafy, an iOS campus app.

Core stack:
- SwiftUI
- SwiftData
- URLSession
- Supabase
- Swift Package Manager

Timetable direction:
- The BJFU timetable always renders a 20-week container, keeps all 20 weeks of indexed data and SwiftUI week views resident, and limits only off-screen accessibility exposure. Course occurrences come only from the school response; unused weeks remain empty.
- Semester end dates and winter/summer break ranges come from semantic runtime calendar events, never from the 20-week timetable container.
- Runtime semester configuration selects the undergraduate semester ID, graduate term code, and first-week date without requiring an App Store release.
- Undergraduate and graduate timetable refreshes must use the same observable cache and error semantics.
- User-created schedules use one editor and one user-facing concept: dates inside the current 20-week semester project into the timetable, while dates outside it appear as countdowns. School-provided exams remain a separate data source.
- Schedule-report toggles apply immediately. Exam reminders run daily from 7 through 1 days before; important-date reports run 5, 3, and 1 days before.

Campus heatmap direction:
- Do not bundle semester-wide classroom occupancy data. The user explicitly logs in and updates the selected date and periods on demand.
- Keep only the latest successful heatmap data per campus account and overwrite it after each successful update.
- User-facing copy says “更新数据” and “上次更新”; avoid unfamiliar implementation terminology.

Community security direction:
- One `(campus_id, edu_id)` maps to exactly one durable community profile. Multiple replaceable device Supabase Auth sessions may link to that profile, while one Auth session maps to at most one profile.
- School login automatically inherits the matching community profile and content. A verified bound email is notification-only and never participates in school login or community recovery.
- Posts and comments are created through validated RPCs, reports never auto-hide content, and post images require a short-lived single-use server validation receipt.
- School logout clears school credentials and personal caches but does not destroy the durable community profile. Switching school identities hides the previous profile immediately and remaps the current device Auth link through bootstrap.

Leafy AI direction:
- Leafy AI defaults to the server-backed Flash service: free users receive 10 requests per Beijing day; the current weekly subscription receives 120 requests per Apple billing period with a 40-request Beijing daily cap.
- BYOK is an optional fallback. DeepSeek keys stay in the device Keychain and model requests go directly from iOS to DeepSeek; Pro is available only in BYOK mode.
- The only supported subscription product is `com.isaachuo.leafy.ai.weekly.v2`; legacy products grant no entitlement.
- Web research uses the authenticated `campus-ai-tools` Supabase Tool Gateway. The gateway may receive search queries and signed result receipts, but never receives the model key or local campus context.
- Prefer BJFU official CMS search, with DuckDuckGo Lite as a best-effort zero-key public search provider. Do not silently add paid search providers or random public SearXNG instances.
- Managed and BYOK research use one model-driven Agent loop. The model decides whether to answer directly, search, rewrite a query, judge candidate relevance and freshness, request the minimum personal context, prepare an explicit user-requested action, or stop; deterministic code must not impose semantic keyword, topic, year, or relevance-score gates.
- Search hits are internal candidates, and only successfully read pages or documents may become visible sources. Keep the Agent bounded by 10 research turns, 15 searches, 20 HTML page reads, 4 text-layer PDF reads, and 4 XLSX reads; these are safety limits, never targets, so the Agent must finish early once verified evidence is sufficient. Web and document content is untrusted data, and only search-issued IDs/receipts may be read.
- HTML, text-layer PDFs, and bounded XLSX tables are readable. XLS/DOC/DOCX/PPT/PPTX remain openable attachments, and scanned PDFs do not use OCR.
- Managed SSE responses must end with an explicit non-empty `done` or structured `error`; keepalive comments preserve long research connections, and abandoned quota reservations expire after 10 minutes without consuming quota.
- Personal context defaults to timetable and exams only. All other scopes are opt-in; BYOK sends only bounded local retrieval results, and external search is blocked after personal context is read or when a query contains direct identifiers or copied personal-result text.

Architecture and performance direction:
- Feature dependencies flow from Presentation to Application to Domain; Data implements narrow application protocols and is wired at the app composition root.
- Preserve existing public type names, repository contracts, SwiftData schema, Supabase interfaces, UI, copy, and navigation during structural refactors.
- Keep transient Leafy AI streaming text out of broad SwiftData invalidation; persist only at explicit checkpoints and terminal states.
- Build timetable render input and its signature once per refresh, and consume indexed snapshot data from child views.
- Community rating sections load on demand while retaining per-section state; feed projections and formatters must not be rebuilt per card body evaluation.
- Performance claims require three comparable runs, at least 10% median improvement, no more than 5% peak-memory regression, and no new app-owned leaks. Signposts must never include user content or personal data.

Minimum iOS target:
- iOS 17+

Before changing code:
- Use liquid glass effects if the device is iOS 26+.
- Inspect existing SwiftUI patterns first.
- Do not introduce heavy architecture unless needed.
- Keep campus features stable and user-facing behavior predictable.

Principles:

1. **Fail Fast / No Silent Failures**
   Do not swallow errors, hide failures, or add fallback logic that masks real problems. When something breaks, surface it clearly.

2. **Fix Root Causes, Not Symptoms**
   Do not cover bugs with small patches, special cases, or temporary workarounds. Find the real cause and fix it properly.

3. **Make Debugging Possible**
   Critical paths must have enough logging, tracing, or observable state to diagnose failures. When information is insufficient, add instrumentation instead of pretending the issue is fixed.

4. **Keep Documentation in Sync**
   When the project’s core stack, architecture, or product direction changes, update `agents.md`. Documentation must evolve with the code and remain the single source of truth.

5. **Do Not Break Mainline**
   Create a separate branch before large refactors, risky changes, or experiments. Keep the main branch stable and releasable.
