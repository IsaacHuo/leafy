# 2026-04-26 Timetable Layout Hang

## Symptom

- App entered the main screen and became unresponsive after roughly 2 seconds.
- It looked like a freeze rather than a normal Swift crash.
- iPhone 17 simulator logs showed an earlier `SIGKILL(9)`, but no useful Swift exception stack.

## Environment

- Simulator: iPhone 17, iOS 26.4
- Bundle identifier: `com.isaachuo.leafy`
- Main entry path: logged-in user opens directly into the timetable tab.

## Investigation

Useful commands:

```sh
xcrun simctl list devices available
xcrun simctl spawn booted log show --last 15m --style compact --predicate 'process == "leafy" OR process CONTAINS[c] "leafy" OR senderImagePath CONTAINS[c] "leafy" OR composedMessage CONTAINS[c] "leafy"'
pgrep -fl leafy
sample <leafy-pid> 5 -file /tmp/leafy_sample_<pid>.txt
```

The decisive evidence came from `sample`. The main thread was repeatedly inside:

```text
TimetableScrollContainer.updateUIView(_:context:)
TimetableScrollContainer.Coordinator.updateLayout()
TimetableView.dayHeader(day:week:)
TimetableView.dateString(for:in:)
```

This meant the issue was a main-thread layout loop in the timetable screen, not a Supabase/community networking failure.

## Root Cause

`UIViewRepresentable.updateUIView` was calling `updateLayout()` synchronously. `updateLayout()` then called `rootView.layoutIfNeeded()` while SwiftUI was already updating the view tree.

That created a reentrant loop:

1. SwiftUI updates `TimetableScrollContainer`.
2. `updateUIView` immediately forces UIKit layout.
3. UIKit asks hosted SwiftUI content for layout/content size.
4. SwiftUI recomputes timetable header/body views.
5. The representable updates again and repeats.

The problem was amplified because the timetable header renders 20 weeks by 7 days. Each date label previously created a new `DateFormatter`, so the repeated layout pass became expensive enough to lock the main thread.

## Fix

Changed `TimetableScrollContainer.updateUIView` so it schedules a coalesced layout update on the next main-queue turn instead of forcing layout synchronously during SwiftUI's update pass.

Touched area:

- `leafy/Features/Timetable/TimetableView.swift`
- `updateUIView(_:context:)`
- `Coordinator.scheduleLayoutUpdate()`
- `Coordinator.scheduleDeferredScrollRetry()`

Also replaced per-cell `DateFormatter` creation with lightweight `Calendar` date component formatting:

- `monthString()`
- `dateString(for:in:)`

## Verification

Build:

```sh
xcodebuild -project leafy.xcodeproj -scheme leafy -destination 'platform=iOS Simulator,name=iPhone 17' build
```

Runtime check:

```sh
xcrun simctl terminate booted com.isaachuo.leafy
xcrun simctl install booted /Users/isaachuo/Library/Developer/Xcode/DerivedData/leafy-gzetbuekzhytpkbwnprnholcyfsu/Build/Products/Debug-iphonesimulator/leafy.app
xcrun simctl launch booted com.isaachuo.leafy
sample <new-leafy-pid> 3 -file /tmp/leafy_sample_after_fix.txt
```

After the fix, the new sample showed the main thread mostly waiting in `mach_msg`, which is normal idle behavior. Filtering logs from the new launch time did not show new `SIGKILL`, `Hang Risk`, or `sqlite3_open_v2` hang warnings for the running process.

## Lessons

- Avoid calling `layoutIfNeeded()` synchronously from `UIViewRepresentable.updateUIView` unless absolutely necessary.
- When bridging SwiftUI and UIKit, coalesce layout work with `DispatchQueue.main.async` to avoid reentrant SwiftUI update/layout cycles.
- Keep layout-time computations cheap, especially inside repeated grids. Do not create heavy formatters inside many cells during body/layout recomputation.
- For freezes without crash stacks, use `sample <pid>` early. It is often more useful than simulator logs.
