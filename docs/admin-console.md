# MyLeafy 运营后台

MyLeafy 运营后台是与官网同仓部署的受保护 Web 应用，生产路由为 `/admin`。它用于管理 MyLeafy 自有的社区、目录、配置和运营数据，不访问用户的学校密码，也不代替学校教务后台。

后台前端位于 `site/src/admin/`，使用 React-admin 5、MUI、ECharts、Vite 与 TypeScript。管理 API 由 Cloudflare Pages Functions 代理到 Supabase Edge Functions。

## 1. 架构与信任边界

![运营后台安全链路](diagrams/admin-security.svg)

图源：[D2 source](diagrams/admin-security.d2)

后台使用三层安全边界：

1. **浏览器 UI**：渲染资源、表单和确认交互，不持有服务端密钥。
2. **Cloudflare Pages Functions**：管理 HttpOnly Cookie，校验同源、CSRF 和请求格式，并代理请求。
3. **Supabase Edge Functions**：执行管理会话验证、RBAC、校园范围、参数校验、数据访问与审计。

数据库和 Storage 是最终数据层。浏览器不能绕过代理直接以管理员身份调用 Data API。

## 2. 请求链路

浏览器只访问同域管理接口：

```text
POST /api/admin/login
GET  /api/admin/me
POST /api/admin/logout
POST /api/admin/actions
POST /api/admin/export
```

### 2.1 登录

1. 管理员在 `/admin` 提交凭据。
2. Pages Function 校验来源、请求大小和代理配置。
3. 请求转发至 `admin-login` Edge Function。
4. Edge Function 执行限流、账号状态和密码验证。
5. 成功后，Pages Function 将管理会话写入 `leafy_admin_session` Cookie。

Cookie 属性：

- `HttpOnly`
- `Secure`
- `SameSite=Strict`
- `Path=/api/admin`
- 有限会话时长

响应不把 token 返回给 JavaScript，也不写入 `localStorage` 或 `sessionStorage`。启动时会清理旧版本遗留的浏览器 token。

### 2.2 认证请求

- 浏览器自动携带 HttpOnly Cookie。
- 客户端发送固定 CSRF header。
- Pages Function 校验 `Origin`、方法、内容类型和 CSRF。
- 代理为每次请求生成或转发 request ID。
- Edge Function 验证管理会话、角色和校园范围。
- 高风险操作记录结果、持续时间和审计状态。

只有确定的未认证响应才清理本地管理员状态。权限不足、网络故障或服务端错误不得被统一误处理为“退出登录”。

## 3. 角色模型

| 角色 | 典型权限 | 明确限制 |
|---|---|---|
| `viewer` | 查看总览、列表、详情和受限搜索 | 不写入、不批量操作、不导出 |
| `operator` | 日常内容运营、公告、反馈、目录维护和允许的导出 | 不管理超级管理员和高敏感系统设置 |
| `super_admin` | 全部运营能力、管理员/会话管理和敏感操作 | 仍受审计、参数和校园范围约束 |

角色只定义能力上限，实际权限还受：

- 当前管理员状态。
- 资源和 action 白名单。
- 对象当前状态。
- 服务端额外确认或审计要求。

页面顶部的学校选择器是查询与操作范围，不是管理员授权边界。当前版本不提供多学校管理员 ACL；若未来需要按学校隔离管理员权限，必须作为独立的服务端授权能力设计，不能依赖前端选择器。

前端隐藏按钮只改善体验，不构成授权。所有权限必须在 Edge Function 重新判断。

## 4. 资源模型

后台资源由 `site/src/admin/registry.ts` 与相关 contracts 定义，并由 data provider 映射到服务端 action。

主要领域：

### 4.1 总览与手册

- 社区与业务关键指标。
- 待处理反馈、内容和异常概览。
- 常见运营流程、权限边界和处置说明。

总览用于发现问题，不把复杂写操作塞进指标卡片。

### 4.2 社区内容

- 帖子、评论、投票和互动详情。
- 全局/分类置顶与客户端 Feed 预览。
- 批量下架、恢复和必要的内容状态操作。
- 举报、通知、公告和反馈处理。

反馈状态口径固定为：`open` 是未查看待处理，`reviewed` 是已查看但仍待处理，`closed` 才是处理完成。总览、逾期统计和列表必须使用同一口径。

Feed 预览应调用与 iOS 客户端一致的服务端排序规则，而不是在浏览器中模拟另一套排序。

### 4.3 用户与访问

- profile 与校园范围内的必要业务信息。
- 禁言、解除、访问状态和相关审计。
- 默认不在搜索摘要中返回邮箱、学号和联系方式。

管理员需要定位身份时，使用权限明确的详情或受控搜索，不把敏感字段加入所有列表。

### 4.4 目录与评价

- 教师、课程、菜品等目录。
- 用户提交的缺失目录建议。
- 评分聚合和异常数据检查。
- 导入、审核、发布与停用。

目录修改应保留来源、校园和状态，避免直接覆盖导致历史评分指向不明。

### 4.5 校园与运行配置

- 校园和学校申请。
- 学期运行配置。
- 国家/校园日历配置。
- 后端 capability 和兼容状态。

active 配置切换使用原子 action，不通过多个不相关表单请求拼接。

### 4.6 管理系统

- 管理员账号与角色。
- 管理会话与撤销。
- 登录尝试和异常访问。
- 审计日志与受控导出。

这些资源只对具有对应权限的管理员显示和返回。

## 5. 前端结构

```text
site/src/admin/
├── AdminConsole.tsx          # 后台入口与资源组装
├── registry.ts               # 资源定义
├── contracts.ts              # API 与资源契约
├── components/               # 登录、布局和共享组件
├── dashboard/                # 指标与 ECharts 按需运行时
├── providers/                # auth、session、client、data provider
├── resources/                # 列表、详情、编辑与复合页面
└── *.test.ts(x)              # 单元和契约测试
```

后台通过 `lazy()` 从公开网站独立加载，避免把 React-admin、MUI 和 ECharts 全部加入官网首屏包。ECharts 使用模块化运行时，页面只注册实际图表类型。

## 6. 前端数据契约

React-admin 的 list/getOne/create/update/delete 等行为由 data provider 转换成受控 action。服务端不接受任意表名和任意 SQL 式参数。

### 6.1 列表

- 分页允许 20、50、100。
- 筛选、排序和页码写入 URL，支持刷新和分享当前运营视图。
- 服务端验证可筛选、可排序字段。
- 数据响应同时返回稳定 ID 和总数。
- 搜索输入有长度和速率限制。
- 只有服务端真实支持搜索或排序的资源、字段才显示对应控件；不允许展示无效控件。

### 6.2 写操作

- 使用明确 action 名称与参数 schema。
- 新增与编辑使用独立表单能力；没有 create action 的资源不得显示新增入口。
- 前端不做高风险乐观更新。
- 删除、禁言、审核、会话撤销和配置切换使用自定义确认对话框。
- 对话框写清对象、影响与可逆性；仅业务确实需要时才要求填写原因。
- 成功后只刷新受影响资源和指标。

### 6.3 错误

UI 至少区分：

- `401`：会话无效，回到登录。
- `403`：已登录但权限或范围不足，保留会话。
- `409`：状态冲突或并发修改，要求刷新。
- `422`：参数或业务校验失败，关联到表单。
- `429`：频率限制，说明可重试时间。
- `5xx` / 网络错误：保留上下文并展示 request ID。

错误界面不显示 SQL、堆栈、token 或内部 secret 名值。

## 7. 全局搜索

全局搜索用于快速定位运营对象，不是数据库任意查询入口。

- 查询长度 2–100 字符。
- 按服务端白名单搜索帖子、评论、用户、反馈、目录和公开信息等资源。
- 每类和总结果数都有上限。
- 继承当前角色与校园范围。
- 摘要不返回邮箱、联系方式、学号或其他高敏感字段。
- 点击结果后进入有权限的详情页；对象已不可用时显示统一状态。

## 8. CSV 导出

导出请求只接受服务端定义的 `resource`、`filters` 和可选 `sort`：

- 资源和字段使用白名单。
- 服务端再次验证角色和校园范围。
- 单次导出有行数上限。
- 输出 UTF-8 BOM，便于常见表格软件识别中文。
- 对以 `= + - @` 等字符开头的单元格做公式注入防护。
- 审计记录资源、范围、筛选和实际行数。
- 不提供“导出任意 SQL”或“导出整库”。

涉及敏感数据的导出仅开放给必要角色，并应优先减少字段，而不是依赖导出后人工删除。

## 9. 环境变量

Cloudflare Pages 的 Preview 与 Production 分别配置：

```text
SUPABASE_URL=https://<project-ref>.supabase.co
SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
ADMIN_PROXY_SECRET=<at-least-32-random-bytes>
```

同一 `ADMIN_PROXY_SECRET` 作为 Supabase Edge Function secret：

```bash
supabase secrets set ADMIN_PROXY_SECRET='<same-random-secret>'
```

本地 Pages Functions 开发使用 `site/.dev.vars`，此文件不得提交：

```text
SUPABASE_URL=...
SUPABASE_PUBLISHABLE_KEY=...
ADMIN_PROXY_SECRET=...
```

禁止使用 `VITE_` 前缀暴露管理代理 secret。Vite 以 `VITE_` 开头的变量会进入浏览器 bundle。

## 10. 本地开发

### 10.1 纯前端

```bash
cd site
npm ci
npm run dev
```

适合官网开发和 mock API 下的后台界面开发。Vite dev server 不包含真实 Pages Functions 管理代理。

### 10.2 完整代理链路

```bash
cd site
npm ci
npm run dev:pages
```

该命令先构建网站，再使用 Wrangler 启动 Pages 环境。运行前配置 `site/.dev.vars`，并确保对应 Supabase migration、函数和管理员账号已建立。

### 10.3 初始化首位管理员

仓库脚本从环境变量读取数据库连接和账号信息：

```bash
export SUPABASE_DB_URL='postgresql://...'
export ADMIN_USERNAME='admin'
export ADMIN_PASSWORD='replace-with-a-long-unique-password'
export ADMIN_DISPLAY_NAME='Leafy Admin'
bash supabase/scripts/create-admin-account.sh
```

脚本和文档中只使用占位值。密码和数据库 URL 不得写入 shell history、提交记录或 Issue。

## 11. 数据库与函数

管理链路依赖：

- 管理员、会话、登录尝试和审计相关 migration。
- `admin-login`、`admin-me`、`admin-logout`。
- `admin-community` 通用管理 action。
- `admin-export` 受控导出。
- 公告等独立兼容函数。
- `_shared/admin-*` 权限、CSV 与核心工具。

基本部署：

```bash
supabase db push
supabase functions deploy admin-login
supabase functions deploy admin-me
supabase functions deploy admin-logout
supabase functions deploy admin-community
supabase functions deploy admin-export
```

部署顺序遵循：前向 migration → 向后兼容的 Edge Functions → Cloudflare 变量和代理 → Web 静态资源。不要先发布依赖尚未存在 action 的前端。

本轮后台可靠性修复不包含数据库 migration。发布 `admin-community` 后再发布 Web 静态资源；发布后只读检查总览、列头、筛选、中文状态和权限按钮。真实删除只允许使用明确指定的可废弃记录，并核对对应审计日志。

## 12. 安全要求

### 浏览器

- 不存储管理 token。
- 所有写请求使用同域、CSRF header 和 JSON content type。
- 不使用原生 `prompt` / `confirm` 承载高风险操作。
- 不把权限不足资源短暂渲染后再隐藏。

### Cloudflare 代理

- 校验 Origin、方法、请求大小和 CSRF。
- Cookie 设置 HttpOnly、Secure、SameSite 和受限 Path。
- 代理 secret 只存在于服务端环境。
- 日志不记录密码、Cookie、Authorization 和响应敏感正文。

### Edge Functions

- 管理 session 独立于普通 App session。
- 每个 action 进行角色、校园、资源、字段与状态校验。
- 敏感读和所有高风险写记录审计。
- 登录限流按账号与网络维度组合，并避免用户枚举。
- 审计失败不能被伪装成成功；需要按 action 风险选择拒绝或显式标记。

### 数据库

- 普通用户 RLS 不因后台存在而放宽。
- 管理表不授予 anon/authenticated 直接访问。
- 登录尝试等安全数据只允许服务端角色访问。
- migration 保持前向兼容，危险删除在兼容窗口后执行。

## 13. 交互规范

- 运营页面优先支持可重复、可审计的操作，不追求消费级动画。
- 所有列表保留筛选上下文，详情返回时不丢失位置。
- 日期区间使用浏览器时区偏移计算“开始日包含、结束日次日排除”，保证管理员所见结束当天完整计入。
- 批量操作先显示选择数量和影响范围。
- 不可逆操作要求输入原因或二次确认。
- 可逆操作明确恢复入口和状态。
- 处理中禁用重复提交，不做高风险乐观更新。
- 成功提示包含对象和结果，不只写“操作成功”。
- 失败提示保留表单与筛选，并提供 request ID。

## 14. 测试

### Web

```bash
cd site
npm run typecheck
npm test
npm run build
npm run test:e2e
```

重点覆盖：

- auth provider 的 401/403 分支。
- HttpOnly session 下的启动、退出和过期恢复。
- registry 与 contract 一致性。
- data provider 的分页、筛选、错误映射和缓存刷新。
- 危险操作确认与权限隐藏。
- 浏览器 storage 中不存在管理 token。

### Edge Functions 与数据库

```bash
deno check supabase/functions/admin-login/index.ts \
  supabase/functions/admin-me/index.ts \
  supabase/functions/admin-logout/index.ts \
  supabase/functions/admin-community/index.ts \
  supabase/functions/admin-export/index.ts

deno test --allow-read \
  supabase/functions/_shared/admin-core.test.ts \
  supabase/functions/_shared/admin-permissions.test.ts \
  supabase/functions/_shared/admin-csv.test.ts \
  supabase/functions/admin-community/admin-community.contract.test.ts

bash supabase/tests/verify_admin_security_runtime_migration.sh
supabase test db
```

测试必须覆盖允许与拒绝路径、跨校园访问、角色降级、过期会话、参数越界、CSV 公式注入和审计记录。

## 15. 变更检查清单

新增后台资源或 action 时：

1. 定义资源、角色和校园范围。
2. 在服务端建立参数 schema 与字段白名单。
3. 明确审计内容和可逆性。
4. 更新 contracts、registry 和 data provider。
5. 添加允许与拒绝路径测试。
6. 检查导出和全局搜索是否应该包含该资源。
7. 确认前端不获得新 secret 或直接数据库权限。
8. 更新本文和 [Supabase 接入](supabase.md)。
