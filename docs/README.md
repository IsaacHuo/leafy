# MyLeafy 文档中心

本目录保存 MyLeafy 的公开产品与工程文档。文档以当前 `main` 分支代码为事实来源，面向使用者、贡献者和需要理解系统边界的开发者。

## 推荐阅读顺序

1. [项目总览](overview.md)：产品定位、能力范围、数据来源与当前限制。
2. [架构说明](architecture.md)：iOS 分层、教务链路、本地数据、Supabase 与运营后台边界。
3. [App 产品设计](app-design.md)：信息架构、核心流程、页面职责与状态约定。
4. [UI 风格规范](ui-style-guide.md)：设计令牌、组件模式、可访问性与评审清单。
5. [Supabase 接入](supabase.md)：身份、数据域、RLS、Storage、Edge Functions 与本地环境。
6. [运营后台](admin-console.md)：管理请求链路、角色、资源、安全与测试。
7. [贡献规范](contributing.md)：Issue、分支、PR、验证与敏感信息要求。

## 文档目录

| 文档 | 内容 | 主要读者 |
|---|---|---|
| [overview.md](overview.md) | 项目定位、系统组成、能力、所有权和发展方向 | 所有人 |
| [architecture.md](architecture.md) | 技术分层、数据流、外部系统和架构约束 | iOS/后端开发者 |
| [app-design.md](app-design.md) | 产品目标、导航、核心页面和全局状态 | 产品与客户端开发者 |
| [Leafy_APP功能总结.md](Leafy_APP功能总结.md) | iOS App 与小组件的完整功能清单 | 产品、测试与客户端开发者 |
| [ui-style-guide.md](ui-style-guide.md) | 主题、字体、间距、组件、动效和可访问性 | 设计与客户端开发者 |
| [Leafy_UI设计总结.md](Leafy_UI设计总结.md) | 当前 iOS 页面与组件的设计实现总结 | 设计与客户端开发者 |
| [supabase.md](supabase.md) | Auth、Database、RLS、Storage、Functions 和联调 | 后端与客户端开发者 |
| [admin-console.md](admin-console.md) | Web 后台、RBAC、代理、安全、开发和测试 | Web/后端开发者 |
| [contributing.md](contributing.md) | 协作流程、测试与安全要求 | 贡献者 |
| [roadmap.md](roadmap.md) | 非承诺式发展方向和工程优先级 | 贡献者 |
| [release-notes.md](release-notes.md) | 对外版本更新文案归档 | 维护者与用户 |
| [diagrams/](diagrams/) | D2 源文件与渲染后的 SVG | 文档维护者 |
| [archive/](archive/) | 仍有参考价值的历史复盘和问题分析 | 维护者 |

## D2 图表

架构和流程图同时提交：

- `*.d2`：可维护的源文件。
- `*.svg`：供 GitHub Markdown 直接展示的渲染文件。

修改图表后应重新渲染 SVG，并同时提交源文件与输出文件。推荐使用 D2 CLI：

```bash
d2 --layout=elk --theme=0 \
  docs/diagrams/system-overview.d2 \
  docs/diagrams/system-overview.svg
```

复杂图可以改用其他官方主题，但同一组图应保持一致布局方向、颜色语义和命名。

## 维护规则

- 文档默认使用中文，代码标识、命令和协议名保留原文。
- 当前实现写入总览、架构和对应接入文档；未来方向写入路线图。
- README 负责快速理解和入口，不复制所有实施细节。
- 链接使用仓库相对路径，不写本机绝对路径。
- 用户可见能力必须注明数据来源、可用条件和失败边界。
- 不提交生产密钥、Cookie、密码、真实学生数据、管理员凭据和内部发布权限说明。
- 过期但仍有分析价值的内容移动到 `archive/`；无价值的操作记录直接删除。
- 代码行为、数据库 schema、管理 action 或 UI token 变化时，在同一 PR 更新对应文档。
