# 2026-04-26 课表布局卡死复盘

## 现象

- App 进入主界面后大约 2 秒直接无响应。
- 表现更像主线程卡死，不是普通 Swift 崩溃。
- iPhone 17 模拟器日志里能看到一次较早的 `SIGKILL(9)`，但没有可用的 Swift 异常堆栈。

## 环境

- 模拟器：iPhone 17，iOS 26.4
- Bundle ID：`com.isaachuo.leafy`
- 入口路径：已登录用户启动后默认进入课表 tab。

## 排查过程

关键命令：

```sh
xcrun simctl list devices available
xcrun simctl spawn booted log show --last 15m --style compact --predicate 'process == "leafy" OR process CONTAINS[c] "leafy" OR senderImagePath CONTAINS[c] "leafy" OR composedMessage CONTAINS[c] "leafy"'
pgrep -fl leafy
sample <leafy-pid> 5 -file /tmp/leafy_sample_<pid>.txt
```

真正定位问题的是 `sample`。采样显示主线程反复卡在这条链路：

```text
TimetableScrollContainer.updateUIView(_:context:)
TimetableScrollContainer.Coordinator.updateLayout()
TimetableView.dayHeader(day:week:)
TimetableView.dateString(for:in:)
```

这说明问题不是 Supabase 或社区网络请求，而是课表页的主线程布局循环。

## 根因

`UIViewRepresentable.updateUIView` 里同步调用了 `updateLayout()`，而 `updateLayout()` 里又立即执行 `rootView.layoutIfNeeded()`。

问题在于：`updateUIView` 本来就处在 SwiftUI 更新视图树的过程中，这时同步强制 UIKit 布局，会让 UIKit 反过来要求 `UIHostingController` 计算 SwiftUI 内容尺寸，形成重入。

循环大致是：

1. SwiftUI 更新 `TimetableScrollContainer`。
2. `updateUIView` 立刻强制 UIKit 布局。
3. UIKit 要求 SwiftUI 托管内容重新计算尺寸。
4. SwiftUI 重算课表 header/body。
5. `UIViewRepresentable` 再次更新，继续重复。

这个问题被课表头部放大了：课表一次渲染 20 周 × 7 天，共 140 个日期格。之前每个日期格都会新建 `DateFormatter`，布局循环里反复创建昂贵对象，最终把主线程打满。

## 修复

把 `TimetableScrollContainer.updateUIView` 从“同步强制布局”改成“下一轮主队列合并布局”：

- `leafy/Features/Timetable/TimetableView.swift`
- `updateUIView(_:context:)`
- `Coordinator.scheduleLayoutUpdate()`
- `Coordinator.scheduleDeferredScrollRetry()`

同时把日期显示从每个格子新建 `DateFormatter`，改成用 `Calendar` 取日期组件后格式化：

- `monthString()`
- `dateString(for:in:)`

## 验证

构建：

```sh
xcodebuild -project leafy.xcodeproj -scheme leafy -destination 'platform=iOS Simulator,name=iPhone 17' build
```

运行验证：

```sh
xcrun simctl terminate booted com.isaachuo.leafy
xcrun simctl install booted /Users/isaachuo/Library/Developer/Xcode/DerivedData/leafy-gzetbuekzhytpkbwnprnholcyfsu/Build/Products/Debug-iphonesimulator/leafy.app
xcrun simctl launch booted com.isaachuo.leafy
sample <new-leafy-pid> 3 -file /tmp/leafy_sample_after_fix.txt
```

修复后，新进程采样显示主线程大部分时间在 `mach_msg` 等待事件，这是正常空闲状态。按新启动时间过滤日志，也没有新的 `SIGKILL`、`Hang Risk` 或 `sqlite3_open_v2` 卡顿告警。

## 经验

- 不要轻易在 `UIViewRepresentable.updateUIView` 里同步调用 `layoutIfNeeded()`。
- SwiftUI 和 UIKit 混用时，布局更新最好用 `DispatchQueue.main.async` 合并到下一轮主队列，避免重入 SwiftUI 更新流程。
- 布局阶段的计算必须便宜，尤其是网格、列表、课表这种重复单元很多的界面。
- 遇到“卡死但没有崩溃堆栈”的问题，优先用 `sample <pid>` 看主线程正在做什么，通常比只看 simulator log 更快定位。
