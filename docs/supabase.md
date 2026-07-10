# MyLeafy Supabase 接入

MyLeafy 使用 Supabase 承接社区、通知、公告、反馈、评教、共享课表和运营后台。Supabase 不替代学校教务登录；内部 Swift/SQL 边界仍保留 Leafy 命名。

## 1. 身份模型

当前采用“匿名 Supabase 会话 + 教务学号绑定”：

1. 用户先在 iOS App 中完成强智教务登录。
2. App 创建或恢复匿名 Supabase 会话。
3. App 把已认证的教务学号发送给 `community-bootstrap-user` Edge Function。
4. Edge Function 使用当前 `auth.uid()` 绑定或复用 `(campus_id, edu_id)` 对应的 profile。

这样做的好处：

- 用户不需要额外注册社区账号。
- iOS 客户端不持有 `service_role`。
- 社区表仍可用 `auth.uid()`、profile 映射和 RLS 做权限控制。
- Supabase 只负责 MyLeafy 自己的社区业务数据。

重要边界：当前是 App 端确认教务登录成功后再进行学号绑定。若未来要防止改包伪造学号，需要把教务校验迁到受控后端。

## 2. Supabase 项目配置

控制台需要启用：

- Anonymous sign-ins。
- Email provider。
- Email OTP / Magic Link 和 Email password 登录。

生产或 TestFlight 环境使用自定义 SMTP。当前邮箱能力主要服务社区邮箱验证、通知相关身份补充和后续受控登录能力；验证码邮件建议接入阿里云 DirectMail / 邮件推送，避免 Resend 在国内邮箱上的明显延迟。Cloudflare Email Routing 只用于 `support@myleafy.space` 这类收信转发，不负责 Auth 验证码投递。

Supabase Auth 的 Magic Link / OTP 邮件模板应以验证码为主，正文展示 `{{ .Token }}`。不要把主要操作设计成点击 `{{ .ConfirmationURL }}`；`leafy://auth/callback` 仅保留为旧邮件链接兼容。

邮箱绑定使用 Auth 的 `Change email address` 模板。模板源文件为 `supabase/templates/email-change-otp.html`，主题必须为 `MyLeafy 绑定邮箱验证码`，正文必须保留 `{{ .Token }}` 和 `{{ .NewEmail }}`，不得包含 `{{ .ConfirmationURL }}` 或 `{{ .TokenHash }}`。本地 Supabase 会从 `supabase/config.toml` 加载该模板。

托管 Supabase 项目不会自动读取仓库中的 `config.toml`。每次修改模板后，需在 Dashboard 的 **Auth → Email Templates → Change email address** 中粘贴同一份主题和 HTML，或用 Management API 更新对应的 `mailer_subjects_email_change` 与 `mailer_templates_email_change_content`。发布后先发一封测试邮件：它应只显示验证码，不能显示 “Confirm email change” 或任何确认邮箱的超链接。

自定义 SMTP 建议：

- Sender email：`no-reply@mail.myleafy.space`。
- Sender name：`MyLeafy`。
- Host / Port / Username / Password：按阿里云 DirectMail 控制台提供的 SMTP 信息填写。
- Minimum interval per user：`60` 秒。

阿里云发信域名不要求把域名 NS 迁到阿里云。当前权威 DNS 在 Cloudflare，就在 Cloudflare DNS 手动添加阿里云 DirectMail 控制台给出的所有权验证、SPF、DKIM、MX / 回信地址等记录；阿里云控制台的一键解析只适用于域名也托管在阿里云的情况。

iOS 工程从 `Info.plist` / xcconfig 读取：

- `SUPABASE_URL`
- `SUPABASE_PUBLISHABLE_KEY`
- `SUPABASE_COMMUNITY_BOOTSTRAP_FUNCTION`
- `SUPABASE_EMAIL_LOOKUP_FUNCTION`
- `SUPABASE_CAMPUS_AI_FUNCTION`

通常只需要在本地或 CI 的 xcconfig 中设置：

```text
SUPABASE_URL = https://your-project-ref.supabase.co
SUPABASE_PUBLISHABLE_KEY = sb_publishable_xxx
```

`SUPABASE_COMMUNITY_BOOTSTRAP_FUNCTION` 为空时默认使用 `community-bootstrap-user`。
`SUPABASE_EMAIL_LOOKUP_FUNCTION` 为空时默认使用 `campus-email-lookup`，用于把已验证绑定邮箱解析为北林学号；邮箱只作为登录别名，仍需校园网、教务密码和验证码。
`SUPABASE_CAMPUS_AI_FUNCTION` 为空时默认使用 `campus-ai-assistant`。Campus AI 当前支持两种模式：用户自备 DeepSeek API Key 时由 App 直连 `https://api.deepseek.com`；Leafy 托管模式由 App 调用 `campus-ai-assistant` Edge Function，再由服务端使用 Supabase secret 中的 `DEEPSEEK_API_KEYS` 或 `DEEPSEEK_API_KEY` 请求 DeepSeek。用户自备 API Key 仅保存在当前设备 Keychain，不通过 `xcconfig` 或 Info.plist 注入。

## 3. Migration 顺序

按顺序执行 `supabase/migrations/` 下的 migration：

1. `20260423_community_v1.sql`
2. `20260424000000_community_notifications.sql`
3. `20260424000100_community_profile_completion.sql`
4. `20260424000200_remove_profile_edit_lock.sql`
5. `20260424000300_teacher_ratings.sql`
6. `20260425000100_posts_soft_delete_policy.sql`
7. `20260425000200_posts_soft_delete_rpc.sql`
8. `20260425000300_prevent_post_self_likes.sql`
9. `20260425000400_site_announcements.sql`
10. `20260426000100_allow_profile_edits.sql`
11. `20260426000200_community_profile_auth_links.sql`
12. `20260427000100_post_upload_limits.sql`
13. `20260428000100_notifications_feedback_and_comments.sql`
14. `20260428000200_admin_console.sql`
15. `20260428000300_admin_console_pgcrypto_search_path.sql`
16. `20260508000100_admin_analytics.sql`
17. `20260508000200_guideline_1_2_moderation.sql`
18. `20260511000100_shared_timetables.sql`
19. `20260511000200_shared_timetable_digest_search_path.sql`
20. `20260511000300_shared_timetable_accept_ambiguity.sql`
21. `20260512000100_community_notification_realtime.sql`
22. `20260514000100_explicit_data_api_grants.sql`
23. `20260514000200_restore_revoke_community_terms_rpc.sql`
24. `20260514000300_post_favorites.sql`
25. `20260516123040_course_ratings.sql`
26. `20260517020512_catalog_suggestions.sql`
27. `20260524140954_catalog_suggestion_teacher_name.sql`
28. `20260524221717_community_post_pins.sql`
29. `20260525023043_community_feed_optimization.sql`
30. `20260525032702_community_feed_hardening.sql`
31. `20260526144759_campus_weather_cache.sql`
32. `20260528024930_community_polls_v1.sql`
33. `20260528045814_community_poll_lifecycle_v2.sql`
34. `20260528130839_semester_runtime_configs.sql`
35. `20260529133034_postgraduate_sources.sql`
36. `20260605005826_campus_scope_v1.sql`
37. `20260605010100_next_semester_runtime_config.sql`
38. `20260605075924_reactivate_current_semester_runtime_config.sql`
39. `20260605080459_semester_runtime_auto_reconcile_guard.sql`
40. `20260611075655_community_profile_homepage.sql`
41. `20260611141354_community_profile_stats_v1.sql`
42. `20260612042443_community_profile_cover_path.sql`
43. `20260612074957_community_single_pin_category_limit.sql`
44. `20260615124522_image_posts_publish_after_upload_report_hide.sql`
45. `20260615165000_national_calendar_runtime_configs.sql`
46. `20260618132620_school_community_access_v1.sql`
47. `20260623102832_grant_school_community_admin_access.sql`
48. `20260623113617_community_school_membership_flow.sql`
49. `20260625053303_campus_ai_usage_events.sql`
50. `20260627125947_campus_ai_managed_entitlements.sql`
51. `20260701090000_backend_capabilities_v1.sql`
52. `20260702022000_campus_ai_weekly_subscription.sql`
53. `20260704090000_campus_email_lookup.sql`

`20260605005826_campus_scope_v1.sql` 会建立 `campuses` 表，并把社区、共享课表、运营内容、学期配置等核心表补上 `campus_id`。当前只 seed `bjfu`，但 RLS、profile 绑定和 Feed RPC 已按校园隔离。

这些 migration 覆盖：

- `profiles`
- `campuses`
- `profile_auth_links`
- `posts`
- `post_images`
- `comments`
- `post_likes`
- `post_favorites`
- `community_post_pins`
- `community_notifications`
- `community_notification_settings`
- `timetable_snapshots`
- `timetable_invites`
- `timetable_share_members`
- `site_announcements`
- `site_announcement_reads`
- `feedback_submissions`
- `teachers`
- `teacher_ratings`
- `course_catalog`
- `course_ratings`
- `catalog_suggestions`
- `semester_runtime_configs`
- `admin_users`
- `admin_accounts`
- `admin_sessions`
- `admin_audit_logs`
- 后台只读统计 RPC：`admin_daily_counts`、`admin_activity_heatmap`、`admin_category_mix`、`admin_top_content`
- 社区 Feed RPC：`community_feed_v1`
- 社区热门 RPC：`community_hot_posts_v1`
- `community-images` storage bucket

同时包含 RLS policy、评论数同步、老师评分汇总、发帖频率限制、图片数量限制、禁言限制、软删除 RPC、后台管理函数、运营统计 RPC、审计逻辑和 Data API 显式授权。后台统计 RPC 只 grant 给 `service_role`，前端仍通过 `admin-community` Edge Function 读取。

`community_post_pins` 用于社区运营置顶。iOS App 只能读取当前校园内有效、且目标帖子仍为 `published` 的置顶记录；置顶、取消置顶和优先级调整只能通过后台 Edge Function 使用 `service_role` 执行。`community_feed_v1` 会合并当前校园的有效置顶和最新帖子，按是否置顶、优先级、开始时间、发帖时间排序；后台的客户端 Feed 预览和 iOS 社区页使用同一排序语义。`community_hot_posts_v1` 只读取当前校园近 7 天已发布帖子，按 `评论数 * 3 + 点赞数 * 2` 和发帖时间返回最多 10 条热门帖子。

### Data API 授权约定

MyLeafy 不依赖 Supabase 对 `public` schema 新表的自动 Data API 暴露。`20260514000100_explicit_data_api_grants.sql` 会撤销 repo 管理表、序列和函数的旧默认权限，再按 `authenticated` 与 `service_role` 的真实调用面显式授权；`anon` 不持有表权限，App 的匿名登录用户通过 Supabase Auth 会话按 `authenticated` role 访问。

以后新增任何 `public` 表、序列或 Data API/RPC 函数时，必须在同一个 migration 中同时写清：

- `grant`：只授予该对象实际需要的角色和操作。
- `alter table ... enable row level security`。
- 对应 RLS policy；函数没有 RLS，必须用 `grant execute` 控制可调用角色。

## 4. Edge Functions

当前函数：

- `community-bootstrap-user`
- `community-feed`
- `campus-email-lookup`
- `campus-request`
- `campus-weather`
- `campus-ai-assistant`
- `campus-ai-entitlement`
- `app-store-server-notifications`
- `share-preview`
- `admin-login`
- `admin-me`
- `admin-logout`
- `admin-community`
- `admin-list-announcements`
- `admin-publish-announcement`
- `admin-update-announcement`

部署示例：

```bash
supabase functions deploy community-bootstrap-user
supabase functions deploy community-feed
supabase functions deploy campus-email-lookup
supabase functions deploy campus-request
supabase functions deploy campus-weather
supabase functions deploy campus-ai-assistant
supabase functions deploy campus-ai-entitlement
supabase functions deploy app-store-server-notifications
supabase functions deploy share-preview
supabase functions deploy admin-login
supabase functions deploy admin-me
supabase functions deploy admin-logout
supabase functions deploy admin-community
supabase functions deploy admin-list-announcements
supabase functions deploy admin-publish-announcement
supabase functions deploy admin-update-announcement
```

如果当前目录没有 link 项目，使用 `--project-ref` 显式指定目标项目。

不要手动设置 `SUPABASE_URL`、`SUPABASE_ANON_KEY`、`SUPABASE_SERVICE_ROLE_KEY`、`SUPABASE_DB_URL` 这些 Supabase 保留环境变量；托管 Edge Functions 会自动注入。

### Leafy AI 托管服务

`campus-ai-assistant` 要求调用方携带有效 Supabase Auth JWT。函数以 `text/event-stream` 返回 Leafy 归一化后的 `quota` / `delta` / `reasoning_delta` / `done` / `error` 事件，内部使用 DeepSeek Chat Completions `stream: true` 生成 Markdown 回复；不保存 prompt 或 response 正文。`private.campus_ai_usage_events` 只记录用户、校园、模型、状态、字符数、token、估算成本和错误码，用于额度、限流与排障。

Leafy 托管模式依赖三个函数：

- `campus-ai-assistant`：校验 Supabase Auth 和 App Store 安装记录，预约额度，调用 DeepSeek，并完成用量记录。
- `campus-ai-entitlement`：App 购买、恢复购买或刷新额度时调用，校验 AppTransaction JWS 和可选订阅 Transaction JWS，同步 `private.campus_ai_entitlements`。
- `app-store-server-notifications`：接收 App Store Server Notifications，处理续订、过期、退款和撤销等状态变更。

部署前需要设置：

```bash
supabase secrets set DEEPSEEK_API_KEYS='["sk-...", "sk-..."]'
supabase secrets set APP_STORE_BUNDLE_ID=com.isaachuo.leafy
supabase secrets set APP_STORE_APP_APPLE_ID=...
supabase secrets set APP_STORE_SERVER_ENVIRONMENT=Sandbox
supabase secrets set APPLE_ROOT_CERTIFICATES_BASE64='["..."]'
```

`campus-ai-assistant` 兼容旧的 `DEEPSEEK_API_KEY`，也支持 `DEEPSEEK_API_KEY_1` 到 `DEEPSEEK_API_KEY_10`。推荐使用 `DEEPSEEK_API_KEYS` JSON 数组；函数会按顺序尝试，遇到网络错误、401/403、429 或 5xx 会在开始流式输出前切到下一个 key。

`APP_STORE_SERVER_ENVIRONMENT` 在 TestFlight / Sandbox 验证时设为 `Sandbox`，生产发布前改为 `Production`。`APPLE_ROOT_CERTIFICATES_BASE64` 是 Apple Root Certificates 的 Base64 数组 JSON；不要提交到仓库。

App Store Connect 侧需要在 App Store Server Notifications 中配置 Sandbox Server URL：

```text
https://<project-ref>.supabase.co/functions/v1/app-store-server-notifications
```

自动续订订阅商品必须创建在 Bundle ID `com.isaachuo.leafy` 对应的 App 下，Product ID 必须和代码一致：

```text
com.isaachuo.leafy.ai.weekly
```

周订阅周期为 1 周，当前 App 文案和后端额度按 `50 次/周` 处理。如果 App 内显示“价格未读取”或 StoreKit 没有返回商品，优先检查 App Store Connect 中 Paid Apps Agreement、税务、银行信息、订阅组、商品价格、地区、本地化和商品状态。DeepSeek 或 Supabase secrets 未配置不会影响 StoreKit 价格读取，但会影响额度同步和托管问答。

`admin-community` 承接运营后台的数据读取和受控写操作，包括总览趋势、帖子/评论审核、帖子置顶和取消置顶、客户端 Feed 预览、用户禁言、反馈处理、公告、教师、评分、学期运行配置、管理员和审计日志。总览趋势请求示例：

```json
{
  "action": "overview",
  "params": { "days": 30, "timezone": "Asia/Shanghai" }
}
```

`days` 会归一到 `7`、`30` 或 `90`。响应中的 `analytics` 包含每日趋势、活跃热力、分类分布、热门帖子、反馈老化、教师评分分布和审核压力。`bulkModeratePosts`、`bulkModerateComments`、`pinPost`、`unpinPost`、`previewCommunityFeed`、`getProfile` 也通过 `admin-community` 暴露；批量写操作和置顶操作继续写入 `admin_audit_logs`。

## 5. 客户端能力

iOS 客户端入口：

- `leafy/Services/Supabase/LeafySupabase.swift`
- `leafy/Services/Supabase/CommunityService.swift`
- `leafy/Services/Supabase/CommunitySessionManager.swift`
- `leafy/Features/Discover/CommunityViews.swift`
- `leafy/Features/Discover/DiscoverFeatureViews.swift`
- `leafy/Features/Profile/ProfileView.swift`

当前已接能力：

- Supabase client 初始化。
- 匿名会话恢复和创建。
- 教务学号 bootstrap。
- 社区 profile 读取和编辑。
- 头像上传。
- 邮箱验证绑定。
- 帖子列表。
- 发纯文本帖子。
- 发带图片帖子。
- 帖子详情。
- 评论列表。
- 发表评论。
- 点赞 / 取消点赞。
- 删除自己的帖子。
- 删除自己的评论。
- 我的发帖。
- 我的点赞。
- 我的评论。
- 评论和点赞通知。
- 站内公告。
- 通知静音设置。
- 意见反馈。
- 老师列表搜索。
- 老师评分详情。
- 提交或更新 1 到 5 星评分。
- 手动发布共享课表快照。
- 生成 7 天过期、单次接受的邀请码。
- 接受、查看、撤销和移除共享课表。

## 6. 数据规则

社区 profile：

- `edu_id` 与教务学号绑定并唯一。
- `bound_email` 只保存已验证邮箱，可作为北林登录页的学号别名；`pending_bound_email` 只表示待验证，不能用于登录。
- 昵称必填。
- 头像、专业、年级可选。
- 同一个教务学号可在多个匿名 Supabase `auth.uid()` 间复用同一个 profile。

帖子和评论：

- 发帖、评论、点赞前必须完成社区资料。
- 每小时发帖上限由数据库触发器限制。
- 单条帖子图片数由数据库触发器限制。
- 不能点赞自己的帖子。
- 评论当前只支持一级评论。
- 删除使用软删除或状态更新，不直接暴露普通用户硬删能力。

图片：

- `community-images` bucket 保持私有。
- 客户端通过 signed URL 读取图片。
- 图片路径按用户命名空间隔离。

评教：

- 老师名录在 `teachers` 表。
- 每个用户对每位老师最多一条评分。
- 星级只能是 1 到 5。
- 普通用户只能新增或更新自己的评分，不能删除评分。
- 老师平均分、评分数和 1 到 5 星分布由 trigger 汇总。

评课：

- 公选课课程库在 `course_catalog` 表，第一版由后台导入和维护。
- 课程评分在 `course_ratings` 表。
- App 里的“缺失课程”建议写入 `catalog_suggestions`，其中 `teacher_name` 仅供后台审核，不改变 `course_catalog` 的课程唯一性。
- 每个用户对每门课最多一条评分。
- 星级只能是 1 到 5，暂不支持文字评价。
- 普通用户只能读取已发布课程、新增或更新自己的评分，不能删除评分。
- 课程平均分、评分数和 1 到 5 星分布由 trigger 汇总。

共享课表：

- 本地 SwiftData 课表仍是权威数据源。
- 首次发布需要用户在 App 内手动触发；发布后，课表刷新或全量同步成功时会自动更新已发布的共享快照。
- 快照只包含课程名、老师、地点、周次、节次、学期和发布时间，不包含成绩、考试、备注、提醒或收藏。
- 邀请码明文只在客户端生成后临时展示，数据库仅保存 SHA-256 hash。
- 邀请码 7 天过期且只能被一个用户接受。
- 共享关系是单向只读，分享者可随时撤销查看权限或停止共享；查看者也可移除对方课表。

## 7. 新学期切换操作

学期运行配置存放在 `semester_runtime_configs`。iOS App 的兜底顺序是：远程 active 配置、上次成功配置缓存、App 内置默认配置。远程失败不能阻断课表刷新；如果教务刷新失败，App 继续显示本地旧缓存并保留失败原因。

切换前准备：

1. 在 Supabase SQL Editor 手动执行 `supabase/migrations/20260528130839_semester_runtime_configs.sql`。该 migration 会 seed 当前学期 `2025-2026-2` 为 active，不会提前切到下学期。
2. 部署新版 `admin-community` Edge Function，让后台 action 能读取和写入学期运行配置。
3. 向学校教务或研究生系统确认下学期真实值：`semesterID`、`semesterStartDate`、`supportedWeeks`、`graduateTimetableTermCode`。不要在代码里猜这些值。
4. 校历图片仍由 App 资源手动替换；`calendarEvents` 只放假期、停课等需要参与 App 日期逻辑的结构化事件。
5. 可以提前创建下学期记录，但必须保持 `isActive = false`。只要 active 仍是当前学期，当前学期课表、考试、空教室和共享课表分区不会受影响。

后台 action 示例：

```json
{
  "action": "upsertSemesterRuntimeConfig",
  "params": {
    "semesterID": "2026-2027-1",
    "semesterStartDate": "2026-09-07",
    "supportedWeeks": 20,
    "graduateTimetableTermCode": "47",
    "calendarEvents": [
      {
        "id": "national-2026",
        "title": "国庆",
        "startDateString": "2026-10-01",
        "endDateString": "2026-10-07",
        "kind": "holiday"
      }
    ],
    "isActive": false
  }
}
```

正式切换时，将下学期记录设为 active。若直接在 SQL Editor 操作，先停用旧 active，再激活新学期，避免触发“同一时间只能有一个 active 学期”的唯一索引：

```sql
begin;

update public.semester_runtime_configs
set is_active = false
where is_active = true;

insert into public.semester_runtime_configs (
  semester_id,
  semester_start_date,
  supported_weeks,
  graduate_timetable_term_code,
  calendar_events,
  is_active
)
values (
  '2026-2027-1',
  date '2026-09-07',
  20,
  '47',
  '[]'::jsonb,
  true
)
on conflict (semester_id) do update
set semester_start_date = excluded.semester_start_date,
    supported_weeks = excluded.supported_weeks,
    graduate_timetable_term_code = excluded.graduate_timetable_term_code,
    calendar_events = excluded.calendar_events,
    is_active = true;

commit;
```

切换后验收：

1. 在 SQL Editor 确认只返回一条 active 配置：

```sql
select semester_id, semester_start_date, supported_weeks, graduate_timetable_term_code, is_active
from public.semester_runtime_configs
where is_active = true;
```

2. 打开 App 或从后台回到前台，让 App 拉取远程配置。手动刷新课表和“同步全部教务数据”会强制刷新配置。
3. 本科课表继续走原教务课表链路；周次、日期、共享课表 `semester_id` 使用新配置。
4. 研究生课表确认请求使用新的 `graduateTimetableTermCode`。
5. 考试安排和空教室确认请求参数里的 `xnxqid` / `xnxqh` 使用新的 `semesterID`。
6. 成绩、教学计划、培养方案仍保持现有全量抓取，不按当前学期强制过滤。
7. 发布或刷新一次共享课表，确认新快照落到新学期分区，旧学期共享快照保留历史记录。

回滚方式：用同一套 action 或 SQL 把上一个学期重新设为 active。App 下次启动、回前台、手动刷新课表或同步全部教务数据时会重新读取配置；紧急情况下让用户杀掉 App 后重开，可以避开普通前台刷新节流。

## 8. 教师名录导入

当前不在 App 或 migration 中抓取教师名录。先手动整理 CSV 后导入 Supabase。

模板：`supabase/teacher_import_template.csv`

格式：

```csv
name,unit
张三,信息学院
李四,园林学院
```

导入后进入 App 的 `学业 -> 评教`，下拉刷新或重新进入页面即可看到老师列表。

## 9. 公选课课程库导入

当前不在 App 中实时抓取全校公选课。先整理 CSV 后导入 Supabase 的 `course_catalog` 表。

模板：`supabase/course_import_template.csv`

格式：

```csv
name,unit,category,credit
森林生态学导论,林学院,公选课,2.0
审美艺术导论,艺术设计学院,公选课,2.0
```

建议先从教务教学计划、成绩页课程类别和运营人工校对结果合并候选数据，再按 `(name, unit, category)` 去重导入。导入后进入 App 的 `学业 -> 评课` 即可搜索课程并评分。

App 提交的缺失课程建议会额外收集 `teacher_name` 帮助后台判断课程是否真实存在；审核通过时仍只按 `name,unit,category,credit` 写入 `course_catalog`。

## 10. 管理员初始化

第一位超级管理员通过数据库连接创建，脚本只读取环境变量，不提交密码：

```bash
export SUPABASE_DB_URL='postgresql://...'
export ADMIN_USERNAME='admin'
export ADMIN_PASSWORD='replace-with-a-long-password'
export ADMIN_DISPLAY_NAME='Leafy Admin'
bash supabase/scripts/create-admin-account.sh
```

后台使用说明见 [运营后台](admin-console.md)。

## 11. 联调顺序

1. 启用 Anonymous sign-ins。
2. 启用 Email provider、Email OTP / Magic Link 和邮箱密码登录。
3. 执行所有 migration。
4. 部署 Edge Functions。
5. 配置 iOS 工程的 Supabase URL 和 publishable key。
6. 配置阿里云 DirectMail 自定义 SMTP，并确认 QQ、163、Gmail 都能收到验证码。
7. 在 iOS App 的社区邮箱验证入口测试验证码投递，确认 QQ、163、Gmail 都能收到验证码。
8. 先登录北林教务，再进入 `社区`。
9. 检查 `profiles` 和 `profile_auth_links` 是否生成记录。
10. 完善资料后测试发帖、图片、评论、点赞和收藏。
11. 测试通知、公告和意见反馈。
12. 导入教师 CSV 后测试评教搜索和评分。
13. 测试邮箱验证绑定。
14. 在后台 `帖子` 页执行一次置顶和客户端 Feed 预览，确认 iOS 社区页展示置顶标识。
15. 执行学期运行配置切换演练：创建 inactive 下学期配置、切 active、刷新课表/考试/空教室/共享课表，再切回当前学期。

## 12. 当前约束

- Supabase 不反查教务系统。
- 当前 active 学期由 `semester_runtime_configs` 控制；新学期开学日期、研究生 `termcode` 和结构化校历事件需要运营手动填写。
- 共享课表不会代替本地课表缓存；只有已经发布过共享课表的用户，后续课表刷新成功时才会自动更新共享快照。
- 教师名录需要手动导入。
- 评论不支持多级回复。
- 评教不支持文字评价。
- 帖子收藏存储在 Supabase；自习室收藏仍是本地 SwiftData 数据。
- 后台高权限操作必须经 Edge Functions，不允许把 `service_role` 暴露给前端或 iOS App。
