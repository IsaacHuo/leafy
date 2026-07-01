import Foundation
import SwiftData
import WidgetKit

@MainActor
enum LeafyWidgetSnapshotBuilder {
    static func publish(
        courses: [Course],
        notes: [CourseNote],
        occurrenceNotes: [CourseOccurrenceNote],
        reminders: [CourseReminderSetting],
        cellReminders: [TimetableCellReminder],
        isAuthenticated: Bool,
        date: Date = Date()
    ) {
        let archive = makeArchive(
            courses: courses,
            notes: notes,
            occurrenceNotes: occurrenceNotes,
            reminders: reminders,
            cellReminders: cellReminders,
            isAuthenticated: isAuthenticated,
            date: date
        )
        Task.detached {
            await WidgetSnapshotPublisher.shared.publish(archive)
        }
    }

    static func publish(from modelContext: ModelContext, isAuthenticated: Bool, date: Date = Date()) {
        let courses = fetch(Course.self, in: modelContext)
        let notes = fetch(CourseNote.self, in: modelContext)
        let occurrenceNotes = fetch(CourseOccurrenceNote.self, in: modelContext)
        let reminders = fetch(CourseReminderSetting.self, in: modelContext)
        let cellReminders = fetch(TimetableCellReminder.self, in: modelContext)

        publish(
            courses: courses,
            notes: notes,
            occurrenceNotes: occurrenceNotes,
            reminders: reminders,
            cellReminders: cellReminders,
            isAuthenticated: isAuthenticated,
            date: date
        )
    }

    static func publishNeedsLogin(date: Date = Date()) {
        let language = AppLanguagePreference.current
        let snapshots = LeafyWidgetConstants.supportedDayOffsets.map { dayOffset in
            let snapshotDate = dateForSnapshot(baseDate: date, dayOffset: dayOffset)
            return LeafyWidgetDaySnapshot(
                dayOffset: dayOffset,
                snapshot: LeafyWidgetSnapshot(
                    generatedAt: date,
                    status: .needsLogin,
                    displayDate: Self.displayDate(for: snapshotDate, language: language),
                    weekText: weekText(for: snapshotDate, language: language),
                    dayText: dayText(for: snapshotDate, language: language),
                    headline: L10n.text("需要重新登录", language: language),
                    subtitle: L10n.text("连接校园网并打开 %@ 重新登录后，小组件会继续显示课表。", language: language, AppBrand.displayName),
                    syncText: nil,
                    lastFailureText: nil,
                    nextExamText: nextExamText(from: SchoolDataCache.loadExamSchedule(), date: snapshotDate, language: language),
                    courses: []
                )
            )
        }

        let archive = LeafyWidgetSnapshotArchive(generatedAt: date, snapshots: snapshots)
        Task.detached {
            await WidgetSnapshotPublisher.shared.publishNeedsLogin(archive)
        }
    }

    #if DEBUG
    static func makeArchiveForTesting(
        courses: [Course],
        notes: [CourseNote] = [],
        occurrenceNotes: [CourseOccurrenceNote] = [],
        reminders: [CourseReminderSetting] = [],
        cellReminders: [TimetableCellReminder] = [],
        isAuthenticated: Bool,
        date: Date
    ) -> LeafyWidgetSnapshotArchive {
        makeArchive(
            courses: courses,
            notes: notes,
            occurrenceNotes: occurrenceNotes,
            reminders: reminders,
            cellReminders: cellReminders,
            isAuthenticated: isAuthenticated,
            date: date
        )
    }
    #endif

    private static func makeArchive(
        courses: [Course],
        notes: [CourseNote],
        occurrenceNotes: [CourseOccurrenceNote],
        reminders: [CourseReminderSetting],
        cellReminders: [TimetableCellReminder],
        isAuthenticated: Bool,
        date: Date
    ) -> LeafyWidgetSnapshotArchive {
        let language = AppLanguagePreference.current
        let snapshots = LeafyWidgetConstants.supportedDayOffsets.map { dayOffset in
            LeafyWidgetDaySnapshot(
                dayOffset: dayOffset,
                snapshot: makeSnapshot(
                    courses: courses,
                    notes: notes,
                    occurrenceNotes: occurrenceNotes,
                    reminders: reminders,
                    cellReminders: cellReminders,
                    isAuthenticated: isAuthenticated,
                    date: dateForSnapshot(baseDate: date, dayOffset: dayOffset),
                    generatedAt: date,
                    dayOffset: dayOffset,
                    language: language
                )
            )
        }

        return LeafyWidgetSnapshotArchive(generatedAt: date, snapshots: snapshots)
    }

    private static func makeSnapshot(
        courses: [Course],
        notes: [CourseNote],
        occurrenceNotes: [CourseOccurrenceNote],
        reminders: [CourseReminderSetting],
        cellReminders: [TimetableCellReminder],
        isAuthenticated: Bool,
        date: Date,
        generatedAt: Date,
        dayOffset: Int,
        language: AppLanguagePreference
    ) -> LeafyWidgetSnapshot {
        let schedule = SemesterConfig.weekAndDay(for: date)
        let todayCourses = courses
            .filter { $0.dayOfWeek == schedule.day && $0.weeks.contains(schedule.week) }
            .sortedByStartPeriod()
        let notesByKey = TimetableNoteResolver.courseNotesByKey(notes)
        let occurrenceNotesByKey = TimetableNoteResolver.occurrenceNotesByKey(occurrenceNotes)
        let remindersByKey = Dictionary(uniqueKeysWithValues: reminders.map { ($0.courseKey, $0.minutesBefore) })
        let todayCellReminders = cellReminders
            .filter { $0.week == schedule.week && $0.dayOfWeek == schedule.day }
            .sorted { $0.period < $1.period }

        let widgetCourses = todayCourses.enumerated().map { index, course in
            LeafyWidgetCourse(
                id: course.id,
                title: displayName(for: course),
                timeText: course.timeRangeText,
                periodText: course.durationTextForShare,
                locationText: course.locationTextForShare,
                teacherText: trimmed(course.teacher),
                noteText: TimetableNoteResolver.effectiveNote(
                    for: course,
                    week: schedule.week,
                    courseNotesByKey: notesByKey,
                    occurrenceNotesByKey: occurrenceNotesByKey
                ),
                reminderText: reminderText(minutes: remindersByKey[course.stableCourseKey] ?? 0, language: language),
                accentIndex: index,
                isActive: dayOffset == 0 && course.contains(date: date, week: schedule.week)
            )
        }

        let extraCellReminderText = todayCellReminders.first.flatMap { reminder -> String? in
            let title = trimmed(reminder.title) ?? L10n.text("课表提醒", language: language)
            guard let slot = TimetablePeriodSchedule.slot(for: reminder.period) else {
                return title
            }
            return "\(slot.startText) \(title)"
        }

        let status: LeafyWidgetSnapshot.Status
        if !isAuthenticated {
            status = .needsLogin
        } else if courses.isEmpty {
            status = .stale
        } else if todayCourses.isEmpty {
            status = .noCourses
        } else {
            status = .ready
        }

        return LeafyWidgetSnapshot(
            generatedAt: generatedAt,
            status: status,
            displayDate: displayDate(for: date, language: language),
            weekText: weekText(for: date, language: language),
            dayText: dayText(for: date, language: language),
            headline: headline(
                status: status,
                activeCourse: widgetCourses.first { $0.isActive },
                hasCourses: !widgetCourses.isEmpty,
                dayOffset: dayOffset,
                language: language
            ),
            subtitle: subtitle(
                status: status,
                courses: widgetCourses,
                extraCellReminderText: extraCellReminderText,
                dayOffset: dayOffset,
                language: language
            ),
            syncText: syncText(language: language),
            lastFailureText: trimmed(TimetableCacheMetadata.lastFailureMessage),
            nextExamText: nextExamText(from: SchoolDataCache.loadExamSchedule(), date: date, language: language),
            courses: Array(widgetCourses)
        )
    }

    private static func headline(
        status: LeafyWidgetSnapshot.Status,
        activeCourse: LeafyWidgetCourse?,
        hasCourses: Bool,
        dayOffset: Int,
        language: AppLanguagePreference
    ) -> String {
        switch status {
        case .ready:
            if dayOffset == 0, let activeCourse {
                return L10n.text("正在上：%@", language: language, activeCourse.title)
            }
            if hasCourses {
                return dayOffset == 0 ? L10n.text("今日课表", language: language) : L10n.text("明日课表", language: language)
            }
            return dayOffset == 0 ? L10n.text("今日课表", language: language) : L10n.text("明日课表", language: language)
        case .noCourses:
            return dayOffset == 0 ? L10n.text("今天没有课程", language: language) : L10n.text("明天没有课程", language: language)
        case .needsLogin:
            return L10n.text("需要重新登录", language: language)
        case .stale:
            return L10n.text("暂无课表缓存", language: language)
        }
    }

    private static func subtitle(
        status: LeafyWidgetSnapshot.Status,
        courses: [LeafyWidgetCourse],
        extraCellReminderText: String?,
        dayOffset: Int,
        language: AppLanguagePreference
    ) -> String {
        switch status {
        case .ready:
            if let next = courses.first(where: { !$0.isActive }) {
                return dayOffset == 0
                    ? L10n.text("下一节：%@", language: language, next.title)
                    : L10n.text("第一节：%@", language: language, next.title)
            }
            if let first = courses.first {
                return "\(first.timeText) · \(first.locationText)"
            }
            return extraCellReminderText ?? L10n.text("今天安排很轻。", language: language)
        case .noCourses:
            return extraCellReminderText ?? L10n.text("留一点空白给自己。", language: language)
        case .needsLogin:
            return L10n.text("连接校园网并打开 %@ 重新登录后，小组件会继续显示课表。", language: language, AppBrand.displayName)
        case .stale:
            return L10n.text("打开缓存与同步，重新拉取最新课表。", language: language)
        }
    }

    private static func syncText(language: AppLanguagePreference) -> String? {
        guard let date = TimetableCacheMetadata.lastSyncAt else { return nil }
        return L10n.text("最近同步：%@", language: language, DateFormatters.headerWithTime.string(from: date))
    }

    private static func nextExamText(from exams: [ExamArrangement], date: Date, language: AppLanguagePreference) -> String? {
        guard let exam = exams.nextRelevantExam(from: date) else { return nil }
        return L10n.text("考试：%@ · %@", language: language, exam.name, exam.date)
    }

    private static func displayDate(for date: Date, language: AppLanguagePreference) -> String {
        DateFormatters.chineseDay.string(from: date)
    }

    private static func weekText(for date: Date, language: AppLanguagePreference) -> String {
        L10n.text("第 %d 周", language: language, SemesterConfig.weekAndDay(for: date).week)
    }

    private static func dayText(for date: Date, language: AppLanguagePreference) -> String {
        let weekday = SemesterConfig.weekAndDay(for: date).day
        guard (1...7).contains(weekday) else { return "" }
        return language.weekdayTitle(for: weekday)
    }

    private static func dateForSnapshot(baseDate: Date, dayOffset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: dayOffset, to: baseDate)
            ?? baseDate.addingTimeInterval(TimeInterval(dayOffset * 24 * 60 * 60))
    }

    private static func reminderText(minutes: Int, language: AppLanguagePreference) -> String? {
        let minutes = TimetableNotificationManager.normalizedReminderMinutes(minutes)
        guard minutes > 0 else { return nil }
        return L10n.text("提前 %d 分钟", language: language, minutes)
    }

    private static func displayName(for course: Course) -> String {
        trimmed(course.courseName) ?? L10n.text("未命名课程")
    }

    private static func trimmed(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func fetch<T: PersistentModel>(_ type: T.Type, in modelContext: ModelContext) -> [T] {
        (try? modelContext.fetch(FetchDescriptor<T>())) ?? []
    }
}

private extension Course {
    var timeRangeText: String {
        guard let first = duration.min(),
              let last = duration.max(),
              let startSlot = TimetablePeriodSchedule.slot(for: first),
              let endSlot = TimetablePeriodSchedule.slot(for: last) else {
            return durationTextForShare
        }

        return "\(startSlot.startText)-\(endSlot.endText)"
    }

    func contains(date: Date, week: Int) -> Bool {
        guard let start = TimetablePeriodSchedule.startDate(for: self, week: week),
              let end = TimetablePeriodSchedule.endDate(for: self, week: week)
        else {
            return false
        }

        return date >= start && date <= end
    }
}
