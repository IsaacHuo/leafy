# 通知邮箱绑定 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 保留可验证的通知邮箱，同时彻底移除北林邮箱别名登录并修复验证码立即失效的问题。

**Architecture:** 北林登录继续使用原教务认证。通知邮箱沿用当前 Supabase 匿名社区会话，通过 email-change OTP 验证所有权；同一待验证邮箱使用 resend 获取新令牌，成功后只更新 `profiles.bound_email`。别名解析客户端、Edge Function 和数据库 RPC 全部下线。

**Tech Stack:** Swift 6、SwiftUI、Supabase Swift、Supabase Auth、PostgreSQL migration、Deno Edge Functions、XCTest、zsh。

## Global Constraints

- 最低 iOS 版本为 17，不新增依赖。
- 北林入口始终要求学号、教务密码、教务验证码和可访问教务系统的网络。
- 邮箱和 Supabase 密码不得成为北林登录凭据。
- 只有 `bound_email` 可用于后台通知；`pending_bound_email` 不可用于通知。
- 邮箱验证码固定为 8 位，邮件不得包含 `{{ .ConfirmationURL }}` 或 `{{ .TokenHash }}`。
- 通用入口现有邮箱注册和登录保持不变。

---

### Task 1: Make notification-email OTP behavior explicit

**Files:**
- Modify: `leafyTests/EmailBindingAndAliasLoginTests.swift`
- Modify: `leafy/Shared/Models/CommunityModels.swift`
- Modify: `leafy/Services/Supabase/CommunityService.swift`
- Modify: `leafy/Features/Profile/Presentation/ProfileEmailBindingView.swift`
- Modify: `supabase/config.toml`
- Modify: `supabase/tests/check-email-change-otp-template.sh`
- Modify: `supabase/templates/email-change-otp.html`

**Interfaces:**
- Produces: `CommunityEmailBinding.verificationCodeLength`, `isCompleteVerificationCode(_:)`, and `shouldResendVerification(pendingEmail:requestedEmail:)`.
- Consumes: `SupabaseClient.auth.resend(email:type:)` with `.emailChange`.

- [ ] **Step 1: Write failing XCTest cases**

Add tests asserting that code normalization keeps only the first 8 digits, completeness requires exactly 8 digits, and a normalized requested email equal to `pendingBoundEmail` selects resend.

- [ ] **Step 2: Run the focused test suite and observe RED**

Run `test_sim` with `-only-testing:leafyTests/EmailBindingAndAliasLoginTests`.

Expected: compile or assertion failure because the new API and 8-digit limit do not exist.

- [ ] **Step 3: Implement the minimal OTP behavior**

Set `verificationCodeLength = 8`, truncate normalized codes to that length, add exact completeness validation, and select `auth.resend(email:type:.emailChange)` when the requested address matches the pending address. Keep `auth.update(user:)` for first requests and changed addresses.

- [ ] **Step 4: Align UI and mail configuration**

Require exactly 8 digits before enabling “完成绑定”, mention 8 digits in the field/footer, set local `otp_length = 8`, and remove all login-alias language from the page and email template.

- [ ] **Step 5: Run XCTest and the mail-template check**

Expected: focused XCTest passes and `zsh supabase/tests/check-email-change-otp-template.sh` exits 0.

### Task 2: Remove the North Forest email-alias login surface

**Files:**
- Modify: `leafy/Features/Auth/LoginView.swift`
- Modify: `leafy/Features/Profile/Presentation/ProfileView.swift`
- Delete: `leafy/Services/Supabase/CampusEmailAliasLoginService.swift`
- Modify: `leafy/Services/Supabase/SupabaseConfig.swift`
- Modify: `leafy/Resources/Info.plist`
- Modify: `Config/Leafy.xcconfig`
- Modify: `Config/Leafy.example.xcconfig`
- Modify: `leafyTests/EmailBindingAndAliasLoginTests.swift`
- Modify: `leafyTests/WeatherServicingTests.swift`

**Interfaces:**
- Removes: `SupabaseConfig.emailLookupFunctionName` and `CampusEmailAliasLoginService`.
- Preserves: generic-entry `CustomCampusAuthService` email/password behavior.

- [ ] **Step 1: Remove alias tests and add a source-level absence check**

Delete alias resolver cases from the focused XCTest file. Use `rg` after implementation to assert no app/config references to `CampusEmailAliasLoginService`, `SUPABASE_EMAIL_LOOKUP_FUNCTION`, or “学号或已绑定邮箱”.

- [ ] **Step 2: Restore direct school login**

Use “学号” for non-custom login and pass the trimmed username directly to `schoolNetworkManager.performLogin(...)`; remove `schoolLoginAccount(for:)`.

- [ ] **Step 3: Remove alias service and configuration**

Delete the service file, config property, plist/xcconfig key, and stale test fixture argument. Change the Profile support-row detail to “接收服务通知”.

- [ ] **Step 4: Verify absence and compile**

Run the repository-wide `rg` check and `build_sim`. Expected: no forbidden references and build succeeds.

### Task 3: Retire the alias backend and apply Auth settings

**Files:**
- Delete: `supabase/functions/campus-email-lookup/index.ts`
- Create: `supabase/migrations/20260710120000_drop_campus_email_lookup.sql`
- Modify: `docs/supabase.md`
- Delete: `docs/superpowers/specs/2026-07-10-email-binding-otp-delivery-design.md`
- Delete: `docs/superpowers/plans/2026-07-10-email-binding-otp-delivery.md`

**Interfaces:**
- Removes: Edge Function `campus-email-lookup` and SQL function `public.lookup_verified_edu_id_by_email(text, text)`.
- Configures: hosted Auth `security_manual_linking_enabled = true` and `mailer_secure_email_change_enabled = false`.

- [ ] **Step 1: Add the drop migration and remove the Edge Function source**

The migration must run `drop function if exists public.lookup_verified_edu_id_by_email(text, text);`. Preserve the historical creation migration.

- [ ] **Step 2: Update Supabase documentation**

Document notification-only semantics, 8-digit OTP, required hosted Auth settings, and remove alias lookup deployment/config instructions.

- [ ] **Step 3: Apply remote changes**

PATCH only the two hosted Auth fields, apply the new database migration, and delete the deployed `campus-email-lookup` function. Do not push the complete local `config.toml` because it contains local URLs.

- [ ] **Step 4: Verify remote and local state**

Read back hosted Auth config, list deployed Edge Functions, run the mail-template check, `plutil -lint`, `build_sim`, and focused XCTest. Expected: manual linking true, secure email change false, alias function absent, build succeeds, tests pass.
