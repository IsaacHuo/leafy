# MyLeafy 文档中心

本目录集中维护 MyLeafy 的项目文档。内部代码名仍为 Leafy；根目录 `README.md` 只保留项目简介和入口链接，其余项目自有 Markdown 都应放在这里。

## 推荐阅读顺序

1. [项目总览](overview.md)：先理解产品定位、已落地能力、数据源和当前边界。
2. [架构说明](architecture.md)：再看 App、教务直连、解析、SwiftData、Supabase 的分层与数据流。
3. [App 设计](app-design.md)：确认登录、课表、社区、学业、我的、评教等页面结构。
4. [UI 风格指南](ui-style-guide.md)：落 UI 前对齐主题、间距、控件和状态展示。
5. [Supabase 接入](supabase.md)：配置社区、通知、评教和 Edge Functions。
6. [运营后台](admin-console.md)：配置 Web 后台和社区运营能力。
7. [发布说明](release-notes.md)：准备 App Store 和 TestFlight 文案。
8. [后续路线图](roadmap.md)：查看接下来优先处理的产品与工程事项。
9. [TestFlight 检查清单](testflight-checklist.md)：发 TestFlight 前逐项检查。

## 文档目录

| 文档 | 用途 |
|---|---|
| [overview.md](overview.md) | 项目定位、能力范围、数据源、当前状态 |
| [architecture.md](architecture.md) | SwiftUI App、教务直连、HTML 解析、SwiftData、Supabase、后台架构 |
| [app-design.md](app-design.md) | 页面信息架构、主要流程、状态与交互 |
| [ui-style-guide.md](ui-style-guide.md) | 主题、颜色、字体、圆角、间距、卡片、Tab、空/错/加载态 |
| [supabase.md](supabase.md) | Supabase 配置、migration、Edge Function、客户端能力和约束 |
| [admin-console.md](admin-console.md) | 官网 `/admin` 运营后台的配置、模块和安全边界 |
| [release-notes.md](release-notes.md) | App Store 和 TestFlight 发布说明 |
| [roadmap.md](roadmap.md) | 当前阶段之后的实施重点 |
| [testflight-checklist.md](testflight-checklist.md) | TestFlight 上传前检查 |
| [archive/](archive/) | 历史复盘、错误分析和阶段性总结 |

## 维护约定

- 文档统一使用中文。
- 不再新增根目录级 Markdown，根目录 `README.md` 除外。
- 文档内链接优先使用相对路径，不写本机绝对路径。
- 当前实现写入 `overview.md` / `architecture.md`；未来计划写入 `roadmap.md`。
- 过期但仍有参考价值的分析文档放入 `archive/`，不要混入主文档流。
