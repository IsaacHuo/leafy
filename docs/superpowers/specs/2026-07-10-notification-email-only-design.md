# 通知邮箱绑定设计

## 目标

北林学生可在“我的 → 支持 → 绑定邮箱”验证一个通知邮箱，供管理后台发送服务故障、数据库异常和重要运营通知。邮箱不参与北林登录；北林入口始终使用学号、教务密码、教务验证码和可访问教务系统的网络。

## 身份边界

- `profiles.bound_email` 是管理后台可用的已验证通知地址，`pending_bound_email` 不能用于通知或登录。
- Supabase Auth 仅用于证明当前校园账号控制待绑定邮箱，不为北林入口设置邮箱密码，也不把邮箱解析为学号。
- 通用入口已有的 Supabase 邮箱账号流程保持不变，与北林通知邮箱功能分开。

## 验证流程

1. 已完成北林教务登录的用户输入邮箱。
2. 首次请求调用 Auth email change；同一待验证邮箱重发时调用 Auth `resend(type: .emailChange)`，避免继续使用旧令牌。
3. 邮件只显示 8 位 `{{ .Token }}`，不包含确认链接。
4. App 只接受恰好 8 位数字；`verifyOTP(type: .emailChange)` 成功后才写入 `bound_email` 并清空待验证状态。
5. 已绑定邮箱更换期间，旧 `bound_email` 继续用于通知，直到新邮箱验证成功。

托管 Auth 必须开启 manual linking，让现有匿名社区会话能关联邮箱；必须关闭 secure email change，因为匿名会话没有旧邮箱，绑定时只需要向新邮箱发送一套验证码。

## 删除邮箱登录别名

- 北林登录页占位恢复为“学号”，直接将学号交给现有教务登录流程。
- 删除 `CampusEmailAliasLoginService`、`SUPABASE_EMAIL_LOOKUP_FUNCTION` 和 `campus-email-lookup` Edge Function。
- 保留已执行的历史 migration，再新增 migration 删除 `lookup_verified_edu_id_by_email(text, text)`，并删除已部署的 Edge Function。
- 所有“登录别名”“已绑定邮箱登录”等用户文案和 Supabase 文档同步删除。

## 错误与可观测性

- 空码或不足 8 位时在客户端拦截，不发送无效请求。
- Supabase 返回 `otp_expired` 时提示用户重新发送并使用最新邮件中的验证码。
- Auth 错误日志只记录错误码，不记录邮箱和验证码。

## 验证

- XCTest 覆盖 8 位验证码规范化、完整性判断，以及同一待验证邮箱应走 resend 的决策。
- shell 检查确保邮件模板包含 `{{ .Token }}`、本地 OTP 长度为 8，且不存在确认链接。
- `rg` 检查客户端、配置和文档不再引用邮箱别名解析。
- XcodeBuildMCP 构建 `leafy` scheme，并运行邮箱绑定相关测试。
- 只读复查线上 Auth 设置和 Edge Function 列表；数据库 migration 应成功应用。
