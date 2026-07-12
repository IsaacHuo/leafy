# MyLeafy UI 设计总结

本文档总结 MyLeafy 原生 iOS App 与小组件的界面设计。内部代码、组件和部分资源仍沿用 Leafy 命名；内容以当前 SwiftUI 实现和项目 UI 规范为准，不展开官网、后台控制台或数据库管理界面。

## 1. 整体视觉方向

MyLeafy 的 UI 目标是轻量、原生、低噪声的北林校园工具感：

- 以 SwiftUI 系统控件为基础，优先使用 `NavigationStack`、`TabView`、`List`、`sheet`、`Menu`、`Alert`、`Picker`、`Toggle` 和 `ContentUnavailableView`。
- 页面背景使用系统 grouped background 叠加低透明度主题渐变。
- 主要内容由卡片、列表、胶囊控件、浮动按钮和 sheet 承载。
- 主题保持明亮、清爽、低饱和，不使用厚重阴影和复杂装饰。
- 图标优先使用 SF Symbols。
- 新系统使用 Liquid Glass 能力，旧系统使用材质背景、边框和卡片阴影回退。

整体气质：

- 课表页强调“快速确认今天安排”。
- Leafy AI 强调“全屏沉浸对话、悬浮输入和成品资产”。
- 社区页强调“信息流和互动动作清楚可见”。
- 学业页强调“工具集合但不拥挤”。
- 我的页强调“系统设置感和安全边界”。

## 2. 主题、颜色和外观

主题设置：

- 鼠尾草绿：默认主题。
- 蒂芙尼蓝。
- 糖果莓粉。
- 自定义主题色。

语义色使用：

- `AppTheme.accent`：主强调色，用于按钮、选中状态、重点图标和课程卡片。
- `AppTheme.accentEmphasis`：更高对比的强调色，用于浅色背景上的图标和文字。
- `AppTheme.background`：系统分组背景。
- `AppTheme.pageGradient`：页面渐变底色。
- `AppTheme.cardBackground`：卡片和列表行底色。
- `AppTheme.separator`：低对比边框。
- `AppTheme.primaryText`、`secondaryText`、`tertiaryText`：主文本、辅助文本和弱提示。
- `AppTheme.danger`：退出登录、删除、举报后续确认等危险操作。
- `AppTheme.warning`：考试、停课、特殊日程等提示。

外观模式：

- 默认浅色。
- 可切换深色。
- 可跟随系统。
- 切换外观和主题色时使用柔和动画。

App 图标：

- 图标外观可以跟随主题或使用预设色。
- 自定义主题色会映射到最接近的预设图标外观。

## 3. 字体、字号和密度

字体策略：

- 中文和普通 UI 使用系统字体。
- 英文品牌标题使用 `Lora` 资源。
- 通过 `leafyFontScale`、`leafyControlScale` 和 `dynamicTypeSize` 统一控制显示密度。

显示密度：

- 紧凑。
- 标准。
- 舒适。
- 宽松。

常用字号层级：

- 页面标题使用大标题或 `responsiveLargeTitle()` 一类样式。
- 卡片标题使用 `title2()`、`leafyHeadline()`。
- 正文使用 `leafyBody()`。
- 次级说明使用 `leafySubheadline()`。
- 微说明、状态、时间和辅助标签使用 `microCaption()`。

设计规则：

- 不按屏幕宽度直接缩放字号。
- 小屏下文字自然换行，关键标签使用 `lineLimit` 和 `minimumScaleFactor` 控制溢出。
- 图标按钮和紧凑控件会随 `leafyControlScale` 调整尺寸。

## 4. 圆角、间距、卡片和背景

圆角：

- `AppRadius.large = 24`：大卡片、主要容器、部分 sheet 内容块。
- `AppRadius.medium = 16`：中型卡片、输入框、列表容器。
- `AppRadius.small = 12`：小角标、图标底板、紧凑块。

间距：

- `AppSpacing.page = 20`：页面左右边距。
- `AppSpacing.section = 24`：大区块间距。
- `AppSpacing.card = 16`：卡片内部和卡片之间的常用间距。
- `AppSpacing.compact = 12`：紧凑控件间距。
- `AppSpacing.micro = 8`：微小间距。

背景：

- 页面根背景使用 `LeafyPageBackground()`。
- 卡片使用 `.leafyCardStyle()`。
- 胶囊控件使用 `.leafyFloatingCapsule()` 或 `.leafyCapsuleChipSurface()`。
- 玻璃/材质表面使用 `.leafyGlassSurface(...)`，在 iOS 26 使用 `glassEffect`，低版本回退到 `topBarMaterial` 和描边。

卡片规则：

- 卡片用于信息项、工具入口、状态提示和重复内容。
- 避免整页大装饰卡片。
- 避免在卡片里套视觉等价的卡片。
- 卡片边框使用低对比 separator，浅色模式可有轻阴影，深色模式弱化阴影。

## 5. 根导航设计

根结构：

- Leafy：SF Symbol `sparkles`。
- 课表：SF Symbol `calendar`。
- 社区：SF Symbol `person.2`。
- 学业：SF Symbol `book.closed`。
- 我的：SF Symbol `person`。

iOS 26 及以上：

- 使用系统 `TabView`。
- 社区 Tab 支持未读 badge。
- 使用系统 tab bar 外观并禁止最小化行为。
- Leafy 被选中后隐藏根 tab bar，AI 顶部工具栏自然使用 Liquid Glass。

iOS 17 到 iOS 25：

- 使用系统 `TabView` 与原生 tab item。
- Leafy 被选中后使用系统 toolbar visibility 隐藏根 tab bar，退出工作空间后恢复。
- 社区 Tab 使用系统 badge。

Leafy AI 工作空间：

- 顶部使用透明系统工具栏：左侧菜单，右侧成组的新建对话和退出按钮，不显示居中标题。
- iPhone 使用左侧滑入的历史抽屉；iPad 使用 `NavigationSplitView`。
- 抽屉包含搜索、成品库和最近对话；设置使用左下角独立圆形按钮，退出入口统一放在聊天页右上角。
- 输入栏脱离底部整块栏位，以悬浮玻璃胶囊承载 `+`、多行输入和发送/停止。
- iOS 26 使用 `GlassEffectContainer`；旧系统回退到系统 Material、细描边和轻阴影。

## 6. 登录页设计

布局：

- 使用 `NavigationStack` 包裹，但隐藏导航栏。
- 页面居中排列，顶部留白充足。
- 背景使用 `LeafyPageBackground()`。
- Logo 使用 `LeafyLoginLeaf` 图片，圆角方形裁切。
- 品牌名 `Leafy` 使用英文品牌字体。
- 表单最大宽度约 360，适配不同屏幕。

控件：

- 登录身份选择使用 segmented picker。
- 学号、密码、验证码放在同一张卡片内，用分割线分隔。
- 密码显隐使用眼睛 SF Symbol 按钮。
- 验证码按钮显示图片、加载态或“重试”状态。
- 登录按钮在 iOS 26 使用 `.glassProminent`，旧系统使用 `.borderedProminent`。
- 演示模式使用带 `sparkles` 图标的 bordered 按钮。

反馈：

- 登录中显示 `ProgressView`。
- 验证码加载失败时在表单下方显示微说明。
- 登录失败用系统 alert。

## 7. 课表页 UI

整体：

- 不使用大导航标题，重点空间留给课表。
- 顶部工具栏左侧是快捷入口菜单，右侧是周次菜单、回到本周和刷新。
- 页面背景可以叠加用户自定义课表底图。
- 课表主体优先使用横向连续周视图网格。

周视图网格：

- 左上角显示月份。
- 左侧时间轴显示第几节和开始/结束时间。
- 顶部日期头显示星期、日期、校历事件和考试提示。
- 今日日期头使用主题色实底。
- 考试日期头使用 warning 色。
- 节次背景块使用低透明度卡片背景，午间/晚间边界有更明显的分隔。
- 课程块使用低饱和、多色卡片。
- 今日课程有额外强调。
- 有备注的课程显示提示。
- 重叠课程并排压缩。
- 空白节次可点击添加提醒。

辅助块：

- 重要日期以小块投射到对应日期和节次。
- 考试以 warning 风格小块投射到课表。
- 本地提醒以独立提醒块展示。

详情与状态：

- 课程详情使用 medium/large detent sheet。
- 节次提醒使用 medium detent sheet。
- 日期摘要使用 medium/large detent sheet。
- 首次欢迎说明使用 alert。
- 未登录、加载中、空课表均有明确状态视图。

Agenda 模式：

- 在适合的设备上使用列表式周日程。
- 顶部有上一周/下一周按钮、当前周和日期范围。
- 每天是一张卡片，课程、考试、提醒和重要日期按时间排序。

课表底图：

- 底图位于页面背景层。
- 支持显示模式、透明度、模糊、遮罩和课程卡片透明度调整。
- 自定义底图启用时，课程配色可从底图生成或使用兜底色板。

## 8. 社区页 UI

整体：

- 社区页是信息流结构，内容用滚动卡片承载。
- 顶部保留天气、工具入口、通知、发布等操作。
- 社区工具面板是浮动面板，包含筛选、热门、搜索和投票入口。

帖子卡片：

- 展示标题、正文摘要、分类、作者、时间、图片预览和互动统计。
- 点赞与收藏使用图标按钮。
- 图片以网格或横向预览展示，点击可进入图片预览。
- 热门列表顶部显示“近 7 天热门”和排序说明。

发布 sheet：

- 使用 `NavigationStack`。
- 顶部标题为“发布”。
- 内容按卡片分成帖子内容和图片两块。
- 标题、正文使用填充背景输入框。
- 分类使用横向胶囊 pill。
- 匿名发布使用 Toggle。
- 图片选择使用 `PhotosPicker`，预览图右上角有删除按钮。
- 工具栏左侧取消，右侧发布。

搜索 sheet：

- 顶部为玻璃搜索框。
- 输入为空时显示搜索引导空状态。
- 搜索结果继续使用帖子卡片。
- 清空输入使用 `xmark.circle.fill` 图标。

投票 sheet：

- 使用列表卡片展示投票。
- 顶部右侧 `plus` 发布投票。
- 空状态使用 `ContentUnavailableView`。
- 删除申请使用 confirmation dialog。

条款、举报和屏蔽：

- 未同意条款时显示条款提示卡。
- 条款确认用 large detent sheet。
- 举报和屏蔽使用 confirmation dialog。
- 删除帖子或评论使用 destructive 操作样式。

## 9. 学业页 UI

整体：

- 学业页不再做首页式大卡片堆叠，而是通过一级功能切换展示对应工具。
- 页面使用 `ScrollView` 加 `VStack`，内容最大宽度约 840。
- 各工具入口使用 `ToolEntryCard`，带 SF Symbol、标题和一句说明。
- 动态动作按钮可打开学业功能切换浮动面板。

一级功能：

- 成绩。
- 自习室。
- 学习相关。
- 体育相关。
- 教学培养。
- 职业规划。
- 考研信息。
- 评教/评课/评菜。

详情页通用结构：

- 使用 `AcademicDetailScrollContainer` 统一滚动容器、背景、顶部补偿和底部浮动 Tab 预留。
- 使用 `AcademicDetailCard` 作为信息块。
- 使用 `AcademicDetailSectionHeader` 作为小节标题。
- 使用 `AcademicDetailDivider` 做卡片内部轻分割线。
- 使用 medium/large sheet 展示教师、课程、菜品、体育场馆、考研目标等详情。

成绩与教务类：

- 成绩查询、考试安排、教学计划、培养方案等使用卡片、表格和分组列表。
- 失败状态区分加载失败、无数据和教务会话问题。

学习与职业类：

- 本地资料、简历和文件预览使用 Quick Look。
- 文件行包含缩略图、标题、类型、时间和更多操作菜单。
- 任务行使用圆形勾选按钮，完成后弱化文本并添加删除线。
- 添加按钮使用小胶囊样式。

体育类：

- 体育场馆以双列 tile 展示，包含标题、位置和标签。
- 场馆详情 sheet 中分区展示开放时间、收费标准和备注。
- 阳光长跑、体测记录用摘要卡片和记录列表表达进度。

评教/评课/评菜：

- 顶部用 segmented picker 切换三种评分对象。
- 每个模式都有搜索和筛选工具栏。
- 列表项使用卡片，展示平均分、评分数和星级分布。
- 详情 sheet 内提交或更新星级评分。
- 缺失项提交按钮放在标题区域右侧。

考研信息：

- 目标院校、公共来源、提交线索分区展示。
- 目标行提供打开、编辑、聚焦、归档和删除操作。
- 公共来源不可用时展示错误提示和官方链接兜底。

## 10. 我的页 UI

整体：

- 使用系统 `List + insetGrouped`。
- 列表最大宽度约 760，居中显示。
- 背景仍使用 `LeafyPageBackground()`。
- 列表行背景使用 `AppTheme.cardBackground`。

资料区：

- 第一组是社区资料卡式行。
- 左侧为头像，右侧为昵称和绑定说明。
- 尾部使用 chevron 表示可进入编辑。
- 点击后打开社区资料编辑 sheet。

内容区：

- 我的发帖、我的点赞、我的评论、我的收藏、我的投票。
- 每行左侧使用 `LeafyIconBadge`，右侧包含标题和说明。
- 使用 `NavigationLink` 进入对应列表。

功能区：

- 共享课表、个性化、课表底图使用 `NavigationLink`。
- English 和隐藏周末使用 Toggle。
- Toggle 使用主题强调色。

支持区：

- 说明与安全、举报与反馈、同步与安全、给 MyLeafy 评分、常用链接、检查更新、联系我们。
- 反馈和联系使用 sheet。
- 外部动作，如评分和检查更新，使用按钮行。

退出登录：

- 单独成组。
- 文本居中。
- 使用 `AppTheme.danger`。
- 点击后显示确认 alert。

## 11. 个性化与设置 UI

个性化页：

- 使用 inset grouped List。
- 分区包括主题色、字号、App 外观和外观模式。
- 主题色用圆形 swatch。
- 字号用圆形底板上的字母 A 表示大小。
- App 图标外观用圆角方形 leaf 预览。
- 选中项使用 `checkmark.circle.fill`，未选中使用空心圆。
- 自定义主题色用 medium detent sheet，内部使用系统 `ColorPicker`。

课表底图页：

- 通过照片选择器或本地图片配置课表背景。
- 控件以开关、滑杆、选项和预览方式组织。
- 设置变化即时影响课表背景层。

同步与安全页：

- 以说明卡片、缓存状态和操作入口为主。
- 避免展示原始 Cookie、HTML 或内部调试路径。

## 12. Sheet、弹窗与菜单

Sheet：

- 编辑、详情和轻量任务优先使用 sheet。
- 默认 detents 为 medium/large。
- 条款和内容较长的页面使用 large。
- 表单 sheet 使用 `NavigationStack`，左侧取消，右侧完成/发布/保存。

Alert：

- 登录失败、缓存恢复、退出登录、更新检查失败等使用系统 alert。
- 危险操作使用 destructive role。

Confirmation dialog：

- 举报原因选择。
- 屏蔽用户确认。
- 删除帖子、评论、投票申请等需要确认的操作。

Menu：

- 课表快捷入口。
- 课表周次选择。
- 文件、简历、帖子等更多操作。

## 13. 状态页与反馈

加载态：

- 局部 `ProgressView` 优先，避免整页假死。
- 按钮内也会显示 `ProgressView` 表示提交或登录中。

空状态：

- 使用 `ContentUnavailableView` 表达暂无帖子、暂无投票、暂无课程库、暂无目标院校等情况。
- 空状态通常附带下一步动作，例如重试、刷新、导入、提交缺失项或添加目标。

错误状态：

- 社区错误使用错误卡片和重试按钮。
- 教务错误优先转成用户可理解文案。
- 文件不存在、链接无效、Supabase 权限失败等场景使用 alert 或局部错误文案。

成功反馈：

- 常用 `LeafyOperationAlert` 显示“操作成功/操作失败”。
- 发布、保存、删除、同步等操作完成后给出短提示。

审核/待处理：

- 含图片帖子、投票删除申请、目录补录建议和考研线索会用文案说明待审核。

## 14. 多语言和可访问性

多语言：

- App 支持中文和 English 设置。
- 根 Tab、学业分类、主题标题和部分说明通过 `L10n.text` 本地化。
- 切换语言会影响 `Locale` 和默认字体。

可访问性：

- 图标按钮设置 accessibility label，例如刷新验证码、首页快捷入口、筛选帖子、切换学业功能。
- Tab 选中态添加 accessibility selected trait。
- 小组件和卡片尽量合并子元素，减少读屏噪声。

## 15. iOS 小组件 UI

小组件规格：

- 支持 systemSmall 和 systemMedium。
- 使用 `containerBackground(for: .widget)`。
- 禁用系统内容边距，使背景完整贴合组件。

视觉：

- 背景来自 Leafy 小组件主题调色板。
- 小号强调今日/明日摘要、天气和最近课程。
- 中号顶部居中显示“今日课表/明日课表”，左侧为日期和周次，右侧为“今/明”切换胶囊。
- 课程以紧凑列卡展示。
- 超出课程数时显示“更多”列。
- 无课、需要登录、缓存过期等 quiet state 使用图标底板、标题和说明。

交互：

- 今/明切换通过 App Intent 实现。
- 点击课程 deep link 到 App 内课程详情。
- 点击无课状态进入课表。
- 点击需要登录或缓存过期状态进入缓存同步。

## 16. 设计维护原则

- 新页面优先复用 `AppTheme`、`AppSpacing`、`AppRadius`、`LeafyPageBackground`、`.leafyCardStyle()` 和 `.leafyGlassSurface(...)`。
- 新图标优先使用 SF Symbols。
- 工具操作优先用图标按钮，明确命令才用文字按钮。
- 深色模式、自定义主题色和不同显示密度都要保持可读。
- 不在 UI 中暴露 Cookie、原始 HTML、内部文件路径或工程化调试信息。
- 页面应覆盖加载、空、错误、未认证和成功反馈状态。
- 学业和社区这类工具密集页面应保持可扫描，不做营销式大标题或装饰性视觉。
