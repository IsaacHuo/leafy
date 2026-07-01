# 2026-04-26 iPhone 16e 课表 Auto Layout 卡死复盘

## 现象

- iPhone 17 模拟器上修复后运行正常。
- 换到 iPhone 16e 真机重新构建运行后，App 又进入卡住状态。
- Xcode 控制台出现 `Unable to simultaneously satisfy constraints`。
- 卡住时真机上 `leafy` 进程仍存在，不是普通崩溃退出。

## 环境

- 设备：iPhone 16e
- 系统：iOS 26.4.1
- Bundle ID：`com.isaachuo.leafy`
- 触发页面：已登录后默认进入课表 tab。

## 关键日志

控制台给出的核心冲突是：

```text
UIScrollView.height == 0
UIView.height == 54.52
V:|-(0)-[UIView]
V:[UIView]-(8)-[UIScrollView]
UIScrollView.bottom == UIView.bottom
```

这表示同一个布局里：

- 外层 `TimetableScrollContainer` 已经有约 505pt 的高度。
- 顶部 header 被固定为约 54.52pt。
- scroll view 又被要求从 header 下方 8pt 处一直贴到容器底部。
- 但代码同时给 scroll view 加了 `height == 0`。

Auto Layout 只能打断约束恢复布局；如果这个过程反复发生，就会引发布局抖动甚至卡住。

## 根因

课表容器里原来通过 `GeometryReader` 计算：

```swift
bodyViewportHeight = max(geometry.size.height - headerHeight - AppSpacing.micro, 0)
```

然后把这个值传给 `TimetableScrollContainer`，并在 UIKit 约束里设置：

```swift
axisScrollView.heightAnchor.constraint(equalToConstant: bodyViewportHeight)
bodyScrollView.heightAnchor.constraint(equalToConstant: bodyViewportHeight)
```

真机首次布局时，`GeometryReader` 可能短暂给出一个还没稳定的高度，导致 `bodyViewportHeight == 0`。但同一组视图又已经通过 top/bottom 约束决定了 scroll view 的高度，所以出现了“高度必须是 0”和“必须撑满剩余空间”的冲突。

模拟器没有复现，是因为模拟器的首轮布局时序和真机不同；真机更容易暴露这个短暂 0 高度。

## 修复

去掉 `bodyViewportHeight` 这条手算高度路径，不再给 `axisScrollView` 和 `bodyScrollView` 添加固定高度约束。

现在 scroll view 高度只由稳定的垂直约束决定：

- `axisScrollView.top == cornerContainer.bottom + spacing`
- `axisScrollView.bottom == rootView.bottom`
- `bodyScrollView.top == headerScrollView.bottom + spacing`
- `bodyScrollView.bottom == rootView.bottom`

同时保留前一次修复：

- `UIViewRepresentable.updateUIView` 不再同步强制 `updateLayout()`，改为 `scheduleLayoutUpdate()` 合并到下一轮主队列。
- 日期显示不再在每个格子里新建 `DateFormatter`。

主要修改文件：

- `leafy/Features/Timetable/TimetableView.swift`

## 验证

真机构建通过：

```sh
xcodebuild -project leafy.xcodeproj -scheme leafy -destination 'platform=iOS,id=00008140-000419A80CA2801C' build
```

安装和启动：

```sh
xcrun devicectl device process terminate --device 6F096C6A-438E-55DF-8336-733CD8D6C1E3 --pid <old-pid> --kill
xcrun devicectl device install app --device 6F096C6A-438E-55DF-8336-733CD8D6C1E3 /Users/isaachuo/Library/Developer/Xcode/DerivedData/leafy-gzetbuekzhytpkbwnprnholcyfsu/Build/Products/Debug-iphoneos/leafy.app
xcrun devicectl device process launch --device 6F096C6A-438E-55DF-8336-733CD8D6C1E3 com.isaachuo.leafy
```

修复后重新录制 Time Profiler，导出的 `potential-hangs` 和 `hang-risks` 表没有记录新的 hang 条目。

## 经验

- UIKit 约束里不要同时使用固定高度和 top/bottom 贴边来定义同一个视图的垂直尺寸。
- SwiftUI `GeometryReader` 首轮值可能是临时值，不能把短暂的 0 高度直接变成 UIKit 的强约束。
- 对 `UIViewRepresentable` 来说，布局尺寸最好交给 Auto Layout 的相对约束，而不是反复从 SwiftUI 手算后写入固定约束。
- 模拟器通过不代表真机布局时序一定安全；遇到真机专属卡死，要优先看 Xcode 控制台的 Auto Layout 冲突日志。
