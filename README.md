# MyLeafy

<p align="center">
  面向高校学习与校园生活的原生 iOS 应用，目前主要服务北京林业大学。
</p>

<p align="center">
  <img src="https://img.shields.io/badge/iOS-17.0%2B-111111?logo=apple" alt="iOS 17.0+">
  <img src="https://img.shields.io/badge/Swift-5.x-F05138?logo=swift&logoColor=white" alt="Swift 5.x">
  <img src="https://img.shields.io/badge/UI-SwiftUI-0A84FF" alt="SwiftUI">
  <img src="https://img.shields.io/badge/backend-Supabase-3FCF8E?logo=supabase&logoColor=white" alt="Supabase">
  <img src="https://img.shields.io/badge/license-CC%20BY--NC--SA%204.0-555555" alt="CC BY-NC-SA 4.0">
</p>

MyLeafy 以课表和学业数据为核心，将教务查询、学习管理、校园社区、共享课表与 AI 辅助整合在一个原生 iOS 客户端中。项目直接连接目标学校的教务系统获取授权数据，并使用 Supabase 承载社区、通知、评分、共享与运营数据。

> 仓库名、Xcode target 与部分内部类型仍使用 `leafy` / `Leafy`。对外产品名称统一为 **MyLeafy**。

![MyLeafy 系统概览](docs/diagrams/system-overview.svg)

图源：[D2 source](docs/diagrams/system-overview.d2)

## 项目能力

| 领域 | 当前能力 |
|---|---|
| 课表 | 周课表、课程详情、时间范围、日程叠加、提醒、分享图、小组件与共享课表 |
| 学业 | 成绩、考试、教学计划、培养方案、空教室、校历、学习空间、体育与职业相关工具 |
| Leafy AI | 基于用户授权的本机学业上下文进行问答，生成报告、清单等可阅读 Artifact |
| 社区 | 帖子、图片、评论、点赞、投票、通知、公告、个人内容与内容分享 |
| 评价 | 教师、课程等结构化评分；数据能力按校园配置开放 |
| 个性化 | 浅色/深色外观、主题色、显示密度、多语言与课表背景 |
| 运营 | 独立 Web 管理后台、角色权限、内容管理、配置管理、审计与受控导出 |

功能是否显示由校园能力配置、用户身份与后端配置共同决定，并非所有入口都会在每个校园环境中开放。

## 设计与架构

MyLeafy 采用原生 iOS 优先、边界清晰和本地可用的工程策略：

- SwiftUI 构建页面与导航，iOS 17 为部署基线；在 iOS 26 上使用受可用性检查保护的系统视觉能力。
- 教务数据通过 `URLSession`、显式 Cookie 管理和 SwiftSoup 解析；课表链路在必要时使用 `WKWebView` 复现浏览器路径。
- SwiftData 保存课表、成绩和用户侧本地数据；页面通过预计算投影与快照降低复杂网格的渲染成本。
- Supabase Auth、PostgreSQL、Storage 与 Edge Functions 承载非教务业务；RLS、校园范围和资源所有权共同约束数据访问。
- Web 运营后台通过 Cloudflare Pages Functions 代理管理请求，管理会话不暴露给浏览器 JavaScript。

详细边界、数据流和依赖方向见[架构说明](docs/architecture.md)。

## 技术栈

| 范围 | 技术 |
|---|---|
| iOS UI | SwiftUI |
| 本地持久化 | SwiftData |
| 教务网络 | URLSession、HTTPCookieStorage、WKWebView |
| HTML 解析 | SwiftSoup |
| 系统服务 | WeatherKit、WidgetKit、Keychain |
| 业务后端 | Supabase Auth、PostgreSQL、Storage、Edge Functions |
| Web 后台 | React 18、React-admin 5、MUI、ECharts、Vite、TypeScript |
| 边缘代理 | Cloudflare Pages Functions |
| 自动化检查 | GitHub Actions、Vitest、Playwright、XCTest |

## 仓库结构

```text
leafy/
├── leafy/                  # iOS 主应用
│   ├── App/                # 应用启动、根导航、主题与生命周期
│   ├── Core/               # 依赖、持久化、校园能力、并发等基础设施
│   ├── Features/           # Auth、Timetable、Community、Discover、Profile
│   ├── Services/           # 教务、Supabase、同步与诊断服务
│   ├── Parsers/            # 教务 HTML 解析
│   └── Shared/             # 跨功能模型与共享组件
├── leafyTests/             # iOS 单元与契约测试
├── leafyWidget/            # Widget 扩展
├── LeafyShareExtension/    # 系统分享扩展
├── supabase/               # migrations、Edge Functions、模板与测试
├── site/                   # 官网、运营后台与 Cloudflare Functions
├── Config/                 # 可提交的配置模板；本地密钥文件不入库
└── docs/                   # 产品、架构、设计与后端文档
```

## 本地运行

### 环境要求

- macOS 与 Xcode 26 或更新版本（项目引用 iOS 26 SDK API，并为 iOS 17–25 提供运行时回退）
- iOS 17.0 或更新版本的模拟器/设备
- Node.js 20.19 或更新版本，或 Node.js 22.12 及更新版本（仅网站与运营后台）
- 可用的目标学校教务账号（验证真实教务链路时需要）
- 自建 Supabase 项目（验证社区、共享与运营能力时需要）

### iOS App

```bash
git clone https://github.com/IsaacHuo/leafy.git
cd leafy

cp Config/Leafy.example.xcconfig Config/Leafy.local.xcconfig
open leafy.xcodeproj
```

在 `Config/Leafy.local.xcconfig` 中配置本地 Supabase URL 与 publishable key，然后选择 `leafy` scheme 运行。真实密钥、本地 xcconfig、证书和描述文件不得提交到仓库。

若只关注不依赖 Supabase 的本地页面，可保留示例配置；社区、共享课表和部分远程能力会进入不可用状态。

### 网站与运营后台

```bash
cd site
npm ci
npm run dev
```

`npm run dev` 适合开发公开网站或使用 mock API 调试后台界面。包含 Cloudflare Pages Functions 的真实代理链路使用：

```bash
npm run dev:pages
```

环境变量与安全边界见[运营后台](docs/admin-console.md)。

### Supabase

仓库中的 `supabase/` 包含数据库迁移、Edge Functions、邮件模板、导入模板与验证脚本。新环境应从空项目按迁移顺序建立 schema，并按需部署函数：

```bash
supabase link --project-ref <project-ref>
supabase db push
supabase functions deploy community-bootstrap-user
```

不要在 iOS、网站前端或公开配置中使用 `service_role`。完整说明见[Supabase 接入](docs/supabase.md)。

## 文档

| 文档 | 适用读者 | 内容 |
|---|---|---|
| [项目总览](docs/overview.md) | 所有人 | 产品定位、能力范围、数据边界与限制 |
| [架构说明](docs/architecture.md) | iOS/后端开发者 | 分层、依赖、教务链路、本地存储与系统边界 |
| [App 产品设计](docs/app-design.md) | 产品与客户端开发者 | 信息架构、核心流程、页面状态与产品原则 |
| [UI 风格规范](docs/ui-style-guide.md) | 设计与客户端开发者 | 设计令牌、组件、可访问性与页面模式 |
| [Supabase 接入](docs/supabase.md) | 后端与客户端开发者 | 身份、数据域、RLS、Storage、Functions 与本地联调 |
| [运营后台](docs/admin-console.md) | Web/后端开发者 | 管理架构、角色、安全、资源与开发验证 |
| [贡献规范](docs/contributing.md) | 贡献者 | Issue、分支、PR、测试与安全要求 |

文档索引见 [`docs/README.md`](docs/README.md)。

## 已知边界

- 教务系统不是稳定 API。页面结构、登录流程或网络策略变化可能使解析暂时失效。
- 当前教务身份绑定由 App 在登录成功后发起；它不等同于服务端对学校身份进行独立证明。
- 社区、评价和共享能力依赖正确部署的 Supabase schema、RLS 与 Edge Functions。
- 教师与课程等目录型数据需要经过可信来源整理或后台审核，仓库不会自动保证数据完整性。
- 这是持续演进中的校园产品，内部数据模型与未稳定接口可能变化。

## 发展方向

项目近期优先级是提高教务解析韧性、完善错误与恢复体验、收紧后端安全边界，并让不同校园能够通过能力配置复用基础架构。未来功能以真实使用反馈为依据，不承诺固定时间表。

## 参与贡献

提交代码前请阅读[贡献规范](docs/contributing.md)。涉及新功能或行为变化的 PR 应同时更新对应文档；涉及用户数据、认证、校园身份或管理权限的改动必须说明安全边界与验证方式。

## 许可

本项目使用 [CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/) 许可。允许在署名、非商业和相同方式共享的前提下学习、修改与再分发。第三方依赖、学校系统内容、品牌资源和用户数据不因本仓库许可而获得额外授权。

## 联系

- 问题与建议：[GitHub Issues](../../issues)
- 邮箱：`support@myleafy.space`
