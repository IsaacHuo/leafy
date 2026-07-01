# MyLeafy 项目总览

MyLeafy 是一个通用型校园应用；内部代码名、target 和类型命名继续使用 Leafy。当前首个上线校园是北京林业大学，教务能力直接连接北林强智系统，并用 Supabase 承接社区、通知、反馈、评教、共享课表和运营后台。

目标学校教务站点：`http://newjwxt.bjfu.edu.cn`

## 1. 当前定位

MyLeafy 当前是一个以课表为核心的校园 App：

- `课表`：默认首页，展示当前周课程、日程摘要和课程详情。
- `社区`：集中帖子流、发布、通知、公告和社区互动。
- `学业`：集中成绩、考试、教学培养、自习室、校历和评教。
- `我的`：集中社区资料、个人内容、收藏、共享课表、设置、支持和退出登录。

产品边界：

- 学校登录、课表、成绩、考试安排、教学计划、培养方案、空教室等能力来自强智教务。
- 社区资料、帖子、图片、评论、点赞、通知、公告、反馈、评教和用户主动发布的共享课表快照来自 Supabase。
- Supabase 不替代学校登录，学校学号仍是主身份来源。
- 后台控制台只服务社区运营和内容管理，不参与学校教务抓取。

## 2. 已落地能力

### 教务直连

- 学号、密码、验证码登录。
- 显式 Cookie 会话管理。
- 课表抓取、解析和 SwiftData 缓存。
- 成绩抓取、解析和展示。
- 考试安排抓取和展示。
- 教学计划、培养方案、毕业学分要求。
- 空教室和指定教室占用查询。
- 校历和作息时间本地资源展示。

### App 体验

- 四个根 Tab：课表、社区、学业、我的。
- 系统 SwiftUI TabView 底部 Tab。
- 课表周视图、周次切换、刷新、课程详情 sheet。
- 今日课程摘要、单日课程分享图、天气信息。
- 学业页横向胶囊导航。
- 校历图片全屏预览、缩放、拖拽和切换。
- 我的页系统列表风格、共享课表、主题色、深色模式、反馈、联系、缓存同步和数据安全说明。

### Supabase 社区

- 匿名 Supabase 会话 + 教务学号绑定。
- 社区 profile 持久化。
- 昵称必填，头像、专业、年级可选。
- 发帖、带图发帖、评论、点赞、删除。
- 我的发帖、我的点赞、我的评论。
- 评论和点赞通知。
- 站内公告。
- 邮箱验证绑定。
- 意见反馈提交。
- 评教老师列表、搜索、详情、星级评分和评分汇总。
- 共享课表快照、7 天单次邀请码、单向只读授权和撤销。

### 运营后台

- 官网 `/admin` React/Vite 后台。
- 管理员登录、会话和审计日志。
- 手册、社区指标、帖子置顶和 Feed 预览、评论、用户、反馈、公告、教师和评分管理。
- 高权限操作通过 Supabase Edge Functions 执行。

## 3. 技术栈

| 层 | 当前技术 |
|---|---|
| iOS | SwiftUI |
| iOS 部署目标 | iOS 17.0 |
| 本地持久化 | SwiftData |
| 学校网络 | URLSession + HTTPCookieStorage |
| HTML 解析 | SwiftSoup |
| 课表兜底 | WKWebView |
| 社区后端 | Supabase Auth / Database / Storage / Edge Functions |
| 后台前端 | React + Vite + TypeScript |

说明：项目中有 iOS 26 的 Liquid Glass API 使用点，但都通过 `#available(iOS 26.0, *)` 保护。

## 4. 目录结构

```text
leafy/
├── App/                  # App 启动、根导航、主题和生命周期
├── Features/             # Auth、Timetable、Discover、Profile
├── Services/             # 教务直连、Supabase、诊断、WebView 兜底
├── Parsers/              # HTMLParser 和调试解析
├── Shared/Models/        # 社区 DTO、本地数据模型
└── Resources/            # Info.plist、图片、字体、Assets

supabase/
├── migrations/           # 数据库 schema、RLS、trigger、RPC
├── functions/            # Edge Functions
└── scripts/              # 管理脚本

site/
└── src/admin/            # 生产官网 /admin 后台入口

docs/
├── README.md             # 文档入口
├── overview.md           # 项目总览
├── architecture.md       # 架构说明
├── app-design.md         # 产品和页面设计
├── ui-style-guide.md     # UI 风格指南
├── supabase.md           # Supabase 接入
├── admin-console.md      # 后台说明
├── roadmap.md            # 路线图
├── testflight-checklist.md
└── archive/              # 历史分析和复盘
```

## 5. 数据源边界

| 能力 | 数据源 | 说明 |
|---|---|---|
| 登录 | 强智教务 | 学号、密码、验证码 |
| 课表 | 强智教务 | HTTP 优先，WKWebView 兜底 |
| 成绩 | 强智教务 | HTML 解析 |
| 考试安排 | 强智教务 | HTML 解析 |
| 教学计划 / 培养方案 | 强智教务 | HTML 解析和本地计算 |
| 空教室 / 教室占用 | 强智教务 | 条件查询 |
| 校历 / 作息 | 本地资源 | App 包内图片 |
| 社区资料 / 帖子 / 评论 / 点赞 / 收藏 | Supabase | 匿名会话绑定教务学号 |
| 通知 / 公告 / 反馈 | Supabase | 数据库 + Edge Functions |
| 评教 | Supabase | 老师名录手动导入，星级评分 |
| 运营后台 | Supabase Edge Functions | 高权限管理操作 |

## 6. 当前风险和待优化点

- 强智页面结构变化会影响课表、成绩和培养相关解析。
- 课表链路依赖 Cookie、页面中间跳转和 WebView 兜底，仍是最高风险功能。
- Supabase 当前认证边界是 App 端确认学校登录成功后再绑定学号；如果未来要防止改包伪造学号，需要把学校登录校验迁到受控后端。
- 教师名录仍需手动导入，缺少自动同步机制。
- 错误文案还需要继续降低工程化表达，特别是解析失败和学校网络不可达场景。

## 7. 文档边界

- 当前实现事实：本文档和 [架构说明](architecture.md)。
- 页面产品规格：[App 设计](app-design.md)。
- UI 规范：[UI 风格指南](ui-style-guide.md)。
- Supabase 配置和约束：[Supabase 接入](supabase.md)。
- 后续工作：[后续路线图](roadmap.md)。
