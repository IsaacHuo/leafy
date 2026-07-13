# MyLeafy Wiki

MyLeafy 是一款面向高校学习与校园生活的原生 iOS 应用，目前主要服务北京林业大学。项目以课表和学业数据为核心，将教务查询、学习管理、校园社区、共享课表、Widget 与 Leafy AI 组织为一套连续的校园工作流。

> 对外产品名称统一为 **MyLeafy**；仓库名、Xcode target 与部分历史类型仍使用 `leafy` / `Leafy`。

![MyLeafy 系统概览](https://raw.githubusercontent.com/IsaacHuo/leafy/main/docs/diagrams/system-overview.svg)

## 从这里开始

| 目标 | 推荐页面 |
|---|---|
| 快速了解产品 | [产品总览](Product-Overview) · [功能地图](Features) |
| 在本地运行项目 | [快速开始](Getting-Started) |
| 理解代码与数据流 | [系统架构](Architecture) |
| 开发或评审界面 | [设计系统](Design-System) |
| 配置业务后端 | [Supabase 接入](Supabase) |
| 运行 Web 管理端 | [运营后台](Admin-Console) |
| 了解数据边界 | [安全与隐私](Security-and-Privacy) |
| 参与项目开发 | [贡献指南](Contributing) · [常见问题](FAQ) |

## 项目组成

| 子系统 | 主要职责 | 关键技术 |
|---|---|---|
| iOS App | 教务登录、课表、校园工具、社区、AI、个人设置与本地缓存 | SwiftUI、SwiftData、URLSession、WidgetKit |
| 学校教务适配 | 会话维护、页面访问、HTML 解析与异常恢复 | Cookie、WKWebView、SwiftSoup |
| 业务后端 | 社区、通知、共享、评价、配置与文件 | Supabase Auth、PostgreSQL、RLS、Storage、Edge Functions |
| 官网与运营后台 | 产品官网、公开分享页、内容治理与配置管理 | React、React-admin、MUI、Cloudflare Pages |

## 设计原则

- **课表是核心上下文**：课程时间、地点、周次和学期为提醒、Widget、分享、学习记录与 AI 提供结构化基础。
- **权威来源分离**：学校教务数据以学校系统为准；MyLeafy 自有业务数据由 Supabase 承载；设备数据保留本地所有权。
- **本地优先**：远程服务不可用时尽量保留课表、成绩缓存和个人记录等本地能力。
- **原生交互优先**：以 SwiftUI 系统导航、列表、Tab、Sheet、Alert 和 SF Symbols 为基础。
- **能力按校园开放**：入口由校园配置、用户身份和后端能力共同决定，不展示无法兑现的功能。
- **权限在服务端成立**：前端隐藏入口只改善体验，RLS、Edge Functions 和管理代理才构成安全边界。

## 当前边界

- 学校教务系统不是稳定 API，登录流程或页面结构变化可能导致解析暂时失效。
- 社区、共享、评价和运营功能依赖正确部署的 Supabase schema、RLS 与 Edge Functions。
- AI 输出属于辅助信息，成绩、考试、培养要求等结论仍以学校官方系统为准。
- 不同校园支持的功能不同，页面可见性不等于项目缺少实现。

## 相关链接

- [源代码](https://github.com/IsaacHuo/leafy)
- [详细工程文档](https://github.com/IsaacHuo/leafy/tree/main/docs)
- [问题与建议](https://github.com/IsaacHuo/leafy/issues)
- 联系邮箱：`support@myleafy.space`
