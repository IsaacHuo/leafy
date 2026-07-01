import EventKit
import Foundation

enum TimetableCalendarExportRange: String, CaseIterable, Identifiable {
    case currentWeek
    case remainingSemester
    case fullSemester
    case customWeeks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .currentWeek:
            return L10n.text("当前周")
        case .remainingSemester:
            return L10n.text("剩余学期")
        case .fullSemester:
            return L10n.text("全学期")
        case .customWeeks:
            return L10n.text("自定义")
        }
    }
}

struct TimetableCalendarExportResult: Equatable {
    let created: Int
    let updated: Int
    let removed: Int

    var message: String {
        L10n.text("已导出到系统日历：新增 %d 个，更新 %d 个，移除 %d 个。", created, updated, removed)
    }
}

struct TimetableCalendarClearResult: Equatable {
    let removed: Int

    var message: String {
        if removed == 0 {
            return L10n.text("系统日历中没有本学期 %@ 已导出的课表事件。", AppBrand.displayName)
        }
        return L10n.text("已从系统日历清理本学期 %@ 课表事件：移除 %d 个。", AppBrand.displayName, removed)
    }
}

struct TimetableCalendarEventDraft: Equatable {
    let occurrenceKey: String
    let title: String
    let location: String
    let notes: String
    let startDate: Date
    let endDate: Date
    let url: URL
}

enum TimetableCalendarExportError: LocalizedError {
    case permissionDenied
    case calendarUnavailable

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return L10n.text("未获得完整日历访问权限，无法覆盖更新已导出的课表。请在系统设置中允许 %@ 访问日历。", AppBrand.displayName)
        case .calendarUnavailable:
            return L10n.text("没有可写入的系统日历。请先在系统日历中启用一个可写日历。")
        }
    }
}

@MainActor
enum TimetableCalendarExportBuilder {
    static let urlHost = "timetable"
    private static let examKeyPrefix = "exam:"
    private static let cellReminderKeyPrefix = "cellReminder:"

    static func weekRange(
        for range: TimetableCalendarExportRange,
        currentWeek: Int,
        referenceDate: Date = Date(),
        totalWeeks: Int? = nil,
        customWeeks: ClosedRange<Int>? = nil
    ) -> ClosedRange<Int> {
        let resolvedTotalWeeks = totalWeeks ?? SemesterConfig.supportedWeeks
        let resolvedCurrentWeek = max(1, min(currentWeek, resolvedTotalWeeks))
        switch range {
        case .currentWeek:
            return resolvedCurrentWeek...resolvedCurrentWeek
        case .remainingSemester:
            let startWeek = SemesterConfig.currentWeek(date: referenceDate)
            return min(startWeek, resolvedTotalWeeks)...resolvedTotalWeeks
        case .fullSemester:
            return 1...resolvedTotalWeeks
        case .customWeeks:
            let selectedWeeks = customWeeks ?? resolvedCurrentWeek...resolvedCurrentWeek
            let startWeek = max(1, min(selectedWeeks.lowerBound, resolvedTotalWeeks))
            let endWeek = max(1, min(selectedWeeks.upperBound, resolvedTotalWeeks))
            return min(startWeek, endWeek)...max(startWeek, endWeek)
        }
    }

    static func drafts(
        courses: [Course],
        courseNotes: [CourseNote],
        occurrenceNotes: [CourseOccurrenceNote],
        cellReminders: [TimetableCellReminder] = [],
        exams: [ExamArrangement] = [],
        range: TimetableCalendarExportRange,
        currentWeek: Int,
        referenceDate: Date = Date(),
        totalWeeks: Int? = nil,
        customWeeks: ClosedRange<Int>? = nil
    ) -> [TimetableCalendarEventDraft] {
        let resolvedTotalWeeks = totalWeeks ?? SemesterConfig.supportedWeeks
        let weekRange = weekRange(
            for: range,
            currentWeek: currentWeek,
            referenceDate: referenceDate,
            totalWeeks: resolvedTotalWeeks,
            customWeeks: customWeeks
        )
        let courseNotesByKey = TimetableNoteResolver.courseNotesByKey(courseNotes)
        let occurrenceNotesByKey = TimetableNoteResolver.occurrenceNotesByKey(occurrenceNotes)

        let courseDrafts = courses.flatMap { course in
            course.weeks
                .filter { weekRange.contains($0) }
                .sorted()
                .compactMap { week in
                    draft(
                        course: course,
                        week: week,
                        courseNotesByKey: courseNotesByKey,
                        occurrenceNotesByKey: occurrenceNotesByKey
                    )
                }
        }

        let reminderDrafts = cellReminders
            .filter { weekRange.contains($0.week) }
            .compactMap(draft(reminder:))

        let examDrafts = exams
            .filter { exam in
                guard let week = exam.timetableProjection?.week else { return false }
                return weekRange.contains(week)
            }
            .compactMap(draft(exam:))

        return (courseDrafts + reminderDrafts + examDrafts)
        .sorted { lhs, rhs in
            if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
            return lhs.title < rhs.title
        }
    }

    static func exportInterval(
        for range: TimetableCalendarExportRange,
        currentWeek: Int,
        referenceDate: Date = Date(),
        totalWeeks: Int? = nil,
        customWeeks: ClosedRange<Int>? = nil
    ) -> DateInterval? {
        let resolvedTotalWeeks = totalWeeks ?? SemesterConfig.supportedWeeks
        let weeks = weekRange(
            for: range,
            currentWeek: currentWeek,
            referenceDate: referenceDate,
            totalWeeks: resolvedTotalWeeks,
            customWeeks: customWeeks
        )
        let calendar = Calendar.current
        let semesterStart = calendar.startOfDay(for: SemesterConfig.startOfSemesterDate)
        guard let start = calendar.date(byAdding: .day, value: (weeks.lowerBound - 1) * 7, to: semesterStart),
              let end = calendar.date(byAdding: .day, value: weeks.upperBound * 7, to: semesterStart),
              end > start
        else {
            return nil
        }
        return DateInterval(start: start, end: end)
    }

    static func occurrenceKey(from url: URL?) -> String? {
        guard let url,
              url.scheme == "leafy",
              url.host == urlHost else {
            return nil
        }

        let rawValue = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !rawValue.isEmpty else { return nil }
        return rawValue.removingPercentEncoding ?? rawValue
    }

    private static func draft(
        course: Course,
        week: Int,
        courseNotesByKey: [String: String],
        occurrenceNotesByKey: [String: String]
    ) -> TimetableCalendarEventDraft? {
        guard let startDate = TimetablePeriodSchedule.startDate(for: course, week: week),
              let endDate = TimetablePeriodSchedule.endDate(for: course, week: week)
        else {
            return nil
        }

        let occurrenceKey = course.occurrenceKey(week: week)
        let note = TimetableNoteResolver.effectiveNote(
            for: course,
            week: week,
            courseNotesByKey: courseNotesByKey,
            occurrenceNotesByKey: occurrenceNotesByKey
        )
        return TimetableCalendarEventDraft(
            occurrenceKey: occurrenceKey,
            title: displayName(for: course),
            location: course.locationTextForShare,
            notes: notesText(course: course, week: week, note: note),
            startDate: startDate,
            endDate: endDate,
            url: url(for: occurrenceKey)
        )
    }

    private static func draft(reminder: TimetableCellReminder) -> TimetableCalendarEventDraft? {
        guard let startDate = reminder.resolvedStartDate
        else {
            return nil
        }

        let endDate = reminder.resolvedEndDate.flatMap { $0 > startDate ? $0 : nil }
            ?? startDate.addingTimeInterval(45 * 60)
        let occurrenceKey = cellReminderKeyPrefix + reminder.cellKey
        return TimetableCalendarEventDraft(
            occurrenceKey: occurrenceKey,
            title: reminder.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? L10n.text("课表日程") : reminder.title,
            location: reminder.locationText,
            notes: notesText(reminder: reminder),
            startDate: startDate,
            endDate: endDate,
            url: url(for: occurrenceKey)
        )
    }

    private static func draft(exam: ExamArrangement) -> TimetableCalendarEventDraft? {
        guard let startDate = exam.startsAt else { return nil }
        let endDate = exam.endsAt.flatMap { $0 > startDate ? $0 : nil }
            ?? startDate.addingTimeInterval(90 * 60)
        let occurrenceKey = examKeyPrefix + String(exam.id)
        return TimetableCalendarEventDraft(
            occurrenceKey: occurrenceKey,
            title: L10n.text("考试：%@", exam.name),
            location: exam.location,
            notes: notesText(exam: exam),
            startDate: startDate,
            endDate: endDate,
            url: url(for: occurrenceKey)
        )
    }

    private static func notesText(course: Course, week: Int, note: String?) -> String {
        var lines = [
            L10n.text("教师：%@", course.teacher.isEmpty ? L10n.text("未填写") : course.teacher),
            L10n.text("节次：%@", course.durationTextForShare),
            L10n.text("周次：第 %d 周", week)
        ]

        if let note {
            lines.append(L10n.text("备注：%@", note))
        }

        lines.append(L10n.text("由 %@ 导出", AppBrand.displayName))
        return lines.joined(separator: "\n")
    }

    private static func notesText(reminder: TimetableCellReminder) -> String {
        var lines = [
            L10n.text("类型：课表日程"),
            L10n.text("周次：第 %d 周", reminder.week),
            reminder.displayStartPeriod == reminder.displayEndPeriod
                ? L10n.text("节次：第 %d 节", reminder.displayStartPeriod)
                : L10n.text("节次：第 %d-%d 节", reminder.displayStartPeriod, reminder.displayEndPeriod)
        ]

        if !reminder.locationText.isEmpty {
            lines.append(L10n.text("地点：%@", reminder.locationText))
        }

        if !reminder.noteText.isEmpty {
            lines.append(L10n.text("备注：%@", reminder.noteText))
        }

        if reminder.minutesBefore > 0 {
            lines.append(L10n.text("本地通知：提前 %d 分钟", reminder.minutesBefore))
        }

        lines.append(L10n.text("由 %@ 导出", AppBrand.displayName))
        return lines.joined(separator: "\n")
    }

    private static func notesText(exam: ExamArrangement) -> String {
        [
            L10n.text("类型：考试"),
            L10n.text("课程编号：%@", exam.courseID.isEmpty ? L10n.text("未填写") : exam.courseID),
            L10n.text("时间：%@ %@-%@", exam.date, exam.start, exam.end),
            L10n.text("由 %@ 导出", AppBrand.displayName)
        ].joined(separator: "\n")
    }

    private static func displayName(for course: Course) -> String {
        let name = course.courseName
            .replacingOccurrences(of: "（必修）", with: "")
            .replacingOccurrences(of: "(必修)", with: "")
            .replacingOccurrences(of: "（辅修）", with: "")
            .replacingOccurrences(of: "(辅修)", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? L10n.text("未命名课程") : name
    }

    private static func url(for occurrenceKey: String) -> URL {
        var components = URLComponents()
        components.scheme = "leafy"
        components.host = urlHost
        components.path = "/" + occurrenceKey
        return components.url ?? URL(string: "leafy://\(urlHost)")!
    }
}

@MainActor
final class TimetableCalendarExportService {
    private let eventStore: EKEventStore

    init(eventStore: EKEventStore = EKEventStore()) {
        self.eventStore = eventStore
    }

    func export(
        courses: [Course],
        courseNotes: [CourseNote],
        occurrenceNotes: [CourseOccurrenceNote],
        cellReminders: [TimetableCellReminder] = [],
        exams: [ExamArrangement] = [],
        range: TimetableCalendarExportRange,
        currentWeek: Int,
        customWeeks: ClosedRange<Int>? = nil
    ) async throws -> TimetableCalendarExportResult {
        try await ensureFullCalendarAccess()
        guard let calendar = eventStore.defaultCalendarForNewEvents, calendar.allowsContentModifications else {
            throw TimetableCalendarExportError.calendarUnavailable
        }

        let drafts = TimetableCalendarExportBuilder.drafts(
            courses: courses,
            courseNotes: courseNotes,
            occurrenceNotes: occurrenceNotes,
            cellReminders: cellReminders,
            exams: exams,
            range: range,
            currentWeek: currentWeek,
            customWeeks: customWeeks
        )

        guard let interval = TimetableCalendarExportBuilder.exportInterval(
            for: range,
            currentWeek: currentWeek,
            customWeeks: customWeeks
        ) else {
            return TimetableCalendarExportResult(created: 0, updated: 0, removed: 0)
        }

        let existingEvents = leafyEvents(in: interval)
        let existingByKey = Dictionary(
            existingEvents.compactMap { event in
                TimetableCalendarExportBuilder.occurrenceKey(from: event.url).map { ($0, event) }
            },
            uniquingKeysWith: { first, _ in first }
        )
        let draftKeys = Set(drafts.map(\.occurrenceKey))

        var created = 0
        var updated = 0

        for draft in drafts {
            let event = existingByKey[draft.occurrenceKey] ?? EKEvent(eventStore: eventStore)
            if existingByKey[draft.occurrenceKey] == nil {
                event.calendar = calendar
                created += 1
            } else {
                updated += 1
            }
            apply(draft, to: event, defaultCalendar: calendar)
            try eventStore.save(event, span: .thisEvent, commit: false)
        }

        var removed = 0
        for event in existingEvents {
            guard let key = TimetableCalendarExportBuilder.occurrenceKey(from: event.url),
                  !draftKeys.contains(key)
            else {
                continue
            }
            try eventStore.remove(event, span: .thisEvent, commit: false)
            removed += 1
        }

        try eventStore.commit()
        return TimetableCalendarExportResult(created: created, updated: updated, removed: removed)
    }

    func clearExportedCourses() async throws -> TimetableCalendarClearResult {
        try await ensureFullCalendarAccess()
        guard let interval = TimetableCalendarExportBuilder.exportInterval(
            for: .fullSemester,
            currentWeek: 1
        ) else {
            return TimetableCalendarClearResult(removed: 0)
        }

        let existingEvents = leafyEvents(in: interval)
        var removed = 0
        for event in existingEvents {
            try eventStore.remove(event, span: .thisEvent, commit: false)
            removed += 1
        }

        if removed > 0 {
            try eventStore.commit()
        }
        return TimetableCalendarClearResult(removed: removed)
    }

    private func ensureFullCalendarAccess() async throws {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            return
        case .notDetermined:
            let granted = try await requestFullAccess()
            guard granted else { throw TimetableCalendarExportError.permissionDenied }
        case .authorized:
            return
        case .denied, .restricted, .writeOnly:
            throw TimetableCalendarExportError.permissionDenied
        @unknown default:
            throw TimetableCalendarExportError.permissionDenied
        }
    }

    private func requestFullAccess() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            eventStore.requestFullAccessToEvents { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    private func leafyEvents(in interval: DateInterval) -> [EKEvent] {
        let predicate = eventStore.predicateForEvents(
            withStart: interval.start,
            end: interval.end,
            calendars: nil
        )
        return eventStore.events(matching: predicate)
            .filter { TimetableCalendarExportBuilder.occurrenceKey(from: $0.url) != nil }
    }

    private func apply(_ draft: TimetableCalendarEventDraft, to event: EKEvent, defaultCalendar: EKCalendar) {
        if event.calendar == nil || event.calendar?.allowsContentModifications == false {
            event.calendar = defaultCalendar
        }
        event.title = draft.title
        event.location = draft.location
        event.notes = draft.notes
        event.startDate = draft.startDate
        event.endDate = draft.endDate
        event.url = draft.url
        event.availability = .busy
    }
}
