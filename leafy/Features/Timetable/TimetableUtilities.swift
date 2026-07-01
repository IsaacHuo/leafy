import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import UserNotifications

nonisolated enum TimetablePeriodSchedule {
    struct Slot: Hashable {
        let period: Int
        let startHour: Int
        let startMinute: Int
        let endHour: Int
        let endMinute: Int

        var startText: String {
            String(format: "%02d:%02d", startHour, startMinute)
        }

        var endText: String {
            String(format: "%02d:%02d", endHour, endMinute)
        }
    }

    static let slots: [Slot] = [
        Slot(period: 1, startHour: 8, startMinute: 0, endHour: 8, endMinute: 45),
        Slot(period: 2, startHour: 8, startMinute: 50, endHour: 9, endMinute: 35),
        Slot(period: 3, startHour: 9, startMinute: 50, endHour: 10, endMinute: 35),
        Slot(period: 4, startHour: 10, startMinute: 40, endHour: 11, endMinute: 25),
        Slot(period: 5, startHour: 11, startMinute: 30, endHour: 12, endMinute: 15),
        Slot(period: 6, startHour: 13, startMinute: 30, endHour: 14, endMinute: 15),
        Slot(period: 7, startHour: 14, startMinute: 20, endHour: 15, endMinute: 5),
        Slot(period: 8, startHour: 15, startMinute: 20, endHour: 16, endMinute: 5),
        Slot(period: 9, startHour: 16, startMinute: 10, endHour: 16, endMinute: 55),
        Slot(period: 10, startHour: 18, startMinute: 30, endHour: 19, endMinute: 15),
        Slot(period: 11, startHour: 19, startMinute: 20, endHour: 20, endMinute: 5),
        Slot(period: 12, startHour: 20, startMinute: 10, endHour: 20, endMinute: 55),
        Slot(period: 13, startHour: 21, startMinute: 0, endHour: 21, endMinute: 45)
    ]

    static func slot(for period: Int) -> Slot? {
        slots.first { $0.period == period }
    }

    static func periodForFocus(containing date: Date) -> Slot? {
        let minutes = minutesSinceStartOfDay(for: date)
        return slots.first { minutes <= $0.endHour * 60 + $0.endMinute } ?? slots.last
    }

    static func period(containing date: Date) -> Slot? {
        let minutes = minutesSinceStartOfDay(for: date)
        return slots.first { slot in
            let start = slot.startHour * 60 + slot.startMinute
            let end = slot.endHour * 60 + slot.endMinute
            return (start...end).contains(minutes)
        }
    }

    static func defaultStudyPeriod(for date: Date = Date()) -> Int {
        periodForFocus(containing: date)?.period ?? 1
    }

    static func startDate(for course: Course, week: Int) -> Date? {
        guard let firstPeriod = course.duration.min(),
              let slot = slot(for: firstPeriod)
        else {
            return nil
        }

        let dayOffset = (week - 1) * 7 + (course.dayOfWeek - 1)
        let calendar = Calendar.current
        guard let date = calendar.date(byAdding: .day, value: dayOffset, to: SemesterConfig.startOfSemesterDate) else {
            return nil
        }

        return calendar.date(
            bySettingHour: slot.startHour,
            minute: slot.startMinute,
            second: 0,
            of: date
        )
    }

    static func startDate(week: Int, dayOfWeek: Int, period: Int) -> Date? {
        guard let slot = slot(for: period) else { return nil }

        let dayOffset = (week - 1) * 7 + (dayOfWeek - 1)
        let calendar = Calendar.current
        guard let date = calendar.date(byAdding: .day, value: dayOffset, to: SemesterConfig.startOfSemesterDate) else {
            return nil
        }

        return calendar.date(
            bySettingHour: slot.startHour,
            minute: slot.startMinute,
            second: 0,
            of: date
        )
    }

    static func endDate(week: Int, dayOfWeek: Int, period: Int) -> Date? {
        guard let slot = slot(for: period) else { return nil }

        let dayOffset = (week - 1) * 7 + (dayOfWeek - 1)
        let calendar = Calendar.current
        guard let date = calendar.date(byAdding: .day, value: dayOffset, to: SemesterConfig.startOfSemesterDate) else {
            return nil
        }

        return calendar.date(
            bySettingHour: slot.endHour,
            minute: slot.endMinute,
            second: 0,
            of: date
        )
    }

    static func endDate(for course: Course, week: Int) -> Date? {
        guard let lastPeriod = course.duration.max(),
              let slot = slot(for: lastPeriod)
        else {
            return nil
        }

        let dayOffset = (week - 1) * 7 + (course.dayOfWeek - 1)
        let calendar = Calendar.current
        guard let date = calendar.date(byAdding: .day, value: dayOffset, to: SemesterConfig.startOfSemesterDate) else {
            return nil
        }

        return calendar.date(
            bySettingHour: slot.endHour,
            minute: slot.endMinute,
            second: 0,
            of: date
        )
    }

    private static func minutesSinceStartOfDay(for date: Date) -> Int {
        let calendar = Calendar.current
        return calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
    }

    static func periodRange(overlapping startDate: Date, endDate: Date) -> ClosedRange<Int>? {
        guard endDate > startDate else { return nil }
        let startMinutes = minutesSinceStartOfDay(for: startDate)
        let endMinutes = minutesSinceStartOfDay(for: endDate)
        let periods = slots.compactMap { slot -> Int? in
            let slotStart = slot.startHour * 60 + slot.startMinute
            let slotEnd = slot.endHour * 60 + slot.endMinute
            return startMinutes < slotEnd && endMinutes > slotStart ? slot.period : nil
        }

        guard let first = periods.first, let last = periods.last else { return nil }
        return first...last
    }
}

enum TimetableCacheMetadata {
    private static let lastSyncKey = "timetable.lastSyncAt"
    private static let lastFailureKey = "timetable.lastFailureMessage"

    static var lastSyncAt: Date? {
        get {
            migrateLegacyValues()
            return UserDefaults.standard.object(forKey: scoped(lastSyncKey)) as? Date
        }
        set { UserDefaults.standard.set(newValue, forKey: scoped(lastSyncKey)) }
    }

    static var lastFailureMessage: String? {
        get {
            migrateLegacyValues()
            return UserDefaults.standard.string(forKey: scoped(lastFailureKey))
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: scoped(lastFailureKey))
            } else {
                UserDefaults.standard.removeObject(forKey: scoped(lastFailureKey))
            }
        }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: scoped(lastSyncKey))
        UserDefaults.standard.removeObject(forKey: scoped(lastFailureKey))
    }

    private static func scoped(_ key: String) -> String {
        CampusScopedDefaults.key(key)
    }

    private static func migrateLegacyValues() {
        CampusScopedDefaults.migrateLegacyValuesIfNeeded(
            keys: [lastSyncKey, lastFailureKey],
            migrationID: "timetableMetadata"
        )
    }
}

enum TimetableAdaptiveMode: Equatable {
    case weekGrid
    case agendaList
}

struct TimetableResponsiveLayout {
    struct Metrics: Equatable {
        let rowHeight: CGFloat
        let rowSpacing: CGFloat
        let cardInset: CGFloat
        let laneSpacing: CGFloat
        let dayColumnWidth: CGFloat
        let daySpacing: CGFloat
        let weekSpacing: CGFloat
        let gridHeight: CGFloat
        let allowsVerticalScroll: Bool
        let weekStride: CGFloat
        let containerWidth: CGFloat
        let containerHeight: CGFloat
        let horizontalPadding: CGFloat
        let mode: TimetableAdaptiveMode
    }

    static func metrics(
        for size: CGSize,
        dayCount: Int,
        totalClasses: Int,
        axisWidth: CGFloat,
        headerHeight: CGFloat,
        horizontalPadding: CGFloat,
        daySpacing: CGFloat,
        weekSpacing: CGFloat,
        rowSpacing: CGFloat,
        minimumRowHeight: CGFloat,
        cardInset: CGFloat,
        laneSpacing: CGFloat,
        bottomClearance: CGFloat,
        controlScale: CGFloat,
        interPaneSpacing: CGFloat,
        allowsAgendaList: Bool = true
    ) -> Metrics {
        let resolvedDayCount = max(dayCount, 1)
        let contentWidth = max(size.width - horizontalPadding * 2, 0)
        let bodyViewportWidth = max(contentWidth - axisWidth - interPaneSpacing, 0)
        let rawDayColumnWidth = (
            bodyViewportWidth - CGFloat(max(resolvedDayCount - 1, 0)) * daySpacing
        ) / CGFloat(resolvedDayCount)
        let dayColumnWidth = max(rawDayColumnWidth, 1)
        let bodyVisibleHeight = max(size.height - headerHeight - interPaneSpacing, 0)
        let bodyViewportHeight = max(bodyVisibleHeight - bottomClearance, 0)
        let rowSpacingTotal = CGFloat(max(totalClasses - 1, 0)) * rowSpacing
        let fittedRowHeight = (bodyViewportHeight - rowSpacingTotal) / CGFloat(max(totalClasses, 1))
        let rowHeight = max(fittedRowHeight, minimumRowHeight)
        let gridHeight = CGFloat(totalClasses) * rowHeight + rowSpacingTotal
        let allowsVerticalScroll = gridHeight > bodyVisibleHeight + 0.5
        let weekContentWidth = CGFloat(resolvedDayCount) * dayColumnWidth
            + CGFloat(max(resolvedDayCount - 1, 0)) * daySpacing
        let canShowReadableGrid = dayColumnWidth >= 72 * controlScale
            && bodyVisibleHeight >= 360 * controlScale

        return Metrics(
            rowHeight: rowHeight,
            rowSpacing: rowSpacing,
            cardInset: cardInset,
            laneSpacing: laneSpacing,
            dayColumnWidth: dayColumnWidth,
            daySpacing: daySpacing,
            weekSpacing: weekSpacing,
            gridHeight: gridHeight,
            allowsVerticalScroll: allowsVerticalScroll,
            weekStride: weekContentWidth + weekSpacing,
            containerWidth: contentWidth,
            containerHeight: size.height,
            horizontalPadding: horizontalPadding,
            mode: allowsAgendaList && !canShowReadableGrid ? .agendaList : .weekGrid
        )
    }
}

enum TimetableShareBuilder {
    static func text(for course: Course, note: String? = nil) -> String {
        var lines = [
            course.courseName,
            L10n.text("教师：%@", course.teacher.isEmpty ? L10n.text("未填写") : course.teacher),
            L10n.text("地点：%@", course.locationTextForShare),
            L10n.text("周次：%@", course.weeksTextForShare),
            L10n.text("节次：%@", course.durationTextForShare)
        ]

        if let note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append(L10n.text("备注：%@", note))
        }

        return lines.joined(separator: "\n")
    }

    static func todayText(courses: [Course], exams: [ExamArrangement], date: Date = Date()) -> String {
        let schedule = SemesterConfig.weekAndDay(for: date)
        let todayCourses = courses
            .filter { $0.weeks.contains(schedule.week) && $0.dayOfWeek == schedule.day }
            .sortedByStartPeriod()

        var lines = [L10n.text("%@ 今日课表", AppBrand.displayName), DateFormatters.header.string(from: date)]
        if todayCourses.isEmpty {
            lines.append(L10n.text("今日无课"))
        } else {
            lines.append(contentsOf: todayCourses.map { course in
                "\(course.durationTextForShare) \(course.courseName) @ \(course.locationTextForShare)"
            })
        }

        if let exam = exams.nextRelevantExam(from: date) {
            lines.append(L10n.text("考试：%@ %@ %@ @ %@", exam.name, exam.date, exam.start, exam.location))
        }

        return lines.joined(separator: "\n")
    }
}

@MainActor
enum TimetableNoteResolver {
    static func effectiveNote(
        for course: Course,
        week: Int,
        courseNotes: [CourseNote],
        occurrenceNotes: [CourseOccurrenceNote]
    ) -> String? {
        let occurrenceKey = course.occurrenceKey(week: week)
        if let occurrenceText = occurrenceNotes
            .filter({ $0.occurrenceKey == occurrenceKey })
            .sorted(by: latestFirst)
            .compactMap({ trimmed($0.text) })
            .first {
            return occurrenceText
        }

        return courseNotes
            .filter { $0.courseKey == course.stableCourseKey }
            .sorted(by: latestFirst)
            .compactMap { trimmed($0.text) }
            .first
    }

    static func hasEffectiveNote(
        for course: Course,
        week: Int,
        courseNotes: [CourseNote],
        occurrenceNotes: [CourseOccurrenceNote]
    ) -> Bool {
        effectiveNote(
            for: course,
            week: week,
            courseNotes: courseNotes,
            occurrenceNotes: occurrenceNotes
        ) != nil
    }

    static func courseNotesByKey(_ notes: [CourseNote]) -> [String: String] {
        Dictionary(
            notes
                .sorted(by: latestFirst)
                .compactMap { note in
                    trimmed(note.text).map { (note.courseKey, $0) }
                },
            uniquingKeysWith: { first, _ in first }
        )
    }

    static func occurrenceNotesByKey(_ notes: [CourseOccurrenceNote]) -> [String: String] {
        Dictionary(
            notes
                .sorted(by: latestFirst)
                .compactMap { note in
                    trimmed(note.text).map { (note.occurrenceKey, $0) }
                },
            uniquingKeysWith: { first, _ in first }
        )
    }

    static func effectiveNote(
        for course: Course,
        week: Int,
        courseNotesByKey: [String: String],
        occurrenceNotesByKey: [String: String]
    ) -> String? {
        occurrenceNotesByKey[course.occurrenceKey(week: week)]
            ?? courseNotesByKey[course.stableCourseKey]
    }

    static func hasEffectiveNote(
        for course: Course,
        week: Int,
        courseNotesByKey: [String: String],
        occurrenceNotesByKey: [String: String]
    ) -> Bool {
        effectiveNote(
            for: course,
            week: week,
            courseNotesByKey: courseNotesByKey,
            occurrenceNotesByKey: occurrenceNotesByKey
        ) != nil
    }

    private static func latestFirst(_ lhs: CourseNote, _ rhs: CourseNote) -> Bool {
        lhs.updatedAt > rhs.updatedAt
    }

    private static func latestFirst(_ lhs: CourseOccurrenceNote, _ rhs: CourseOccurrenceNote) -> Bool {
        lhs.updatedAt > rhs.updatedAt
    }

    private static func trimmed(_ text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

@MainActor
enum TimetableNotificationManager {
    static let reminderOptions = [0, 5, 20, 30]
    static let customReminderRange = 1...180

    static func normalizedReminderMinutes(_ minutes: Int) -> Int {
        guard minutes > 0 else { return 0 }
        return min(max(minutes, customReminderRange.lowerBound), customReminderRange.upperBound)
    }

    static func resolvedAnchorPeriod(_ anchorPeriod: Int?, for course: Course) -> Int? {
        let sortedPeriods = course.duration.sorted()
        guard let firstPeriod = sortedPeriods.first else { return nil }
        guard let anchorPeriod, sortedPeriods.contains(anchorPeriod) else {
            return firstPeriod
        }
        return anchorPeriod
    }

    static func reminderStartDate(for course: Course, week: Int, anchorPeriod: Int?) -> Date? {
        guard let period = resolvedAnchorPeriod(anchorPeriod, for: course) else {
            return nil
        }
        return TimetablePeriodSchedule.startDate(
            week: week,
            dayOfWeek: course.dayOfWeek,
            period: period
        )
    }

    static func reminderTriggerDate(for course: Course, week: Int, minutesBefore: Int, anchorPeriod: Int?) -> Date? {
        guard let startDate = reminderStartDate(for: course, week: week, anchorPeriod: anchorPeriod) else {
            return nil
        }
        return Calendar.current.date(
            byAdding: .minute,
            value: -normalizedReminderMinutes(minutesBefore),
            to: startDate
        )
    }

    static func applyReminder(minutesBefore: Int, anchorPeriod: Int?, course: Course) async throws {
        cancelReminder(for: course)
        let minutesBefore = normalizedReminderMinutes(minutesBefore)
        guard minutesBefore > 0 else { return }

        let center = try await authorizedNotificationCenter()

        let now = Date()
        for week in course.weeks.sorted() {
            guard let triggerDate = reminderTriggerDate(
                for: course,
                week: week,
                minutesBefore: minutesBefore,
                anchorPeriod: anchorPeriod
            ),
                triggerDate > now
            else {
                continue
            }

            let content = UNMutableNotificationContent()
            content.title = course.courseName
            content.body = L10n.text("%d 分钟后上课，地点：%@", minutesBefore, course.locationTextForShare)
            content.sound = .default

            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(
                identifier: notificationID(courseKey: course.stableCourseKey, week: week),
                content: content,
                trigger: trigger
            )
            try await center.add(request)
        }
    }

    static func applyReminder(minutesBefore: Int, course: Course) async throws {
        try await applyReminder(minutesBefore: minutesBefore, anchorPeriod: nil, course: course)
    }

    static func applyReminder(for reminder: TimetableCellReminder) async throws -> Bool {
        cancelReminder(for: reminder)
        let minutesBefore = normalizedReminderMinutes(reminder.minutesBefore)
        guard minutesBefore > 0 else { return false }

        guard let startDate = reminder.resolvedStartDate,
              let triggerDate = Calendar.current.date(byAdding: .minute, value: -minutesBefore, to: startDate),
              triggerDate > Date()
        else {
            return false
        }

        let center = try await authorizedNotificationCenter()
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        if reminder.locationText.isEmpty {
            content.body = L10n.text("%d 分钟后有课表日程：第 %d 节。", minutesBefore, reminder.period)
        } else {
            content.body = L10n.text("%d 分钟后有课表日程：第 %d 节，地点：%@", minutesBefore, reminder.period, reminder.locationText)
        }
        content.sound = .default

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: notificationID(cellKey: reminder.cellKey),
            content: content,
            trigger: trigger
        )
        try await center.add(request)
        return true
    }

    static func cancelReminder(for course: Course) {
        let ids = course.weeks.map { notificationID(courseKey: course.stableCourseKey, week: $0) }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    static func cancelReminder(for reminder: TimetableCellReminder) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [
            notificationID(cellKey: reminder.cellKey)
        ])
    }

    static func cancelAllCourseReminders(courses: [Course]) {
        let ids = courses.flatMap { course in
            course.weeks.map { notificationID(courseKey: course.stableCourseKey, week: $0) }
        }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    static func cancelAllCellReminders(_ reminders: [TimetableCellReminder]) {
        let ids = reminders.map { notificationID(cellKey: $0.cellKey) }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    private static func authorizedNotificationCenter() async throws -> UNUserNotificationCenter {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            guard granted else { throw TimetableNotificationError.permissionDenied }
        } else if settings.authorizationStatus == .denied {
            throw TimetableNotificationError.permissionDenied
        }

        return center
    }

    private static func notificationID(courseKey: String, week: Int) -> String {
        let stableID = courseKey.unicodeScalars
            .map { String(format: "%02X", $0.value) }
            .joined()
            .prefix(64)
        return "leafy.courseReminder.\(stableID).\(week)"
    }

    private static func notificationID(cellKey: String) -> String {
        let stableID = cellKey.unicodeScalars
            .map { String(format: "%02X", $0.value) }
            .joined()
            .prefix(64)
        return "leafy.cellReminder.\(stableID)"
    }
}

enum TimetableNotificationError: LocalizedError {
    case permissionDenied

    var errorDescription: String? {
        L10n.text("未获得通知权限，请在系统设置中允许 %@ 发送通知。", AppBrand.displayName)
    }
}

#if canImport(UIKit)
struct LeafySystemShare: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#elseif canImport(AppKit)
struct LeafySystemShare: NSViewRepresentable {
    let activityItems: [Any]

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        DispatchQueue.main.async {
            context.coordinator.present(items: activityItems, from: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class Coordinator {
        private var picker: NSSharingServicePicker?

        func present(items: [Any], from view: NSView) {
            guard !items.isEmpty, view.window != nil else { return }
            let picker = NSSharingServicePicker(items: items)
            self.picker = picker
            picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        }
    }
}
#endif

typealias ShareSheet = LeafySystemShare

extension Course {
    var formattedLocationText: String {
        let cleanLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanRoom = room.trimmingCharacters(in: .whitespacesAndNewlines)

        if cleanLocation.isEmpty {
            return cleanRoom.isEmpty ? L10n.text("未填写") : cleanRoom
        }

        if cleanRoom.isEmpty {
            return cleanLocation
        }

        let compactLocation = cleanLocation.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        let compactRoom = cleanRoom.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        if compactLocation == compactRoom || compactLocation.hasSuffix(compactRoom) {
            return cleanLocation
        }

        if compactRoom.hasPrefix(compactLocation) {
            return cleanRoom
        }

        return "\(cleanLocation) \(cleanRoom)"
    }

    var locationTextForShare: String {
        formattedLocationText
    }

    var durationTextForShare: String {
        guard let start = duration.min(), let end = duration.max() else { return L10n.text("未填写") }
        if start == end { return L10n.text("第 %d 节", start) }
        return L10n.text("第 %d-%d 节", start, end)
    }

    var weeksTextForShare: String {
        let sortedWeeks = weeks.sorted()
        guard let first = sortedWeeks.first, let last = sortedWeeks.last else { return L10n.text("未填写") }
        if first == last { return L10n.text("第 %d 周", first) }
        return L10n.text("第 %d-%d 周", first, last)
    }
}

extension [Course] {
    func sortedByStartPeriod() -> [Course] {
        sorted { lhs, rhs in
            let leftStart = lhs.duration.min() ?? 0
            let rightStart = rhs.duration.min() ?? 0
            if leftStart == rightStart {
                return (lhs.duration.max() ?? 0) < (rhs.duration.max() ?? 0)
            }
            return leftStart < rightStart
        }
    }
}

extension [ExamArrangement] {
    func nextRelevantExam(from date: Date = Date()) -> ExamArrangement? {
        sorted { ($0.startsAt ?? .distantFuture) < ($1.startsAt ?? .distantFuture) }
            .first { ($0.endsAt ?? $0.startsAt ?? .distantPast) >= date }
    }
}
