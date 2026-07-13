import CoreLocation
import XCTest
@testable import Leafy

final class TimetableWeatherAdviceTests: XCTestCase {
    @MainActor
    func testWeatherKitTimetableWeatherServiceReturnsFetchedSnapshotAndCaches() async throws {
        let expected = makeSnapshot(hours: [makeHour(date: classStartDate, temperature: 24, condition: "多云")])
        let cache = InMemoryTimetableWeatherCache()
        let service = WeatherKitTimetableWeatherService(
            locationProvider: StubTimetableLocationProvider(),
            weatherFetcher: { _ in expected },
            cache: cache
        )

        let result = try await service.fetchCurrentWeather(requestsPermissionIfNeeded: false)

        XCTAssertEqual(result, expected)
        XCTAssertEqual(cache.currentWeather(maxAge: 60), expected)
    }

    @MainActor
    func testWeatherKitTimetableWeatherServiceFallsBackToFreshCache() async throws {
        let cached = makeSnapshot(hours: [makeHour(date: classStartDate, temperature: 18, condition: "晴")])
        let cache = InMemoryTimetableWeatherCache(snapshot: cached, savedAt: Date())
        let service = WeatherKitTimetableWeatherService(
            locationProvider: StubTimetableLocationProvider(),
            weatherFetcher: { _ in throw URLError(.badServerResponse) },
            cache: cache
        )

        let result = try await service.fetchCurrentWeather(requestsPermissionIfNeeded: false)

        XCTAssertEqual(result, cached)
    }

    @MainActor
    func testWeatherKitTimetableWeatherServiceThrowsWhenCacheExpired() async {
        let cached = makeSnapshot(hours: [makeHour(date: classStartDate, temperature: 18, condition: "晴")])
        let cache = InMemoryTimetableWeatherCache(
            snapshot: cached,
            savedAt: Date(timeIntervalSinceNow: -(31 * 60))
        )
        let service = WeatherKitTimetableWeatherService(
            locationProvider: StubTimetableLocationProvider(),
            weatherFetcher: { _ in throw URLError(.badServerResponse) },
            cache: cache
        )

        do {
            _ = try await service.fetchCurrentWeather(requestsPermissionIfNeeded: false)
            XCTFail("Expected expired cache to surface a weather error.")
        } catch {
            XCTAssertEqual(error as? TimetableWeatherServiceError, .weatherUnavailable)
        }
    }

    @MainActor
    func testWeatherKitTimetableWeatherServiceRequiresPermissionWithoutCache() async {
        let unusedSnapshot = makeSnapshot(hours: [])
        let service = WeatherKitTimetableWeatherService(
            locationProvider: StubTimetableLocationProvider(error: TimetableWeatherServiceError.permissionRequired),
            weatherFetcher: { _ in unusedSnapshot },
            cache: InMemoryTimetableWeatherCache()
        )

        do {
            _ = try await service.fetchCurrentWeather(requestsPermissionIfNeeded: false)
            XCTFail("Expected permission requirement.")
        } catch {
            XCTAssertEqual(error as? TimetableWeatherServiceError, .permissionRequired)
        }
    }

    func testTimetableCapsuleTextRoundsTemperatureAndUsesCelsiusUnit() {
        let mild = makeSnapshot(hours: [
            makeHour(date: classStartDate, temperature: 23.4, condition: "多云")
        ])
        let cold = makeSnapshot(hours: [
            makeHour(date: classStartDate, temperature: -2.6, condition: "雪")
        ])

        XCTAssertEqual(mild.timetableCapsuleText, "23℃ 多云")
        XCTAssertEqual(cold.timetableCapsuleText, "-3℃ 雪天")
    }

    func testTimetableCapsuleTextUsesTwoCharacterWeatherConditions() {
        let cases = [
            ("晴", "晴天"),
            ("阴", "阴天"),
            ("雨", "雨天"),
            ("毛毛雨", "小雨"),
            ("雪", "雪天"),
            ("雾", "雾天"),
            ("多云", "多云"),
            ("雷雨", "雷雨"),
            ("未知", "天气")
        ]

        for (condition, expected) in cases {
            let snapshot = makeSnapshot(hours: [
                makeHour(date: classStartDate, temperature: 20, condition: condition)
            ])

            XCTAssertEqual(snapshot.timetableCapsuleText, "20℃ \(expected)")
            XCTAssertEqual(expected.count, 2)
        }
    }

    func testWeatherAttributionRoundTripsMarkURLsAndDecodesLegacyCache() throws {
        let attribution = TimetableWeatherAttribution(
            serviceName: "Apple Weather",
            legalPageURL: URL(string: "https://example.com/legal")!,
            combinedMarkLightURL: URL(string: "https://example.com/light.svg"),
            combinedMarkDarkURL: URL(string: "https://example.com/dark.svg")
        )

        let decoded = try JSONDecoder().decode(
            TimetableWeatherAttribution.self,
            from: JSONEncoder().encode(attribution)
        )
        XCTAssertEqual(decoded, attribution)

        let legacyData = Data(#"{"serviceName":"Weather","legalPageURL":"https://example.com/legal"}"#.utf8)
        let legacy = try JSONDecoder().decode(TimetableWeatherAttribution.self, from: legacyData)
        XCTAssertNil(legacy.combinedMarkLightURL)
        XCTAssertNil(legacy.combinedMarkDarkURL)
    }

    func testUpcomingHourlyForecastSortsFiltersAndLimitsHours() {
        let now = classStartDate
        let snapshot = makeSnapshot(hours: [
            makeHour(date: now.addingTimeInterval(3 * 3600), temperature: 23, condition: "晴"),
            makeHour(date: now.addingTimeInterval(-2 * 3600), temperature: 18, condition: "晴"),
            makeHour(date: now.addingTimeInterval(3600), temperature: 21, condition: "多云"),
            makeHour(date: now.addingTimeInterval(2 * 3600), temperature: 22, condition: "雨")
        ])

        let hours = snapshot.upcomingHourlyForecast(now: now, limit: 2)

        XCTAssertEqual(hours.map(\.temperature), [21, 22])
    }

    func testScheduleItemsKeepOnlyTodayCurrentWeekFutureItems() {
        let now = classStartDate.addingTimeInterval(-30 * 60)
        let currentCourse = Course(courseName: "高等数学", teacher: "王老师", room: "一教 101", dayOfWeek: 1, weeks: [1], duration: [1, 2])
        let otherWeekCourse = Course(courseName: "大学英语", teacher: "李老师", room: "二教 201", dayOfWeek: 1, weeks: [2], duration: [1])
        let otherDayCourse = Course(courseName: "体育", teacher: "赵老师", room: "操场", dayOfWeek: 2, weeks: [1], duration: [1])
        let pastReminder = TimetableCellReminder(week: 1, dayOfWeek: 1, period: 1, title: "晨读", startsAt: now.addingTimeInterval(-90 * 60), endsAt: now.addingTimeInterval(-30 * 60))
        let futureReminder = TimetableCellReminder(week: 1, dayOfWeek: 1, period: 3, title: "交作业")
        let exam = ExamArrangement(
            id: 1,
            courseID: "MATH",
            name: "线代考试",
            date: DateFormatters.queryDate.string(from: now),
            start: "10:00",
            end: "11:30",
            location: "主楼"
        )

        let items = TimetableWeatherAdviceBuilder.scheduleItems(
            courses: [currentCourse, otherWeekCourse, otherDayCourse],
            cellReminders: [pastReminder, futureReminder],
            exams: [exam],
            currentWeek: 1,
            now: now
        )

        XCTAssertEqual(items.map(\.displayTitle), ["高等数学", "交作业", "线代考试"])
    }

    func testRainSuggestionMentionsAffectedCourse() {
        let now = classStartDate.addingTimeInterval(-30 * 60)
        let course = Course(courseName: "高等数学", teacher: "王老师", room: "一教 101", dayOfWeek: 1, weeks: [1], duration: [1, 2])
        let items = TimetableWeatherAdviceBuilder.scheduleItems(
            courses: [course],
            cellReminders: [],
            exams: [],
            currentWeek: 1,
            now: now
        )
        let snapshot = makeSnapshot(hours: [
            makeHour(date: classStartDate, temperature: 21, condition: "雨", symbolName: "cloud.rain", precipitationChance: 0.6)
        ])

        let summary = TimetableWeatherAdviceBuilder.makeSummary(snapshot: snapshot, scheduleItems: items, now: now)

        XCTAssertEqual(summary.suggestions.first?.id, "rain")
        XCTAssertTrue(summary.suggestions.first?.detail.contains("高等数学") == true)
    }

    func testColdSuggestionAsksForExtraLayer() {
        let now = classStartDate.addingTimeInterval(-30 * 60)
        let item = TimetableWeatherScheduleItem(title: "早八", kind: .course, startsAt: classStartDate, endsAt: classEndDate)
        let snapshot = makeSnapshot(hours: [
            makeHour(date: classStartDate, temperature: 5, condition: "晴", symbolName: "sun.max")
        ])

        let summary = TimetableWeatherAdviceBuilder.makeSummary(snapshot: snapshot, scheduleItems: [item], now: now)

        XCTAssertTrue(summary.suggestions.contains { $0.id == "cold" })
    }

    func testHeatAndUVSuggestionsCanAppearTogether() {
        let now = classStartDate.addingTimeInterval(-30 * 60)
        let item = TimetableWeatherScheduleItem(title: "植物学", kind: .course, startsAt: classStartDate, endsAt: classEndDate)
        let snapshot = makeSnapshot(hours: [
            makeHour(date: classStartDate, temperature: 32, condition: "晴", symbolName: "sun.max", uvIndex: 8, isDaylight: true)
        ])

        let summary = TimetableWeatherAdviceBuilder.makeSummary(snapshot: snapshot, scheduleItems: [item], now: now)
        let ids = summary.suggestions.map(\.id)

        XCTAssertTrue(ids.contains("heat"))
        XCTAssertTrue(ids.contains("uv"))
    }

    func testNoFutureScheduleUsesEmptyDaySuggestion() {
        let now = classStartDate.addingTimeInterval(-30 * 60)
        let snapshot = makeSnapshot(hours: [
            makeHour(date: classStartDate, temperature: 22, condition: "晴", symbolName: "sun.max")
        ])

        let summary = TimetableWeatherAdviceBuilder.makeSummary(snapshot: snapshot, scheduleItems: [], now: now)

        XCTAssertEqual(summary.suggestions, [
            TimetableWeatherSuggestion(
                id: "clear-empty",
                systemImage: "sparkles",
                title: "今天后续无课",
                detail: "今天没有后续课程安排，外出前可关注最新天气变化。"
            )
        ])
    }

    func testCalmWeatherUsesDefaultScheduleSuggestion() {
        let now = classStartDate.addingTimeInterval(-30 * 60)
        let item = TimetableWeatherScheduleItem(title: "英语", kind: .course, startsAt: classStartDate, endsAt: classEndDate)
        let snapshot = makeSnapshot(hours: [
            makeHour(date: classStartDate, temperature: 22, condition: "多云", symbolName: "cloud.sun")
        ])

        let summary = TimetableWeatherAdviceBuilder.makeSummary(snapshot: snapshot, scheduleItems: [item], now: now)

        XCTAssertEqual(summary.suggestions.first?.id, "clear")
    }

    private var classStartDate: Date {
        TimetablePeriodSchedule.startDate(week: 1, dayOfWeek: 1, period: 1)!
    }

    private var classEndDate: Date {
        TimetablePeriodSchedule.endDate(week: 1, dayOfWeek: 1, period: 2)!
    }

    private func makeSnapshot(hours: [TimetableHourlyWeather]) -> TimetableWeatherSnapshot {
        TimetableWeatherSnapshot(
            temperature: hours.first?.temperature ?? 22,
            condition: hours.first?.condition ?? "晴",
            symbolName: hours.first?.symbolName ?? "sun.max",
            observedAt: hours.first?.date ?? classStartDate,
            hourlyForecast: hours,
            attribution: .appleWeather
        )
    }

    private func makeHour(
        date: Date,
        temperature: Double,
        condition: String,
        symbolName: String = "cloud.sun",
        precipitationChance: Double = 0,
        uvIndex: Int = 0,
        isDaylight: Bool = true
    ) -> TimetableHourlyWeather {
        TimetableHourlyWeather(
            date: date,
            temperature: temperature,
            condition: condition,
            symbolName: symbolName,
            precipitationChance: precipitationChance,
            uvIndex: uvIndex,
            isDaylight: isDaylight
        )
    }
}

private final class StubTimetableLocationProvider: TimetableLocationProviding, @unchecked Sendable {
    private let state: TimetableWeatherAuthorizationState
    private let location: CLLocation
    private let error: Error?

    init(
        state: TimetableWeatherAuthorizationState = .authorized,
        location: CLLocation = CLLocation(latitude: 40.006, longitude: 116.352),
        error: Error? = nil
    ) {
        self.state = state
        self.location = location
        self.error = error
    }

    @MainActor
    func authorizationState() -> TimetableWeatherAuthorizationState {
        state
    }

    @MainActor
    func currentLocation(requestsPermissionIfNeeded: Bool) async throws -> CLLocation {
        if let error {
            throw error
        }
        return location
    }
}

private final class InMemoryTimetableWeatherCache: TimetableWeatherCaching, @unchecked Sendable {
    private var snapshot: TimetableWeatherSnapshot?
    private var savedAt: Date?

    init(snapshot: TimetableWeatherSnapshot? = nil, savedAt: Date? = nil) {
        self.snapshot = snapshot
        self.savedAt = savedAt
    }

    func save(_ snapshot: TimetableWeatherSnapshot) {
        self.snapshot = snapshot
        savedAt = Date()
    }

    func currentWeather(maxAge: TimeInterval) -> TimetableWeatherSnapshot? {
        guard let snapshot,
              let savedAt,
              Date().timeIntervalSince(savedAt) <= maxAge else {
            return nil
        }
        return snapshot
    }
}
