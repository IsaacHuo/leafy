# 贡献规范

这个项目的协作流程保持轻量：先开 Issue 说明问题或需求，再从 `main` 拉分支，提交 PR，等 GitHub Actions 通过后合并。

## 分支命名

从 `main` 拉新分支，使用小写短横线或数字：

- `feature/<short-slug>`：新功能
- `fix/<short-slug>`：缺陷修复
- `docs/<short-slug>`：文档变更
- `chore/<short-slug>`：配置、依赖、脚本维护
- `refactor/<short-slug>`：不改变行为的重构
- `test/<short-slug>`：测试补充
- `release/<version>`：发布准备
- `codex/<short-slug>`：Codex 生成或整理的工作分支

示例：`feature/timetable-export`、`fix/admin-login-state`、`docs/supabase-setup`。

## Issue 规范

Bug 使用 Bug report 模板，至少写清楚复现步骤、期望行为、实际行为和环境。功能建议使用 Feature request 模板，说明要解决的问题、最小可用方案和影响范围。

不要在 Issue 里粘贴密码、token、cookie、真实学生个人信息或生产数据库内容。需要说明配置时，只写环境变量名或占位值。

## PR 规范

PR 应该保持小而清晰，标题用一句话说明结果，例如 `Add timetable widget refresh tests`。正文按模板填写 Summary、Linked Issue、Changes 和 Validation。

合并前至少满足：

- PR 关联了对应 Issue，纯文档或很小的维护变更可以例外。
- 本地跑过相关构建或测试；UI 改动看过模拟器、截图或浏览器效果。
- 没有提交 `.env`、本地 xcconfig、证书、profile、服务账号 JSON、Xcode 用户状态或临时脚本。
- 行为、配置或部署方式变化时，同步更新 `docs/`。

## GitHub Actions

PR 和推送到 `main` 会跑基础 CI：

- Repository hygiene：检查 PR 分支名、禁止公开仓库不该跟踪的文件，并扫描明显密钥格式。
- Website build：在 `site/` 执行 `npm ci` 和 `npm run build`。
- Xcode project metadata：在 macOS runner 上执行 `xcodebuild -list -project leafy.xcodeproj`，确认 Xcode 项目结构可解析。

iOS 完整模拟器构建耗时较长，暂时不放入必跑 CI；需要时在本地或单独的 release 分支上运行。
