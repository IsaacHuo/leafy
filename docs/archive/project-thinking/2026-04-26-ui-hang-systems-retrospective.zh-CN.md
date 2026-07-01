# 2026-04-26 UI 卡死系统复盘：布局、线程、网络与排查思维

## 宏观分类

这次看起来是“两次卡死”，但从宏观上属于同一类问题：

> UI 响应性问题，具体是 SwiftUI 与 UIKit 桥接层的布局反馈循环和约束不一致导致的主线程卡死。

它不是普通崩溃，不是网络请求卡住，也不是 Supabase 或社区模块导致的业务错误。更准确地说，这是一个跨框架 UI 布局系统问题：

- SwiftUI 负责声明式状态和视图树更新。
- UIKit / Auto Layout 负责 `UIViewRepresentable` 内部的实际布局。
- 两边之间如果同步互相触发，就容易形成重入、约束冲突或布局风暴。
- 只要主线程被这些布局工作长期占用，用户看到的就是“App 卡死”。

## 两个问题的本质

### 问题一：模拟器上的主线程布局重入

现象：

- 进入 App 后 2 秒左右无响应。
- 没有 Swift crash stack。
- `sample <pid>` 显示主线程反复卡在：

```text
TimetableScrollContainer.updateUIView(_:context:)
TimetableScrollContainer.Coordinator.updateLayout()
TimetableView.dayHeader(day:week:)
TimetableView.dateString(for:in:)
```

本质：

- `UIViewRepresentable.updateUIView` 处在 SwiftUI 更新视图树的过程中。
- 里面同步调用 `updateLayout()`，再调用 `rootView.layoutIfNeeded()`。
- UIKit 被强制布局后，又要求 `UIHostingController` 计算 SwiftUI 内容尺寸。
- SwiftUI 重新计算课表 header/body，触发下一轮更新。

这就是典型的布局重入：

```text
SwiftUI update
  -> updateUIView
    -> UIKit layoutIfNeeded
      -> hosted SwiftUI content layout
        -> SwiftUI update again
```

同时，课表 header 是 20 周 × 7 天，共 140 个日期格。之前每个格子都创建 `DateFormatter`，让布局循环的 CPU 成本被放大。

修复方向：

- `updateUIView` 不再同步强制布局。
- 改成 `scheduleLayoutUpdate()`，把布局合并到下一轮主队列。
- 日期字符串计算去掉每格 `DateFormatter`，改用轻量的 `Calendar` 组件格式化。

### 问题二：真机 iPhone 16e 上的 Auto Layout 约束冲突

现象：

- iPhone 17 模拟器修好后正常。
- iPhone 16e 真机再次卡死。
- Xcode 控制台出现 `Unable to simultaneously satisfy constraints`。
- 核心冲突是：

```text
UIScrollView.height == 0
header height == 54.52
scroll view top == header bottom + 8
scroll view bottom == container bottom
container height == 505
```

本质：

- `GeometryReader` 首轮布局时可能给出临时高度。
- 代码把 `bodyViewportHeight = max(geometry.height - headerHeight - spacing, 0)` 传给 UIKit。
- 真机上这个值短暂变成 0。
- 但 scroll view 同时又有 top/bottom 贴边约束，已经能从容器高度推导出自身高度。
- 于是同一个视图被两套规则同时定义高度：

```text
height == 0
top + bottom imply height > 0
```

Auto Layout 只能不断打断其中一条约束。这个过程本身会触发布局更新，如果叠加 SwiftUI/UIKit 桥接，就会演变成卡死。

修复方向：

- 删除 `bodyViewportHeight` 固定高度约束。
- `axisScrollView` 和 `bodyScrollView` 的高度只由 top/bottom 约束决定。
- 保留 `axisWidth`、`headerHeight` 这类稳定尺寸约束。

## 为什么会误判成网络或社区问题

这次排查里有一个干扰项：最近修改过 `CommunityViews.swift`，社区模块也会触发 Supabase Auth、Keychain 和网络请求。

但卡死发生在默认课表 tab。真实证据指向课表：

- 模拟器 `sample` 里主线程在 `TimetableScrollContainer`。
- 真机 Xcode 控制台里的冲突对象也是 `TimetableScrollContainer` 里的 UIKit view host。
- Supabase / Keychain 日志出现在点进社区或认证流程时，不是主线程长期卡住的根因。

这提醒我们：最近改动可以作为线索，但不能作为结论。结论必须来自运行时证据。

## 线程视角

UI 卡死的第一判断不是“哪里报错”，而是：

```text
主线程现在在做什么？
```

这次两个问题都属于主线程响应性问题：

- 问题一：主线程在同步布局重入里忙等，CPU 被布局计算占住。
- 问题二：主线程被 Auto Layout 约束恢复和 SwiftUI/UIKit 重布局反复牵引。

以后遇到类似现象，先分三类：

1. Crash：进程退出，有 crash log。
2. Hang：进程仍在，主线程不处理事件。
3. Slow async：主线程可动，但某个数据/网络结果迟迟没回来。

对应工具：

- Crash：看 crash report 和 exception backtrace。
- Hang：用 `sample <pid>`、Time Profiler、`thread backtrace all`。
- Slow async：看任务日志、URLSession、超时、状态机。

## 网络视角

网络问题通常不会直接让整个 App 卡死，除非出现这些情况：

- 在主线程同步等待网络结果。
- 在 `@MainActor` 上做大量解析或数据库写入。
- 网络回调更新状态后触发无限刷新。
- 任务取消/重试逻辑形成循环。

本次排查中，网络被排除的原因是：

- 卡死时主线程采样没有显示 URLSession、Supabase fetch、Keychain 等长期占用主线程。
- 社区请求有 timeout 包装。
- 真机约束日志直接暴露了布局冲突。

但这不代表网络层可以忽略。社区模块仍然需要保持这些边界：

- 网络请求必须离开主线程。
- 解析和 hydration 不要在主线程做重活。
- UI 状态更新只做轻量赋值。
- 进入/退出页面时任务要可取消。
- 网络超时要转化成 UI 错误，而不是让视图无限 loading。

## 布局视角

这两个问题都说明：课表是项目里布局风险最高的界面。

原因：

- 它是高密度网格。
- 同时有横向周滚动、纵向节次滚动、固定 header、固定 axis。
- SwiftUI 外层管理状态，UIKit 内层管理同步滚动。
- 内容尺寸由 `UIHostingController` 托管的 SwiftUI view 计算。

因此课表布局需要遵守几条硬规则：

1. `UIViewRepresentable.updateUIView` 里不要同步强制 `layoutIfNeeded()`。
2. 同一个方向的尺寸只能有一个来源。
3. 如果已经有 top/bottom 约束，就不要再加固定 height。
4. `GeometryReader` 的首轮值不能被当作稳定事实。
5. SwiftUI `body`、cell、header 里不要创建昂贵对象。
6. UIKit scroll offset 同步要避免写状态后立即触发下一轮布局。

## 思维结构：以后如何排查类似问题

### 第一层：先定性

先回答：

```text
这是 crash、hang，还是 slow state？
```

判断方式：

- 进程没了：crash 或被系统杀。
- 进程还在但 UI 不动：hang。
- UI 能点但数据不来：slow state / network / backend。

### 第二层：找主线程证据

如果是 hang，不要先读所有代码。直接看主线程：

```sh
pgrep -fl leafy
sample <pid> 5 -file /tmp/leafy_sample.txt
```

真机可以用：

```sh
xcrun xctrace record --template 'Time Profiler' --device <udid> --attach <pid> --time-limit 5s --output /tmp/leafy.trace --no-prompt
```

目标不是“收集很多日志”，而是回答：

```text
主线程正在布局、等待锁、跑网络、做数据库，还是空闲？
```

### 第三层：按边界定位

把系统分成几个边界：

- SwiftUI 状态边界：`@State`、`@Query`、`@ObservedObject`、`.task`、`.onChange`
- UIKit 桥接边界：`UIViewRepresentable`、`UIHostingController`、`UIScrollViewDelegate`
- 数据边界：SwiftData、缓存、文件 IO
- 网络边界：Supabase、教务系统、URLSession
- 设备边界：模拟器 vs 真机、不同屏幕尺寸、不同 iOS patch 版本

这次的问题落在 SwiftUI/UIKit 桥接边界。

### 第四层：检查不变量

布局不变量：

- 一个 view 的高度不能既由固定 height 决定，又由 top/bottom 决定。
- `updateUIView` 不能同步触发会反向要求 SwiftUI 重新布局的工作。
- 滚动同步不能在 delegate 中制造状态写入循环。

线程不变量：

- 主线程只做轻量 UI 状态和布局，不做重计算。
- `@MainActor` 方法里不要包进不可控的同步工作。
- 网络、解析、数据库重活都要能离开主线程。

状态不变量：

- 页面出现触发的任务必须可取消。
- 状态更新要有去重，避免同一个值反复写入。
- 自动定位当前课程这类逻辑不能和用户滚动互相抢控制权。

### 第五层：用最小修复打断循环

对 hang 类问题，不要一开始大重构。先打断循环：

- 同步改异步合并。
- 删除重复约束。
- 去掉布局里的重对象创建。
- 给状态写入加相等判断。
- 给异步任务加取消和超时。

这次就是先把 `updateUIView -> updateLayout` 改成合并调度，再删除 0 高度固定约束。

## 项目层面的改进建议

### 1. 给课表桥接层加注释和约束原则

`TimetableScrollContainer` 是高风险桥接层，建议在代码附近写明：

- 不要在 `updateUIView` 同步 `layoutIfNeeded()`。
- body/axis scroll view 高度由 top/bottom 约束决定。
- 不要重新引入 `bodyViewportHeight` 固定高度。

### 2. 建立 UI Hang 排查清单

可以放在 `docs/archive/project-thinking` 或 `docs/archive/error-summaries`：

- 进程是否还在？
- 主线程采样在哪？
- 控制台是否有 Auto Layout 冲突？
- 是否有 Main Thread Checker / Hang Risk？
- 最近改动是否只是干扰项？
- 模拟器和真机是否都验证？

### 3. 对高密度视图做性能约束

课表、社区列表、成绩列表都属于高密度 UI。原则：

- cell/body 中不创建 formatter。
- 大量数据的转换在 view model 或 model 层预处理。
- 图片、网络、解析不进入 body。
- SwiftUI body 只描述 UI，不承担重计算。

### 4. 真机验证要成为发布前固定步骤

模拟器和真机的差异包括：

- 首轮布局时序不同。
- Auto Layout 恢复策略不同。
- 屏幕尺寸、安全区、动态字体可能不同。
- 真机性能和调度更接近用户环境。

至少对课表这种核心页，要在真机跑一遍启动、切 tab、滚动、回到当前课程。

### 5. 网络问题要用状态机思维

虽然这次不是网络根因，但社区和教务请求仍然要按状态机看：

```text
idle -> loading -> success / empty / failed / cancelled
```

避免：

- 页面反复 appear 导致重复请求。
- 请求失败后状态又触发请求。
- `@MainActor` 中等待网络或做重解析。
- 取消后仍写入 UI 状态。

## 这次最重要的经验

这次不是“某一行写错了”那么简单，而是系统边界没有被明确管理：

- SwiftUI 的更新周期有自己的节奏。
- UIKit 的 Auto Layout 有自己的约束求解规则。
- `UIViewRepresentable` 正好站在两套系统的交界处。

在这个交界处，最危险的操作是：

```text
同步布局 + 状态写入 + 手算尺寸 + 重复约束
```

以后只要看到这些组合，就要优先怀疑 UI hang。

最终的思维框架可以压缩成一句话：

> 先判断卡死类型，再抓主线程证据，然后按 SwiftUI/UIKit/数据/网络边界找反馈循环，最后用最小改动打断循环并固化不变量。
