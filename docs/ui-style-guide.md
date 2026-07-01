# Leafy UI 风格指南

本文档记录当前 Leafy 的 UI 风格和组件使用约定。页面结构见 [App 设计](app-design.md)。

## 1. 视觉方向

Leafy 的视觉目标是轻量、原生、低噪声：

- 使用 SwiftUI 系统控件作为基础。
- 页面背景使用系统分组背景叠加低透明度主题渐变。
- 内容以卡片、列表、胶囊控件和 sheet 承接。
- 主题色可切换，整体保持明亮多彩但不过度霓虹的校园工具感。
- 避免厚重阴影、复杂装饰和大面积毛玻璃。

## 2. 主题色

主题定义集中在 `leafy/App/Theme/AppTheme.swift`。

当前支持的主题：

- 鼠尾草绿：默认主题。
- 蒂芙尼蓝。
- 阳光琥珀。
- 珊瑚粉红。
- 蜜橘橙。
- 柠檬黄。
- 青柠绿。
- 海岛晴蓝。
- 糖果莓粉。
- 兰花紫。

语义色：

- `AppTheme.accent`：主强调色。
- `AppTheme.accentEmphasis`：用于浅色主题文字和图标的高对比强调色。
- `AppTheme.leafyGreenSoft`：主题浅色背景。
- `AppTheme.background`：系统 grouped background。
- `AppTheme.cardBackground`：卡片底色。
- `AppTheme.separator`：低对比度边框。
- `AppTheme.primaryText`：主文本。
- `AppTheme.secondaryText`：次级文本。
- `AppTheme.tertiaryText`：弱提示文本。
- `AppTheme.danger`：危险操作。

使用规则：

- 普通操作使用 `accent`。
- 危险操作只使用 `danger`。
- 卡片边框使用 `separator`，不要直接使用高对比描边。
- 新页面不要硬编码颜色，应优先使用 `AppTheme` 语义色。

## 3. 字体

当前字体策略：

- 中文和大部分 UI 使用系统字体。
- 字号通过 `leafyFontScale` 环境值统一缩放。
- 英文品牌标题可使用 `Lora` 资源。

常用 View modifier：

- `responsiveLargeTitle()`
- `title1()`
- `title2()`
- `leafyTitle3()`
- `leafyHeadline()`
- `leafyBody()`
- `leafySubheadline()`
- `microCaption()`

使用规则：

- 页面主标题使用 `responsiveLargeTitle()` 或同级大标题。
- 卡片标题使用 `title2()` / `leafyHeadline()`。
- 列表说明和辅助信息使用 `leafyBody()` / `microCaption()`。
- 不按屏幕宽度动态缩放字号；只使用 App 统一 display scale。

## 4. 圆角、间距和阴影

圆角定义：

- `AppRadius.large = 24`：大卡片、sheet 内主要容器。
- `AppRadius.medium = 16`：中型卡片、按钮组。
- `AppRadius.small = 12`：小角标、图标底板、紧凑块。

间距定义：

- `AppSpacing.page = 20`：页面水平边距。
- `AppSpacing.section = 24`：大区块间距。
- `AppSpacing.card = 16`：卡片内部和卡片间常用间距。
- `AppSpacing.compact = 12`：紧凑控件间距。
- `AppSpacing.micro = 8`：微小间距。

阴影：

- 浅色模式卡片使用轻阴影：半径 10，Y 偏移 2，黑色 5%。
- 深色模式默认弱化阴影，主要依赖系统底色和边框层次。

## 5. 背景和卡片

通用背景：

- 页面根部使用 `LeafyPageBackground()`。
- 常规内容卡片使用 `.leafyCardStyle()`。
- 浮动胶囊使用 `.leafyFloatingCapsule()`。

卡片规则：

- 卡片用于重复内容项、工具入口、状态说明和信息容器。
- 不要把整个页面 section 做成一张大装饰卡片。
- 不要在卡片里再套视觉上等价的卡片。
- 卡片文本需要在小屏下自然换行，不允许压缩到不可读。

## 6. 图标和按钮

通用图标底板：

- 使用 `LeafyIconBadge(systemName:tint:)`。
- 图标优先使用 SF Symbols。

顶部浮动操作：

- 使用 `LeafyGlassIconButton`。
- iOS 26 使用 `.glassEffect(.regular.interactive())`。
- 低版本回退到 `topBarMaterial` + 圆形边框。

按钮规则：

- 刷新、通知、发布、设置等工具动作优先使用图标按钮。
- 文本按钮用于明确命令，例如登录、重试、退出。
- 通知未读状态使用小红点，不把数字做成复杂 badge。

## 7. 根 Tab 和导航

根导航：

- 固定 `课表 / 社区 / 学业 / 我的` 四个 Tab。
- `ContentView` 使用系统 `TabView` 承载页面。
- 使用系统 tab bar；iOS 26 以上由系统提供 Liquid Glass 外观。

Tab 样式：

- 选中项使用当前主题强调色。
- 未选中项使用 `tertiaryText`。
- 每个 Tab 由 SF Symbol + 短标题组成。
- 教务相关复杂功能进入学业页，社区保持独立根入口。

页面导航：

- 二级页面优先使用 `NavigationLink`。
- 轻量详情和编辑优先使用 `.sheet`。
- 确认危险操作使用 `Alert`。

## 8. 页面状态

每个核心页面必须有明确状态：

- `Loading`：使用 `ProgressView` 或局部加载态，避免整页假死。
- `Empty`：说明没有内容的原因，并给出下一步动作。
- `Error`：展示用户可理解的错误，不暴露 Cookie、原始 HTML 或内部调试文件路径。
- `Unauthenticated`：学校会话失效时引导重新登录；社区会话缺失时尝试重新初始化。

推荐文案方向：

- 网络不可达：提示检查校园网络或稍后重试。
- 学校会话失效：提示重新登录。
- 解析失败：提示学校页面结构可能变化，并提供重试。
- Supabase 配置缺失：提示社区功能暂不可用。

## 9. 页面级约定

### 登录页

- 顶部留白较多，保持轻量启动感。
- Logo 使用叶子 SF Symbol。
- 表单以一组卡片承载。
- 主按钮使用主题色，加载时切换为明确等待状态。

### 课表页

- 自定义头部，不使用默认大导航栏。
- 周次切换和刷新位于右上。
- 课程块圆角、低饱和、多色可读。
- 课程详情使用半屏 sheet。
- 重叠课程并排压缩。

### 社区和学业页

- 社区页顶部包含天气、筛选、通知、发布。
- 学业页顶部直接使用横向胶囊一级导航。
- 工具入口使用 `ToolEntryCard`。
- 社区和评教以真实 Supabase 数据展示，同时保留空状态。

### 我的页

- 使用系统 `List + insetGrouped`。
- 个人资料作为第一组。
- 设置和支持入口保持系统设置风格。
- 退出登录单独成组，使用红色。

## 10. 设计维护规则

- 新页面先复用 `AppTheme`、`AppSpacing`、`AppRadius` 和 `AppChrome`，不要新造局部主题。
- 新图标优先使用 SF Symbols。
- 新 sheet 默认支持 medium / large detents，除非内容天然需要全屏。
- 深色模式和主题色切换必须可读。
- 不在 UI 上显示调试文件名、原始请求摘要或工程化错误堆栈。
