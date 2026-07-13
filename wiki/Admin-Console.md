# 运营后台

MyLeafy 运营后台位于官网项目中，生产路由为 `/admin`。它用于管理 MyLeafy 自有的社区、目录、配置和运营数据，不访问用户学校密码，也不代替学校教务后台。

## 技术栈

- React 18、TypeScript、Vite
- React-admin 5、MUI、ECharts
- Cloudflare Pages Functions
- Supabase Edge Functions、PostgreSQL 与 Storage

## 安全链路

![运营后台安全链路](https://raw.githubusercontent.com/IsaacHuo/leafy/main/docs/diagrams/admin-security.svg)

浏览器只访问同域管理接口；Pages Functions 管理 HttpOnly Cookie、校验同源与 CSRF，并将请求代理到 Edge Functions。服务端再次执行会话、角色、校园范围、参数与审计校验。

## 角色

| 角色 | 典型权限 |
|---|---|
| `viewer` | 查看总览、列表、详情和受限搜索 |
| `operator` | 日常内容运营、公告、反馈、目录维护和允许的导出 |
| `super_admin` | 管理员、会话和敏感配置等高权限操作 |

角色只定义能力上限。资源、对象状态、校园范围和服务端 action 白名单仍会进一步限制权限。

## 本地运行

纯前端或 mock API：

```bash
cd site
npm ci
npm run dev
```

包含 Pages Functions 的完整代理链路：

```bash
cd site
npm ci
npm run dev:pages
```

本地完整链路需要 `site/.dev.vars`：

```text
SUPABASE_URL=https://<project-ref>.supabase.co
SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
ADMIN_PROXY_SECRET=<at-least-32-random-bytes>
```

`ADMIN_PROXY_SECRET` 不得带 `VITE_` 前缀，否则会进入浏览器 bundle。

## 交互与数据约束

- 列表筛选、排序和页码写入 URL。
- 服务端定义可筛选、可排序字段与 action 参数 schema。
- 高风险操作不做乐观更新，必须提供清晰的确认和审计。
- CSV 导出使用字段白名单、行数上限和公式注入防护。
- `401`、`403`、`409`、`422`、`429` 和网络错误分别处理。
- 错误提示可包含 request ID，但不能展示 SQL、堆栈、token 或 secret。

## 验证

```bash
cd site
npm run typecheck
npm test
npm run build
npm run test:e2e
```

完整部署顺序、管理员初始化、资源模型与测试清单见仓库[运营后台文档](https://github.com/IsaacHuo/leafy/blob/main/docs/admin-console.md)。


