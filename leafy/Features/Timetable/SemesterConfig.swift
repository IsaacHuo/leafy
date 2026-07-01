//
//  SemesterConfig.swift
//  leafy
//
//  Created by IsaacHuo on 2026/4/21.
//

import Foundation
import Supabase

nonisolated struct SemesterRuntimeConfig: Codable, Hashable, Sendable {
    let semesterID: String
    let semesterStartDateString: String
    let supportedWeeks: Int
    let graduateTimetableTermCode: String
    let calendarEvents: [SchoolCalendarEvent]
    let updatedAt: String?
    let isActive: Bool

    var semesterStartDate: Date {
        Self.date(from: semesterStartDateString) ?? Date()
    }

    var isUsable: Bool {
        !semesterID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !graduateTimetableTermCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        supportedWeeks > 0 &&
        Self.date(from: semesterStartDateString) != nil
    }

    static let builtIn = SemesterRuntimeConfig(
        semesterID: "2025-2026-2",
        semesterStartDateString: "2026-03-09",
        supportedWeeks: 20,
        graduateTimetableTermCode: "46",
        calendarEvents: [
            SchoolCalendarEvent(id: "bjfu-sports-2026", title: "运动会停课", startDateString: "2026-04-24", endDateString: "2026-04-24", kind: .closure)
        ],
        updatedAt: nil,
        isActive: true
    )

    private static func date(from string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter.date(from: string)
    }
}

nonisolated enum SemesterRuntimeConfigCache {
    private static let key = "semester.runtimeConfig.v1"

    static func load(defaults: UserDefaults = .standard) -> SemesterRuntimeConfig? {
        migrateLegacyValue(defaults: defaults)
        guard let data = defaults.data(forKey: scopedKey(defaults: defaults)),
              let config = try? JSONDecoder().decode(SemesterRuntimeConfig.self, from: data),
              config.isUsable else {
            return nil
        }
        return config
    }

    static func save(_ config: SemesterRuntimeConfig, defaults: UserDefaults = .standard) {
        guard config.isUsable,
              let data = try? JSONEncoder().encode(config) else {
            return
        }
        defaults.set(data, forKey: scopedKey(defaults: defaults))
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: scopedKey(defaults: defaults))
    }

    private static func scopedKey(defaults: UserDefaults) -> String {
        CampusScopedDefaults.key(key, defaults: defaults)
    }

    private static func migrateLegacyValue(defaults: UserDefaults) {
        CampusScopedDefaults.migrateLegacyValuesIfNeeded(
            keys: [key],
            migrationID: "semesterConfig",
            identity: CampusIdentityStore.currentIdentity(defaults: defaults),
            defaults: defaults
        )
    }
}

actor SemesterRuntimeConfigService {
    static let shared = SemesterRuntimeConfigService()

    private let minimumRefreshInterval: TimeInterval = 60 * 60
    private var activeRefreshTask: Task<SemesterRuntimeConfig, Never>?
    private var lastAttemptAt: Date?

    private init() {}

    func refreshFromRemoteIfAvailable(force: Bool = false) async -> SemesterRuntimeConfig {
        if !force,
           let lastAttemptAt,
           Date().timeIntervalSince(lastAttemptAt) < minimumRefreshInterval {
            return SemesterConfig.current
        }

        if let activeRefreshTask {
            return await activeRefreshTask.value
        }

        let previous = SemesterConfig.current
        let task = Task<SemesterRuntimeConfig, Never> {
            do {
                let remoteConfig = try await Self.fetchRemoteActiveConfig()
                guard remoteConfig.isActive, remoteConfig.isUsable else {
                    return previous
                }
                SemesterRuntimeConfigCache.save(remoteConfig)
                return remoteConfig
            } catch {
                return previous
            }
        }

        activeRefreshTask = task
        lastAttemptAt = Date()
        let result = await task.value
        activeRefreshTask = nil

        if result != previous {
            await MainActor.run {
                NotificationCenter.default.post(name: .semesterRuntimeConfigDidChange, object: nil)
            }
        }

        return result
    }

    private static func fetchRemoteActiveConfig() async throws -> SemesterRuntimeConfig {
        let client = try LeafySupabase.shared.requireClient()
        let records: [RemoteSemesterRuntimeConfigRecord] = try await client
            .from("semester_runtime_configs")
            .select()
            .eq("campus_id", value: ActiveCampusContext.descriptor.id.rawValue)
            .eq("is_active", value: true)
            .order("updated_at", ascending: false)
            .limit(1)
            .execute()
            .value

        guard let record = records.first else {
            throw URLError(.resourceUnavailable)
        }

        return record.runtimeConfig
    }
}

private nonisolated struct RemoteSemesterRuntimeConfigRecord: Decodable, Sendable {
    let semesterID: String
    let semesterStartDateString: String
    let supportedWeeks: Int
    let graduateTimetableTermCode: String
    let calendarEvents: [SchoolCalendarEvent]
    let updatedAt: String?
    let isActive: Bool

    var runtimeConfig: SemesterRuntimeConfig {
        SemesterRuntimeConfig(
            semesterID: semesterID,
            semesterStartDateString: semesterStartDateString,
            supportedWeeks: supportedWeeks,
            graduateTimetableTermCode: graduateTimetableTermCode,
            calendarEvents: calendarEvents,
            updatedAt: updatedAt,
            isActive: isActive
        )
    }

    enum CodingKeys: String, CodingKey {
        case semesterID = "semester_id"
        case semesterStartDateString = "semester_start_date"
        case supportedWeeks = "supported_weeks"
        case graduateTimetableTermCode = "graduate_timetable_term_code"
        case calendarEvents = "calendar_events"
        case updatedAt = "updated_at"
        case isActive = "is_active"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        semesterID = try container.decode(String.self, forKey: .semesterID)
        semesterStartDateString = try container.decode(String.self, forKey: .semesterStartDateString)
        supportedWeeks = try container.decode(Int.self, forKey: .supportedWeeks)
        graduateTimetableTermCode = try container.decode(String.self, forKey: .graduateTimetableTermCode)
        calendarEvents = try container.decodeIfPresent([SchoolCalendarEvent].self, forKey: .calendarEvents) ?? []
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? false
    }
}

nonisolated struct SemesterConfig {
    static var sunshineRunExcludedWeeks: Set<Int> {
        AcademicCalendarEvents.nationalHolidayWeeks(
            semesterStart: startOfSemesterDate,
            totalWeeks: supportedWeeks
        )
    }

    static var current: SemesterRuntimeConfig {
        SemesterRuntimeConfigCache.load() ?? .builtIn
    }

    static var startOfSemesterString: String {
        current.semesterStartDateString
    }

    static var currentSemesterID: String {
        current.semesterID
    }

    static var graduateTimetableTermCode: String {
        current.graduateTimetableTermCode
    }

    static var calendarEvents: [SchoolCalendarEvent] {
        current.calendarEvents
    }

    static func campusCalendarEvents(campusID: CampusID = ActiveCampusContext.descriptor.id) -> [SchoolCalendarEvent] {
        guard campusID == .bjfu else { return [] }
        return current.calendarEvents.filter { $0.kind == .closure }
    }

    static var startOfSemesterDate: Date {
        current.semesterStartDate
    }

    static var supportedWeeks: Int {
        current.supportedWeeks
    }

    @discardableResult
    static func refreshRemoteIfAvailable(force: Bool = false) async -> SemesterRuntimeConfig {
        async let nationalCalendarRefresh: NationalCalendarRuntimeConfig = NationalHolidayCalendar.refreshRemoteIfAvailable(force: force)
        let semesterConfig = await SemesterRuntimeConfigService.shared.refreshFromRemoteIfAvailable(force: force)
        _ = await nationalCalendarRefresh
        return semesterConfig
    }

    static func currentWeek(date: Date = Date(), config: SemesterRuntimeConfig = current) -> Int {
        let now = date

        let calendar = Calendar.current
        // Remove time components for pure day comparison
        let start = calendar.startOfDay(for: config.semesterStartDate)
        let current = calendar.startOfDay(for: now)

        let components = calendar.dateComponents([.day], from: start, to: current)
        let days = components.day ?? 0

        var week = Int(ceil(Double(days + 1) / 7.0))

        if week < 1 {
            week = 1
        } else if week > config.supportedWeeks {
            week = config.supportedWeeks
        }

        return week
    }

    static func weekAndDay(for date: Date, config: SemesterRuntimeConfig = current) -> (week: Int, day: Int) {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: config.semesterStartDate)
        let current = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: start, to: current).day ?? 0

        let week = max(1, min(config.supportedWeeks, days / 7 + 1))
        let weekday = calendar.component(.weekday, from: current)
        let day = ((weekday + 5) % 7) + 1
        return (week, day)
    }
}

nonisolated struct SchoolCalendarEvent: Identifiable, Codable, Hashable, Sendable {
    enum Kind: String, Codable, Hashable, Sendable {
        case holiday
        case closure
        case solarTerm
    }

    enum SolarTermSeason: String, Hashable, Sendable {
        case spring
        case summer
        case autumn
        case winter
    }

    let id: String
    let title: String
    let startDateString: String
    let endDateString: String
    let kind: Kind

    init(id: String, title: String, startDateString: String, endDateString: String, kind: Kind) {
        self.id = id
        self.title = title
        self.startDateString = startDateString
        self.endDateString = endDateString
        self.kind = kind
    }

    var startDate: Date? {
        Self.dateFormatter.date(from: startDateString)
    }

    var endDate: Date? {
        Self.dateFormatter.date(from: endDateString)
    }

    var solarTermSeason: SolarTermSeason? {
        guard kind == .solarTerm else { return nil }
        switch title {
        case "立春", "雨水", "惊蛰", "春分", "清明", "谷雨":
            return .spring
        case "立夏", "小满", "芒种", "夏至", "小暑", "大暑":
            return .summer
        case "立秋", "处暑", "白露", "秋分", "寒露", "霜降":
            return .autumn
        case "立冬", "小雪", "大雪", "冬至", "小寒", "大寒":
            return .winter
        default:
            return nil
        }
    }

    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard let startDate, let endDate else { return false }
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)
        let target = calendar.startOfDay(for: date)
        return target >= start && target <= end
    }

    static func event(on date: Date) -> SchoolCalendarEvent? {
        AcademicCalendarEvents.event(on: date)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case startDateString
        case endDateString
        case startDate = "start_date"
        case endDate = "end_date"
        case kind
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        startDateString = try container.decodeIfPresent(String.self, forKey: .startDateString)
            ?? container.decode(String.self, forKey: .startDate)
        endDateString = try container.decodeIfPresent(String.self, forKey: .endDateString)
            ?? container.decode(String.self, forKey: .endDate)
        kind = try container.decode(Kind.self, forKey: .kind)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(startDateString, forKey: .startDateString)
        try container.encode(endDateString, forKey: .endDateString)
        try container.encode(kind, forKey: .kind)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter
    }()
}

nonisolated struct NationalHolidayEvent: Identifiable, Codable, Hashable, Sendable {
    enum Kind: String, Codable, Hashable, Sendable {
        case holiday
    }

    let id: String
    let title: String
    let startDateString: String
    let endDateString: String
    let kind: Kind

    init(id: String, title: String, startDateString: String, endDateString: String, kind: Kind = .holiday) {
        self.id = id
        self.title = title
        self.startDateString = startDateString
        self.endDateString = endDateString
        self.kind = kind
    }

    var schoolCalendarEvent: SchoolCalendarEvent {
        SchoolCalendarEvent(
            id: id,
            title: title,
            startDateString: startDateString,
            endDateString: endDateString,
            kind: .holiday
        )
    }

    var startDate: Date? {
        Self.dateFormatter.date(from: startDateString)
    }

    var endDate: Date? {
        Self.dateFormatter.date(from: endDateString)
    }

    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        schoolCalendarEvent.contains(date, calendar: calendar)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case startDateString
        case endDateString
        case startDate = "start_date"
        case endDate = "end_date"
        case kind
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        startDateString = try container.decodeIfPresent(String.self, forKey: .startDateString)
            ?? container.decode(String.self, forKey: .startDate)
        endDateString = try container.decodeIfPresent(String.self, forKey: .endDateString)
            ?? container.decode(String.self, forKey: .endDate)
        kind = try container.decodeIfPresent(Kind.self, forKey: .kind) ?? .holiday
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(startDateString, forKey: .startDateString)
        try container.encode(endDateString, forKey: .endDateString)
        try container.encode(kind, forKey: .kind)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter
    }()
}

nonisolated struct SolarTermEvent: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let title: String
    let dateString: String

    init(id: String, title: String, dateString: String) {
        self.id = id
        self.title = title
        self.dateString = dateString
    }

    var schoolCalendarEvent: SchoolCalendarEvent {
        SchoolCalendarEvent(
            id: id,
            title: title,
            startDateString: dateString,
            endDateString: dateString,
            kind: .solarTerm
        )
    }

    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        schoolCalendarEvent.contains(date, calendar: calendar)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case dateString
        case date = "date_string"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        dateString = try container.decodeIfPresent(String.self, forKey: .dateString)
            ?? container.decode(String.self, forKey: .date)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(dateString, forKey: .dateString)
    }
}

nonisolated struct NationalCalendarRuntimeConfig: Codable, Hashable, Sendable {
    let year: Int
    let holidays: [NationalHolidayEvent]
    let solarTerms: [SolarTermEvent]
    let updatedAt: String?
    let isActive: Bool

    static let builtIn = NationalCalendarRuntimeConfig(
        year: 2026,
        holidays: [
            NationalHolidayEvent(id: "new-year-2026", title: "元旦", startDateString: "2026-01-01", endDateString: "2026-01-03"),
            NationalHolidayEvent(id: "spring-festival-2026", title: "春节", startDateString: "2026-02-15", endDateString: "2026-02-23"),
            NationalHolidayEvent(id: "qingming-2026", title: "清明", startDateString: "2026-04-04", endDateString: "2026-04-06"),
            NationalHolidayEvent(id: "labor-2026", title: "五一", startDateString: "2026-05-01", endDateString: "2026-05-05"),
            NationalHolidayEvent(id: "dragonboat-2026", title: "端午", startDateString: "2026-06-19", endDateString: "2026-06-21"),
            NationalHolidayEvent(id: "midautumn-2026", title: "中秋", startDateString: "2026-09-25", endDateString: "2026-09-27"),
            NationalHolidayEvent(id: "national-day-2026", title: "国庆", startDateString: "2026-10-01", endDateString: "2026-10-07")
        ],
        solarTerms: [
            SolarTermEvent(id: "minor-cold-2026", title: "小寒", dateString: "2026-01-05"),
            SolarTermEvent(id: "major-cold-2026", title: "大寒", dateString: "2026-01-20"),
            SolarTermEvent(id: "start-spring-2026", title: "立春", dateString: "2026-02-04"),
            SolarTermEvent(id: "rain-water-2026", title: "雨水", dateString: "2026-02-19"),
            SolarTermEvent(id: "insects-awaken-2026", title: "惊蛰", dateString: "2026-03-05"),
            SolarTermEvent(id: "spring-equinox-2026", title: "春分", dateString: "2026-03-20"),
            SolarTermEvent(id: "pure-brightness-2026", title: "清明", dateString: "2026-04-04"),
            SolarTermEvent(id: "grain-rain-2026", title: "谷雨", dateString: "2026-04-20"),
            SolarTermEvent(id: "start-summer-2026", title: "立夏", dateString: "2026-05-05"),
            SolarTermEvent(id: "grain-full-2026", title: "小满", dateString: "2026-05-21"),
            SolarTermEvent(id: "grain-in-ear-2026", title: "芒种", dateString: "2026-06-05"),
            SolarTermEvent(id: "summer-solstice-2026", title: "夏至", dateString: "2026-06-21"),
            SolarTermEvent(id: "minor-heat-2026", title: "小暑", dateString: "2026-07-07"),
            SolarTermEvent(id: "major-heat-2026", title: "大暑", dateString: "2026-07-23"),
            SolarTermEvent(id: "start-autumn-2026", title: "立秋", dateString: "2026-08-07"),
            SolarTermEvent(id: "limit-heat-2026", title: "处暑", dateString: "2026-08-23"),
            SolarTermEvent(id: "white-dew-2026", title: "白露", dateString: "2026-09-07"),
            SolarTermEvent(id: "autumn-equinox-2026", title: "秋分", dateString: "2026-09-23"),
            SolarTermEvent(id: "cold-dew-2026", title: "寒露", dateString: "2026-10-08"),
            SolarTermEvent(id: "frost-descent-2026", title: "霜降", dateString: "2026-10-23"),
            SolarTermEvent(id: "start-winter-2026", title: "立冬", dateString: "2026-11-07"),
            SolarTermEvent(id: "minor-snow-2026", title: "小雪", dateString: "2026-11-22"),
            SolarTermEvent(id: "major-snow-2026", title: "大雪", dateString: "2026-12-07"),
            SolarTermEvent(id: "winter-solstice-2026", title: "冬至", dateString: "2026-12-22")
        ],
        updatedAt: nil,
        isActive: true
    )

    var isUsable: Bool {
        year > 0 && isActive && !holidays.isEmpty
    }
}

nonisolated enum NationalCalendarRuntimeConfigCache {
    private static let key = "nationalCalendar.runtimeConfig.v1"

    static func load(defaults: UserDefaults = .standard) -> NationalCalendarRuntimeConfig? {
        guard let data = defaults.data(forKey: key),
              let config = try? JSONDecoder().decode(NationalCalendarRuntimeConfig.self, from: data),
              config.isUsable else {
            return nil
        }
        return config
    }

    static func save(_ config: NationalCalendarRuntimeConfig, defaults: UserDefaults = .standard) {
        guard config.isUsable,
              let data = try? JSONEncoder().encode(config) else {
            return
        }
        defaults.set(data, forKey: key)
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}

actor NationalCalendarRuntimeConfigService {
    static let shared = NationalCalendarRuntimeConfigService()

    private let minimumRefreshInterval: TimeInterval = 60 * 60
    private var activeRefreshTask: Task<NationalCalendarRuntimeConfig, Never>?
    private var lastAttemptAt: Date?

    private init() {}

    func refreshFromRemoteIfAvailable(force: Bool = false) async -> NationalCalendarRuntimeConfig {
        if !force,
           let lastAttemptAt,
           Date().timeIntervalSince(lastAttemptAt) < minimumRefreshInterval {
            return NationalHolidayCalendar.current
        }

        if let activeRefreshTask {
            return await activeRefreshTask.value
        }

        let previous = NationalHolidayCalendar.current
        let task = Task<NationalCalendarRuntimeConfig, Never> {
            do {
                let remoteConfig = try await Self.fetchRemoteActiveConfig()
                guard remoteConfig.isUsable else {
                    return previous
                }
                NationalCalendarRuntimeConfigCache.save(remoteConfig)
                return remoteConfig
            } catch {
                return previous
            }
        }

        activeRefreshTask = task
        lastAttemptAt = Date()
        let result = await task.value
        activeRefreshTask = nil

        if result != previous {
            await MainActor.run {
                NotificationCenter.default.post(name: .nationalCalendarRuntimeConfigDidChange, object: nil)
            }
        }

        return result
    }

    private static func fetchRemoteActiveConfig() async throws -> NationalCalendarRuntimeConfig {
        let client = try LeafySupabase.shared.requireClient()
        let records: [RemoteNationalCalendarRuntimeConfigRecord] = try await client
            .from("national_calendar_runtime_configs")
            .select()
            .eq("is_active", value: true)
            .order("year", ascending: false)
            .order("updated_at", ascending: false)
            .limit(1)
            .execute()
            .value

        guard let record = records.first else {
            throw URLError(.resourceUnavailable)
        }

        return record.runtimeConfig
    }
}

private nonisolated struct RemoteNationalCalendarRuntimeConfigRecord: Decodable, Sendable {
    let year: Int
    let holidays: [NationalHolidayEvent]
    let solarTerms: [SolarTermEvent]
    let updatedAt: String?
    let isActive: Bool

    var runtimeConfig: NationalCalendarRuntimeConfig {
        NationalCalendarRuntimeConfig(
            year: year,
            holidays: holidays,
            solarTerms: solarTerms,
            updatedAt: updatedAt,
            isActive: isActive
        )
    }

    enum CodingKeys: String, CodingKey {
        case year
        case holidays
        case solarTerms = "solar_terms"
        case updatedAt = "updated_at"
        case isActive = "is_active"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        year = try container.decode(Int.self, forKey: .year)
        holidays = try container.decodeIfPresent([NationalHolidayEvent].self, forKey: .holidays) ?? []
        solarTerms = try container.decodeIfPresent([SolarTermEvent].self, forKey: .solarTerms) ?? []
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? false
    }
}

nonisolated enum NationalHolidayCalendar {
    static var current: NationalCalendarRuntimeConfig {
        NationalCalendarRuntimeConfigCache.load() ?? .builtIn
    }

    static var holidays: [NationalHolidayEvent] {
        current.holidays
    }

    static var solarTerms: [SolarTermEvent] {
        current.solarTerms
    }

    @discardableResult
    static func refreshRemoteIfAvailable(force: Bool = false) async -> NationalCalendarRuntimeConfig {
        await NationalCalendarRuntimeConfigService.shared.refreshFromRemoteIfAvailable(force: force)
    }
}

nonisolated enum AcademicCalendarEvents {
    static func events(
        for date: Date,
        campusID: CampusID = ActiveCampusContext.descriptor.id,
        calendar: Calendar = .current
    ) -> [SchoolCalendarEvent] {
        let nationalHoliday = NationalHolidayCalendar.holidays
            .first { $0.contains(date, calendar: calendar) }?
            .schoolCalendarEvent
        let campusEvent = SemesterConfig.campusCalendarEvents(campusID: campusID)
            .first { $0.contains(date, calendar: calendar) }
        let solarTerm = NationalHolidayCalendar.solarTerms
            .first { $0.contains(date, calendar: calendar) }?
            .schoolCalendarEvent

        return [nationalHoliday, campusEvent, solarTerm].compactMap(\.self)
    }

    static func event(
        on date: Date,
        campusID: CampusID = ActiveCampusContext.descriptor.id,
        calendar: Calendar = .current
    ) -> SchoolCalendarEvent? {
        events(for: date, campusID: campusID, calendar: calendar).first
    }

    static func displayEvents(campusID: CampusID = ActiveCampusContext.descriptor.id) -> [SchoolCalendarEvent] {
        let nationalHolidays = NationalHolidayCalendar.holidays.map(\.schoolCalendarEvent)
        let campusEvents = SemesterConfig.campusCalendarEvents(campusID: campusID)
        let solarTerms = NationalHolidayCalendar.solarTerms.map(\.schoolCalendarEvent)
        return nationalHolidays + campusEvents + solarTerms
    }

    static func nextNationalHoliday(
        from referenceDate: Date,
        calendar: Calendar = .current
    ) -> NationalHolidayEvent? {
        let today = calendar.startOfDay(for: referenceDate)
        return NationalHolidayCalendar.holidays
            .filter { holiday in
                guard let endDate = holiday.endDate else { return false }
                return calendar.startOfDay(for: endDate) >= today
            }
            .sorted { lhs, rhs in
                (lhs.startDate ?? .distantFuture) < (rhs.startDate ?? .distantFuture)
            }
            .first
    }

    static func nationalHolidayWeeks(
        semesterStart: Date,
        totalWeeks: Int,
        calendar: Calendar = .current
    ) -> Set<Int> {
        guard totalWeeks > 0 else { return [] }
        let semesterStart = calendar.startOfDay(for: semesterStart)
        let semesterEnd = calendar.date(byAdding: .day, value: totalWeeks * 7 - 1, to: semesterStart) ?? semesterStart
        var weeks = Set<Int>()

        for holiday in NationalHolidayCalendar.holidays {
            guard let holidayStart = holiday.startDate,
                  let holidayEnd = holiday.endDate else {
                continue
            }

            var currentDay = calendar.startOfDay(for: holidayStart > semesterStart ? holidayStart : semesterStart)
            let rangeEnd = calendar.startOfDay(for: holidayEnd < semesterEnd ? holidayEnd : semesterEnd)
            while currentDay <= rangeEnd {
                let offset = calendar.dateComponents([.day], from: semesterStart, to: currentDay).day ?? 0
                if offset >= 0, offset < totalWeeks * 7 {
                    weeks.insert(offset / 7 + 1)
                }
                guard let nextDay = calendar.date(byAdding: .day, value: 1, to: currentDay) else { break }
                currentDay = nextDay
            }
        }

        return weeks
    }
}

extension Notification.Name {
    static let semesterRuntimeConfigDidChange = Notification.Name("semesterRuntimeConfigDidChange")
    static let nationalCalendarRuntimeConfigDidChange = Notification.Name("nationalCalendarRuntimeConfigDidChange")
}
