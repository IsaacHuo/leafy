# 贡献指南

MyLeafy 采用轻量协作流程：先用 Issue 说明问题或需求，从 `main` 创建分支，提交 PR，并在相关检查通过后合并。

## 分支命名

- `feature/<short-slug>`：新功能
- `fix/<short-slug>`：缺陷修复
- `docs/<short-slug>`：文档变更
- `chore/<short-slug>`：配置、依赖或脚本维护
- `refactor/<short-slug>`：不改变行为的重构
- `test/<short-slug>`：测试补充
- `release/<version>`：发布准备
- `codex/<short-slug>`：Codex 生成或整理的工作分支

## 提交 Issue

Bug 至少包含：复现步骤、预期行为、实际行为和运行环境。功能建议应说明用户问题、最小可用方案、数据来源和影响范围。

禁止在 Issue 中提交密码、token、Cookie、真实学生信息、生产数据库内容或内部发布凭据。

## 提交 PR

PR 应保持单一目标，并在正文说明：

1. 解决了什么问题。
2. 改动了哪些边界或行为。
3. 如何验证。
4. 是否涉及数据、权限、配置或部署。
5. 是否同步更新了文档与图表。

合并前检查：

- [ ] 关联对应 Issue；纯文档或很小的维护变更可例外。
- [ ] 运行与改动范围匹配的构建、测试或模拟器验证。
- [ ] UI 改动检查深色模式、动态字体与主要状态。
- [ ] 没有提交 `.env`、本地 xcconfig、证书、profile、token 或 Xcode 用户状态。
- [ ] 行为、schema、管理 action 或部署方式变化时同步更新 `docs/`。
- [ ] D2 图表变更同时提交源文件与渲染后的 SVG。

## 设计与架构要求

- 新页面优先复用主题令牌与系统组件。
- 新校园差异进入 capability 或适配器，不散落学校判断。
- 学校 HTML、Cookie 和解析规则限制在外部系统边界。
- 新的 Supabase 数据表或 action 必须定义 RLS、校园范围和拒绝路径测试。
- 高风险管理能力必须服务端授权并写入审计。

完整规范见仓库[贡献文档](https://github.com/IsaacHuo/leafy/blob/main/docs/contributing.md)。


