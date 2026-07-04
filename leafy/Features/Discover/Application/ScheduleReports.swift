import Foundation
import SwiftData
import UserNotifications

enum ScheduleReportMode: String, CaseIterable, Codable, Identifiable, Hashable {
    case morningReport
    case eveningReport
    case examDigest
    case countdownDigest
    case calendarDigest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .morningReport: return "今日早报"
        case .eveningReport: return "明日晚报"
        case .examDigest: return "考试提醒"
        case .countdownDigest: return "重要日期提醒"
        case .calendarDigest: return "校历节点"
        }
    }

    var subtitle: String {
        switch self {
        case .morningReport:
            return "每天查看今日课程、考试和本地日程"
        case .eveningReport:
            return "每天查看明天全部课程和时间日程"
        case .examDigest:
            return "未来 7 天有考试时提醒"
        case .countdownDigest:
            return "未来 7 天有重要日期时提醒"
        case .calendarDigest:
            return "今天或明天有校历、节气、假期节点时提醒"
        }
    }

    var systemImage: String {
        switch self {
        case .morningReport: return "sunrise.fill"
        case .eveningReport: return "moon.stars.fill"
        case .examDigest: return "pencil.and.list.clipboard"
        case .countdownDigest: return "timer"
        case .calendarDigest: return "calendar.badge.exclamationmark"
        }
    }

    var defaultHour: Int {
        switch self {
        case .morningReport: return 7
        case .eveningReport: return 21
        case .examDigest: return 20
        case .countdownDigest: return 20
        case .calendarDigest: return 8
        }
    }

    var defaultMinute: Int {
        switch self {
        case .morningReport: return 30
        case .eveningReport: return 30
        case .examDigest, .countdownDigest, .calendarDigest: return 0
        }
    }
}

struct ScheduleReportModeSetting: Codable, Hashable {
    var isEnabled: Bool
    var hour: Int
    var minute: Int

    init(isEnabled: Bool = false, hour: Int, minute: Int) {
        self.isEnabled = isEnabled
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
    }

    init(mode: ScheduleReportMode, isEnabled: Bool = false) {
        self.init(isEnabled: isEnabled, hour: mode.defaultHour, minute: mode.defaultMinute)
    }
}

struct ScheduleReportSettings: Codable, Hashable {
    var isEnabled: Bool
    var modeSettings: [ScheduleReportMode: ScheduleReportModeSetting]
    var scheduledNotificationIDs: [String]

    init(
        isEnabled: Bool = false,
        modeSettings: [ScheduleReportMode: ScheduleReportModeSetting] = [:],
        scheduledNotificationIDs: [String] = []
    ) {
        self.isEnabled = isEnabled
        self.modeSettings = Self.normalizedModeSettings(modeSettings)
        self.scheduledNotificationIDs = scheduledNotificationIDs
    }

    static let disabled = ScheduleReportSettings()

    func setting(for mode: ScheduleReportMode) -> ScheduleReportModeSetting {
        modeSettings[mode] ?? ScheduleReportModeSetting(mode: mode)
    }

    mutating func set(_ setting: ScheduleReportModeSetting, for mode: ScheduleReportMode) {
        modeSettings[mode] = ScheduleReportModeSetting(
            isEnabled: setting.isEnabled,
            hour: setting.hour,
            minute: setting.minute
        )
    }

    var enabledModes: [ScheduleReportMode] {
        guard isEnabled else { return [] }
        return ScheduleReportMode.allCases.filter { setting(for: $0).isEnabled }
    }

    private static func normalizedModeSettings(
        _ modeSettings: [ScheduleReportMode: ScheduleReportModeSetting]
    ) -> [ScheduleReportMode: ScheduleReportModeSetting] {
        Dictionary(
            uniqueKeysWithValues: ScheduleReportMode.allCases.map { mode in
                let setting = modeSettings[mode] ?? ScheduleReportModeSetting(mode: mode)
                return (
                    mode,
                    ScheduleReportModeSetting(
                        isEnabled: setting.isEnabled,
                        hour: setting.hour,
                        minute: setting.minute
                    )
                )
            }
        )
    }
}

enum ScheduleReportSettingsStore {
    private static let key = "scheduleReport.settings.v1"

    static func load(defaults: UserDefaults = .standard) -> ScheduleReportSettings {
        guard let data = defaults.data(forKey: scopedKey(defaults: defaults)),
              let settings = try? JSONDecoder().decode(ScheduleReportSettings.self, from: data)
        else {
            return .disabled
        }
        return ScheduleReportSettings(
            isEnabled: settings.isEnabled,
            modeSettings: settings.modeSettings,
            scheduledNotificationIDs: settings.scheduledNotificationIDs
        )
    }

    static func save(_ settings: ScheduleReportSettings, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: scopedKey(defaults: defaults))
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: scopedKey(defaults: defaults))
    }

    static func scopedStorageKey(defaults: UserDefaults = .standard) -> String {
        scopedKey(defaults: defaults)
    }

    private static func scopedKey(defaults: UserDefaults) -> String {
        CampusScopedDefaults.key(key, defaults: defaults)
    }
}

struct ScheduleReportInput {
    var courses: [Course]
    var exams: [ExamArrangement]
    var countdowns: [CustomScheduleEvent]
    var cellReminders: [TimetableCellReminder]

    init(
        courses: [Course],
        exams: [ExamArrangement],
        countdowns: [CustomScheduleEvent],
        cellReminders: [TimetableCellReminder]
    ) {
        self.courses = courses
        self.exams = exams
        self.countdowns = countdowns
        self.cellReminders = cellReminders
    }
}

struct ScheduleReportNotificationDraft: Identifiable, Equatable {
    let id: String
    let mode: ScheduleReportMode
    let fireDate: Date
    let title: String
    let body: String
    let targetURL: URL
}

enum ScheduleReportPlanner {
    static let lookaheadDays = 7
    static let targetURL = URL(string: "leafy://schedule-reports")!

    static func drafts(
        settings: ScheduleReportSettings,
        input: ScheduleReportInput,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [ScheduleReportNotificationDraft] {
        guard settings.isEnabled else { return [] }

        let today = calendar.startOfDay(for: now)
        let modes = settings.enabledModes
        return modes.flatMap { mode in
            drafts(
                mode: mode,
                setting: settings.setting(for: mode),
                input: input,
                now: now,
                startDay: today,
                calendar: calendar
            )
        }
        .sorted { lhs, rhs in
            if lhs.fireDate != rhs.fireDate { return lhs.fireDate < rhs.fireDate }
            return lhs.id < rhs.id
        }
    }

    static func summary(
        for mode: ScheduleReportMode,
        input: ScheduleReportInput,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        switch mode {
        case .morningReport:
            return reportBody(for: calendar.startOfDay(for: referenceDate), input: input, label: "今天", calendar: calendar)
        case .eveningReport:
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: referenceDate)) ?? referenceDate
            return reportBody(for: tomorrow, input: input, label: "明天", includesAllCourses: true, calendar: calendar)
        case .examDigest:
            return upcomingExamSummary(input.exams, from: referenceDate, days: lookaheadDays, calendar: calendar)
                ?? "未来 7 天暂无考试安排。"
        case .countdownDigest:
            return upcomingImportantDateSummary(input.countdowns, from: referenceDate, days: lookaheadDays, calendar: calendar)
                ?? "未来 7 天暂无重要日期。"
        case .calendarDigest:
            return calendarDigestSummary(from: referenceDate, calendar: calendar)
                ?? "今天和明天暂无校历节点。"
        }
    }

    private static func drafts(
        mode: ScheduleReportMode,
        setting: ScheduleReportModeSetting,
        input: ScheduleReportInput,
        now: Date,
        startDay: Date,
        calendar: Calendar
    ) -> [ScheduleReportNotificationDraft] {
        guard setting.isEnabled else { return [] }

        switch mode {
        case .morningReport:
            return (0..<lookaheadDays).compactMap { dayOffset in
                let reportDay = calendar.date(byAdding: .day, value: dayOffset, to: startDay) ?? startDay
                guard let fireDate = fireDate(on: reportDay, setting: setting, calendar: calendar),
                      fireDate > now else { return nil }
                return draft(
                    mode: mode,
                    fireDate: fireDate,
                    title: "今日早报",
                    body: reportBody(for: reportDay, input: input, label: "今天", calendar: calendar),
                    calendar: calendar
                )
            }
        case .eveningReport:
            return (0..<lookaheadDays).compactMap { dayOffset in
                let fireDay = calendar.date(byAdding: .day, value: dayOffset, to: startDay) ?? startDay
                let reportDay = calendar.date(byAdding: .day, value: 1, to: fireDay) ?? fireDay
                guard let fireDate = fireDate(on: fireDay, setting: setting, calendar: calendar),
                      fireDate > now else { return nil }
                return draft(
                    mode: mode,
                    fireDate: fireDate,
                    title: "明日晚报",
                    body: reportBody(
                        for: reportDay,
                        input: input,
                        label: "明天",
                        includesAllCourses: true,
                        calendar: calendar
                    ),
                    calendar: calendar
                )
            }
        case .examDigest:
            return singleDraftIfNeeded(
                mode: mode,
                setting: setting,
                startDay: startDay,
                now: now,
                title: "考试提醒",
                body: upcomingExamSummary(input.exams, from: now, days: lookaheadDays, calendar: calendar),
                calendar: calendar
            )
        case .countdownDigest:
            return singleDraftIfNeeded(
                mode: mode,
                setting: setting,
                startDay: startDay,
                now: now,
                title: "重要日期提醒",
                body: upcomingImportantDateSummary(input.countdowns, from: now, days: lookaheadDays, calendar: calendar),
                calendar: calendar
            )
        case .calendarDigest:
            return singleDraftIfNeeded(
                mode: mode,
                setting: setting,
                startDay: startDay,
                now: now,
                title: "校历节点",
                body: calendarDigestSummary(from: now, calendar: calendar),
                calendar: calendar
            )
        }
    }

    private static func singleDraftIfNeeded(
        mode: ScheduleReportMode,
        setting: ScheduleReportModeSetting,
        startDay: Date,
        now: Date,
        title: String,
        body: String?,
        calendar: Calendar
    ) -> [ScheduleReportNotificationDraft] {
        guard let body,
              let fireDate = nextFireDate(startingAt: startDay, setting: setting, now: now, calendar: calendar)
        else {
            return []
        }
        return [
            draft(mode: mode, fireDate: fireDate, title: title, body: body, calendar: calendar)
        ]
    }

    private static func draft(
        mode: ScheduleReportMode,
        fireDate: Date,
        title: String,
        body: String,
        calendar: Calendar
    ) -> ScheduleReportNotificationDraft {
        ScheduleReportNotificationDraft(
            id: notificationID(mode: mode, fireDate: fireDate, calendar: calendar),
            mode: mode,
            fireDate: fireDate,
            title: title,
            body: body,
            targetURL: targetURL
        )
    }

    private static func reportBody(
        for date: Date,
        input: ScheduleReportInput,
        label: String,
        includesAllCourses: Bool = false,
        calendar: Calendar
    ) -> String {
        let courses = courses(on: date, from: input.courses)
        let exams = exams(on: date, from: input.exams, calendar: calendar)
        let reminders = cellReminders(on: date, from: input.cellReminders, calendar: calendar)
        let events = AcademicCalendarEvents.events(for: date, calendar: calendar)
        var parts: [String] = []

        if courses.isEmpty {
            parts.append("\(label)没有课程")
        } else if includesAllCourses {
            let names = courses.map(\.courseName).joined(separator: "、")
            parts.append("\(label) \(courses.count) 节课：\(names)")
        } else if let first = courses.first {
            parts.append("\(label) \(courses.count) 节课，第一节 \(first.courseName)")
        }

        if !exams.isEmpty {
            let names = exams.prefix(2).map(\.name).joined(separator: "、")
            parts.append("\(exams.count) 场考试：\(names)")
        }

        if !reminders.isEmpty {
            let titles = reminders.prefix(2).map(\.title).joined(separator: "、")
            parts.append("\(reminders.count) 个本地日程：\(titles)")
        }

        if !events.isEmpty {
            parts.append(events.map(\.title).joined(separator: "、"))
        }

        return parts.joined(separator: "；")
    }

    private static func upcomingExamSummary(
        _ exams: [ExamArrangement],
        from date: Date,
        days: Int,
        calendar: Calendar
    ) -> String? {
        let end = calendar.date(byAdding: .day, value: days, to: date) ?? date
        let upcoming = exams
            .filter { exam in
                guard let start = exam.startsAt else { return false }
                return start >= date && start <= end
            }
            .sorted { ($0.startsAt ?? .distantFuture) < ($1.startsAt ?? .distantFuture) }
        guard !upcoming.isEmpty else { return nil }

        let first = upcoming[0]
        return "未来 7 天有 \(upcoming.count) 场考试，最近：\(first.name) \(first.date) \(first.start)。"
    }

    private static func upcomingImportantDateSummary(
        _ countdowns: [CustomScheduleEvent],
        from date: Date,
        days: Int,
        calendar: Calendar
    ) -> String? {
        let end = calendar.date(byAdding: .day, value: days, to: date) ?? date
        let upcoming = countdowns
            .filter { $0.startsAt >= date && $0.startsAt <= end }
            .sorted { $0.startsAt < $1.startsAt }
        guard let first = upcoming.first else { return nil }

        return "未来 7 天有 \(upcoming.count) 个重要日期，最近：\(first.title)。"
    }

    private static func calendarDigestSummary(from date: Date, calendar: Calendar) -> String? {
        let today = calendar.startOfDay(for: date)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let todayEvents = AcademicCalendarEvents.events(for: today, calendar: calendar)
        let tomorrowEvents = AcademicCalendarEvents.events(for: tomorrow, calendar: calendar)
        var parts: [String] = []

        if !todayEvents.isEmpty {
            parts.append("今天：" + todayEvents.map(\.title).joined(separator: "、"))
        }
        if !tomorrowEvents.isEmpty {
            parts.append("明天：" + tomorrowEvents.map(\.title).joined(separator: "、"))
        }

        return parts.isEmpty ? nil : parts.joined(separator: "；")
    }

    private static func courses(on date: Date, from courses: [Course]) -> [Course] {
        let schedule = SemesterConfig.weekAndDay(for: date)
        return courses
            .filter { $0.dayOfWeek == schedule.day && $0.weeks.contains(schedule.week) }
            .sortedByStartPeriod()
    }

    private static func exams(
        on date: Date,
        from exams: [ExamArrangement],
        calendar: Calendar
    ) -> [ExamArrangement] {
        exams
            .filter { exam in
                guard let start = exam.startsAt else { return false }
                return calendar.isDate(start, inSameDayAs: date)
            }
            .sorted { ($0.startsAt ?? .distantFuture) < ($1.startsAt ?? .distantFuture) }
    }

    private static func cellReminders(
        on date: Date,
        from reminders: [TimetableCellReminder],
        calendar: Calendar
    ) -> [TimetableCellReminder] {
        reminders
            .filter { reminder in
                guard let start = reminder.resolvedStartDate else { return false }
                return calendar.isDate(start, inSameDayAs: date)
            }
            .sorted { lhs, rhs in
                (lhs.resolvedStartDate ?? .distantFuture) < (rhs.resolvedStartDate ?? .distantFuture)
            }
    }

    private static func nextFireDate(
        startingAt startDay: Date,
        setting: ScheduleReportModeSetting,
        now: Date,
        calendar: Calendar
    ) -> Date? {
        for dayOffset in 0..<lookaheadDays {
            let day = calendar.date(byAdding: .day, value: dayOffset, to: startDay) ?? startDay
            guard let fireDate = fireDate(on: day, setting: setting, calendar: calendar),
                  fireDate > now else { continue }
            return fireDate
        }
        return nil
    }

    private static func fireDate(
        on day: Date,
        setting: ScheduleReportModeSetting,
        calendar: Calendar
    ) -> Date? {
        calendar.date(
            bySettingHour: setting.hour,
            minute: setting.minute,
            second: 0,
            of: day
        )
    }

    private static func notificationID(
        mode: ScheduleReportMode,
        fireDate: Date,
        calendar: Calendar
    ) -> String {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let stamp = [
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0,
            components.hour ?? 0,
            components.minute ?? 0
        ]
        .map { String(format: "%02d", $0) }
        .joined()
        return "leafy.scheduleReport.\(mode.rawValue).\(stamp)"
    }
}

@MainActor
enum ScheduleReportNotificationManager {
    static func updateNotifications(
        settings: ScheduleReportSettings,
        input: ScheduleReportInput,
        now: Date = Date()
    ) async throws -> ScheduleReportSettings {
        cancelScheduledNotifications(settings: settings)

        var updatedSettings = settings
        updatedSettings.scheduledNotificationIDs = []

        let drafts = ScheduleReportPlanner.drafts(settings: settings, input: input, now: now)
        guard settings.isEnabled, !drafts.isEmpty else {
            return updatedSettings
        }

        let center = try await authorizedNotificationCenter()
        for draft in drafts {
            let content = UNMutableNotificationContent()
            content.title = draft.title
            content.body = draft.body
            content.sound = .default
            content.userInfo = ["url": draft.targetURL.absoluteString]

            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: draft.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: draft.id, content: content, trigger: trigger)
            try await center.add(request)
            updatedSettings.scheduledNotificationIDs.append(draft.id)
        }

        return updatedSettings
    }

    static func cancelScheduledNotifications(settings: ScheduleReportSettings) {
        guard !settings.scheduledNotificationIDs.isEmpty else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: settings.scheduledNotificationIDs)
    }

    static func clearScheduledNotifications(defaults: UserDefaults = .standard) {
        let settings = ScheduleReportSettingsStore.load(defaults: defaults)
        cancelScheduledNotifications(settings: settings)
        var clearedSettings = settings
        clearedSettings.scheduledNotificationIDs = []
        ScheduleReportSettingsStore.save(clearedSettings, defaults: defaults)
    }

    static func refreshIfEnabled(
        modelContext: ModelContext,
        defaults: UserDefaults = .standard
    ) async throws {
        let settings = ScheduleReportSettingsStore.load(defaults: defaults)
        guard settings.isEnabled else { return }

        let input = ScheduleReportDataSource.input(modelContext: modelContext)
        let updatedSettings = try await updateNotifications(settings: settings, input: input)
        ScheduleReportSettingsStore.save(updatedSettings, defaults: defaults)
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
}

@MainActor
enum ScheduleReportDataSource {
    static func input(modelContext: ModelContext) -> ScheduleReportInput {
        ScheduleReportInput(
            courses: fetch(Course.self, in: modelContext),
            exams: SchoolDataCache.loadExamSchedule(),
            countdowns: CustomScheduleStore.load(),
            cellReminders: fetch(TimetableCellReminder.self, in: modelContext)
        )
    }

    private static func fetch<T: PersistentModel>(_ type: T.Type, in modelContext: ModelContext) -> [T] {
        (try? modelContext.fetch(FetchDescriptor<T>())) ?? []
    }
}
