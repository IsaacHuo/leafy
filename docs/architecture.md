# MyLeafy 架构说明

本文档描述当前代码的真实架构。产品和页面规格见 [App 设计](app-design.md)，视觉规范见 [UI 风格指南](ui-style-guide.md)。

## 1. 总体分层

MyLeafy 当前按以下边界组织；内部代码名、target 和多数类型名继续沿用 Leafy：

- `leafy/App/`：应用启动、登录态切换、根 Tab、主题、生命周期和导航协调。
- `leafy/Features/`：Auth、Timetable、Discover、Profile 四类用户可见功能。
- `leafy/Features/*/Presentation/`：SwiftUI 页面、子视图、sheet 和导航协调，只组合 UI 与轻量交互状态。
- `leafy/Features/*/Application/`：面向页面的用例、仓储协议、缓存协调和可测试的用户操作。
- `leafy/Features/*/Domain/`：纯计算模型和投影，例如课表网格快照、周课表投影、成绩展示快照和学习空间索引。
- `leafy/Services/`：强智教务直连、Supabase、诊断和课表 WebView 兜底。
- `leafy/Parsers/`：SwiftSoup HTML 解析，输出统一业务模型。
- `leafy/Shared/Models/`：社区 DTO、本地 SwiftData 模型和图片处理。
- `supabase/`：数据库 migration、Edge Functions、管理脚本。
- `site/src/admin/`：官网 `/admin` 社区运营后台。

核心依赖：

| 层 | 技术 |
|---|---|
| iOS UI | SwiftUI |
| 本地持久化 | SwiftData |
| 学校网络 | URLSession + HTTPCookieStorage |
| HTML 解析 | SwiftSoup |
| 课表兜底 | WKWebView |
| 社区后端 | Supabase |
| 后台前端 | React + Vite + Supabase JS |

部署目标为 iOS 17.0；部分 iOS 26 Liquid Glass API 使用 `#available` 做运行时保护。

## 2. App 启动和导航

`leafyApp` 负责创建 SwiftData `ModelContainer`、注入主题偏好、处理深色模式和生命周期回调。模型容器包含课程、成绩、课程备注、课程提醒、收藏自习室和兼容保留的收藏链接等本地模型；如果本地 store 损坏，会先备份旧缓存，再尝试重建或用内存 store 启动。

启动时通过 `SchoolNetworkManager.hasCachedIdentity` 判断入口：

- 有缓存身份：进入 `ContentView`。
- 无缓存身份：进入 `LoginView`。

`ContentView` 保持四个根入口：

- `课表`
- `社区`
- `学业`
- `我的`

系统 `TabView` 负责承载页面，底部样式使用系统 tab bar；iOS 26 以上自动采用系统 Liquid Glass 外观。跨页面跳转由 `AppNavigationCoordinator` 协调，例如从课表跳到学业页的自习室查询。

## 3. 教务直连层

`SchoolNetworkManager` 是教务系统访问的主入口，按职责拆成多个扩展：

- `SchoolNetworkManager.swift`：单例、基础状态、`URLSession`、`baseURL`。
- `SchoolNetworkManager+Core.swift`：请求预处理、Cookie 同步、HTML 解码、登录页识别、调试落盘、会话失效处理。
- `SchoolNetworkManager+Auth.swift`：验证码、强智登录 encode、登录结果识别。
- `SchoolNetworkManager+Timetable.swift`：课表抓取、成绩抓取、课表入口候选和回退。
- `SchoolNetworkManager+Discover.swift`：考试安排、教学计划、毕业要求、成绩排名、空教室、教室占用、校历资源。

项目不依赖 URLSession 的隐式 Cookie 行为，而是显式维护会话：

1. 登录成功后收集响应 Cookie。
2. 每次请求前同步持久化 Cookie 到 `HTTPCookieStorage`。
3. 请求时额外拼接 `Cookie` 头。
4. 识别登录页或会话失效后统一清理学校会话。

强智登录流程：

1. 请求 `/Logon.do?method=logon&flag=sess` 获取临时 key。
2. 请求 `/verifycode.servlet` 获取验证码图片。
3. 本地执行强智 `encode`。
4. POST 到 `/Logon.do?method=logon`。
5. 结合 HTML 内容、跳转结果和会话状态判断是否登录成功。

## 4. 课表抓取和解析

课表是最复杂的数据链路。`fetchTimetable()` 的回退顺序是：

1. 优先尝试上次登录落点。
2. 直接请求 `/jsxsd/xskb/xskb_list.do`。
3. 如果返回查询页，从 form 中提取参数继续请求。
4. 如果返回主页或中间页，从 DOM、脚本、`href`、`onclick` 中提取候选课表 URL。
5. 如果纯 HTTP 仍无法得到可解析课表，使用 `TimetableWebViewBootstrapper` 带 Cookie 在隐藏 `WKWebView` 中复现浏览器路径。

课表页识别标记包括：

- `学期理论课表`
- `id="kbtable"`
- `kbcontent_`
- `.kbcontent`

`HTMLParser` 支持课表、成绩、考试安排、教学计划和空教室解析。课表解析支持 `#kbtable` 和 `kbcontent_* / .kbcontent` 两类结构，并把课程归并为 `Course` 模型，由 `TimetableView` 按当前周过滤展示。

调试 HTML 会落在应用缓存目录 `Library/Caches/leafy-debug/`，用于排查学校页面结构变化。

展示层的课表性能边界：

- 主课表网格通过 `TimetableGridSnapshot`、`TimetableScheduleProjectionSnapshot` 和布局缓存，把课程布局、提醒占用、考试/倒计时投影提前算好。
- 周课表分享和紧凑网格通过 `WeeklyTimetableProjection` 复用同一类预投影输入，避免 SwiftUI body 在每个日期列重复过滤、排序和解析备注。
- Widget 仍消费共享快照模型，不直接读取 SwiftData。

## 5. 本地数据

SwiftData 当前承担本地缓存和用户偏好数据：

- `Course`：课表课程。
- `Grade`：成绩记录。
- `CourseNote`：课程备注。
- `CourseReminderSetting`：课程提醒设置。
- `FavoriteClassroom`：收藏自习室。
- `FavoriteCampusLink`：兼容保留的旧收藏链接模型，当前 UI 不再写入。

本地 store 损坏时，应用启动逻辑会备份旧 store 文件并尝试恢复，避免直接崩溃。

## 6. Supabase 社区层

Supabase 不接管学校登录。当前身份策略是：

1. App 端确认教务登录成功并保存学号。
2. 客户端创建或恢复匿名 Supabase 会话。
3. 调用 `community-bootstrap-user` Edge Function。
4. Edge Function 用当前 `auth.uid()` 绑定 `profiles.edu_id`。

主要客户端入口：

- `LeafySupabase`：读取配置并创建 Supabase client。
- `CommunitySessionManager`：管理社区 profile、bootstrap、退出和资料更新。
- `CommunityService`：封装帖子、图片、评论、点赞、通知、公告、反馈、评教等 Supabase 操作。
- `TimetableSharingService`：封装共享课表快照发布、邀请码、接受邀请、撤销和移除共享关系。

App 层通过窄仓储协议使用社区能力：Feed、帖子详情、投票、评教/评课/评菜、通知等页面只依赖各自需要的方法，`LiveCommunityRepository` 保留为兼容 facade，底层仍委托 `CommunityService`。

当前 Supabase 能力包括资料完善、邮箱验证绑定、帖子流、全局/分类置顶、发帖、图片上传、评论、点赞、删除、我的发帖、我的点赞、我的评论、通知、站内公告、意见反馈、老师星级评分和共享课表。

共享课表不会接管本地课表缓存。用户需要先在 `我的 -> 功能 -> 共享课表` 中手动发布课程快照；发布后，课表刷新或全量同步成功时会自动更新已发布的共享快照。Supabase 只保存课程名、老师、地点、周次、节次、学期和发布时间。邀请码 7 天过期、单次接受，数据库只保存邀请码 hash；共享关系为单向只读，可由分享者撤销或由查看者移除。

## 7. 运营后台

运营后台挂在官网 `/admin`，前端代码在 `site/src/admin/`。后台前端只调用 Supabase Edge Functions，不保存 `service_role`。后台函数负责登录、会话、社区管理、公告和审计等高权限操作。

后台与 iOS App 共享同一 Supabase 项目，但权限边界不同：

- iOS App 使用 publishable key、匿名会话和 RLS。
- 后台前端使用 publishable key 调 Edge Functions。
- Edge Functions 端使用服务端权限执行管理操作。

社区置顶链路由 `community_post_pins`、`community_feed_v1`、`admin-community` 的 `pinPost` / `unpinPost` / `previewCommunityFeed` action，以及 iOS 社区列表的置顶标识共同组成。后台手册页记录日常运营顺序、置顶规则和权限边界。

## 8. 边界和约束

- 教务能力以学校强智站点直连为主，不引入 0class 后端。
- `WKWebView` 只作为课表抓取兜底，不作为常规浏览器自动化层。
- Supabase 只承接社区、通知、反馈、评教、共享课表和运营后台数据，不替代教务登录。
- 教师名录目前需要手动整理 CSV 后导入 Supabase。
- 强智页面结构变化会直接影响解析稳定性，课表链路需要保留调试落盘能力。
