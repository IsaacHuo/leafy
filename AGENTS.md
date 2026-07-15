## Project Context

This is MyLeafy, an iOS campus app.

Core stack:
- SwiftUI
- SwiftData
- URLSession
- Supabase
- Swift Package Manager

Timetable direction:
- The BJFU timetable always renders a 20-week container. Course occurrences come only from the school response; unused weeks remain empty.
- Runtime semester configuration selects the undergraduate semester ID, graduate term code, and first-week date without requiring an App Store release.
- Undergraduate and graduate timetable refreshes must use the same observable cache and error semantics.

Campus heatmap direction:
- Do not bundle semester-wide classroom occupancy data. The user explicitly logs in and updates the selected date and periods on demand.
- Keep only the latest successful heatmap data per campus account and overwrite it after each successful update.
- User-facing copy says “更新数据” and “上次更新”; avoid unfamiliar implementation terminology.

Leafy AI direction:
- Leafy AI defaults to the server-backed Flash service: free users receive 10 requests per Beijing day; the current weekly subscription receives 120 requests per Apple billing period with a 40-request Beijing daily cap.
- BYOK is an optional fallback. DeepSeek keys stay in the device Keychain and model requests go directly from iOS to DeepSeek; Pro is available only in BYOK mode.
- The only supported subscription product is `com.isaachuo.leafy.ai.weekly.v2`; legacy products grant no entitlement.
- Web research uses the authenticated `campus-ai-tools` Supabase Tool Gateway. The gateway may receive search queries and signed result receipts, but never receives the model key or local campus context.
- Prefer BJFU official CMS search, with DuckDuckGo Lite as a best-effort zero-key public search provider. Do not silently add paid search providers or random public SearXNG instances.
- Keep research as a bounded single-tool agent loop. Web content is untrusted data, and only search-issued IDs/receipts may be read.
- HTML and text-layer PDFs are readable in v1. Office files remain openable attachments and scanned PDFs do not use OCR.

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
