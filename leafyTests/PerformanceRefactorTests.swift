import XCTest
import SwiftUI
import UIKit
import ImageIO
import UniformTypeIdentifiers
import Supabase
import SwiftData
@testable import Leafy

final class PerformanceRefactorTests: XCTestCase {
    func testAppLanguagePreferenceDefaultsToSimplifiedChinese() {
        XCTAssertEqual(AppLanguagePreference.current, .zhHans)
        XCTAssertEqual(AppLanguagePreference.zhHans.localeIdentifier, "zh-Hans")
        XCTAssertEqual(AppLanguagePreference.zhHans.weekdayTitle(for: 1), "周一")
        XCTAssertEqual(AppLanguagePreference.zhHans.weekdayTitle(for: 7), "周日")
    }

    func testSimplifiedChineseLocalizationReturnsSourceTextAndFormatsValues() {
        XCTAssertEqual(L10n.text("语言", language: .zhHans), "语言")
        XCTAssertEqual(L10n.text("第 %d 周", language: .zhHans, 3), "第 3 周")
    }

    func testTimetableResponsiveLayoutSwitchesToAgendaWhenSevenDayGridIsTooNarrow() {
        let widths: [CGFloat] = [320, 375, 507, 700, 1024, 1366]
        let modes = widths.map { width in
            timetableMetrics(width: width, height: 800, dayCount: 7, allowsAgendaList: true).mode
        }

        XCTAssertEqual(modes, [.agendaList, .agendaList, .agendaList, .weekGrid, .weekGrid, .weekGrid])
    }

    func testTimetableResponsiveLayoutKeepsPhoneGridWhenAgendaIsDisabled() {
        let metrics = timetableMetrics(width: 320, height: 800, dayCount: 7, allowsAgendaList: false)

        XCTAssertEqual(metrics.mode, .weekGrid)
    }

    func testTimetableResponsiveLayoutKeepsWeekdayGridAtMediumSplitWidth() {
        let metrics = timetableMetrics(width: 507, height: 800, dayCount: 5)

        XCTAssertEqual(metrics.mode, .weekGrid)
        XCTAssertGreaterThanOrEqual(metrics.dayColumnWidth, 72)
    }

    func testTimetableResponsiveLayoutAllowsVerticalScrollWhenHeightIsSmall() {
        let metrics = timetableMetrics(width: 700, height: 320, dayCount: 5)

        XCTAssertEqual(metrics.mode, .agendaList)
        XCTAssertEqual(metrics.rowHeight, 26)
        XCTAssertTrue(metrics.allowsVerticalScroll)
        XCTAssertGreaterThan(metrics.gridHeight, 320 - 52)
    }

    func testTimetableResponsiveLayoutHandlesDisplayScaleChanges() {
        let widths: [CGFloat] = [320, 375, 430, 700]
        let dayCounts = [5, 7]
        let controlScales: [CGFloat] = [0.88, 0.94, 1.0, 1.06]
        let height: CGFloat = 800

        for controlScale in controlScales {
            for dayCount in dayCounts {
                for width in widths {
                    let metrics = timetableMetrics(
                        width: width,
                        height: height,
                        dayCount: dayCount,
                        controlScale: controlScale
                    )
                    let repeatedMetrics = timetableMetrics(
                        width: width,
                        height: height,
                        dayCount: dayCount,
                        controlScale: controlScale
                    )

                    XCTAssertEqual(metrics, repeatedMetrics)
                    XCTAssertGreaterThan(metrics.rowHeight, 0)
                    XCTAssertGreaterThan(metrics.weekStride, 0)
                    XCTAssertGreaterThan(metrics.containerWidth, 0)
                    XCTAssertEqual(metrics.containerHeight, height)
                    XCTAssertGreaterThan(metrics.gridHeight, 0)
                    XCTAssertLessThan(metrics.rowHeight, height)
                    XCTAssertLessThan(metrics.gridHeight, height * 2)
                }
            }
        }
    }

    @MainActor
    func testOverlappingCoursesShareLaneCount() {
        let first = Course(
            courseName: "A",
            teacher: "T",
            room: "101",
            location: "",
            dayOfWeek: 1,
            weeks: [1],
            duration: [1, 2]
        )
        let second = Course(
            courseName: "B",
            teacher: "T",
            room: "102",
            location: "",
            dayOfWeek: 1,
            weeks: [1],
            duration: [2, 3]
        )
        let third = Course(
            courseName: "C",
            teacher: "T",
            room: "103",
            location: "",
            dayOfWeek: 1,
            weeks: [1],
            duration: [5]
        )

        let layouts = DayCourseLayoutBuilder.layouts(for: [first, second, third].sortedByStartPeriod())

        XCTAssertEqual(layouts.count, 3)
        XCTAssertEqual(layouts[0].laneCount, 2)
        XCTAssertEqual(layouts[1].laneCount, 2)
        XCTAssertEqual(layouts[2].laneCount, 1)
    }

    @MainActor
    func testGridSnapshotHidesWeekendsAndKeepsLatestReminder() {
        let mondayCourse = Course(
            courseName: "A",
            teacher: "T",
            room: "101",
            location: "",
            dayOfWeek: 1,
            weeks: [1],
            duration: [1]
        )
        let saturdayCourse = Course(
            courseName: "B",
            teacher: "T",
            room: "102",
            location: "",
            dayOfWeek: 6,
            weeks: [1],
            duration: [1]
        )
        let oldReminder = TimetableCellReminder(
            week: 1,
            dayOfWeek: 1,
            period: 2,
            title: "Old",
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        let newReminder = TimetableCellReminder(
            week: 1,
            dayOfWeek: 1,
            period: 2,
            title: "New",
            updatedAt: Date(timeIntervalSince1970: 2)
        )

        let snapshot = TimetableGridSnapshot.make(
            courses: [mondayCourse, saturdayCourse],
            notes: [],
            occurrenceNotes: [],
            cellReminders: [oldReminder, newReminder],
            hidesWeekends: true,
            totalWeeks: 1
        )

        XCTAssertEqual(snapshot.visibleDays, [1, 2, 3, 4, 5])
        XCTAssertEqual(snapshot.layouts(day: 1, week: 1).map(\.course.courseName), ["A"])
        XCTAssertTrue(snapshot.layouts(day: 6, week: 1).isEmpty)
        XCTAssertEqual(snapshot.cellReminder(week: 1, day: 1, period: 2)?.title, "New")
        XCTAssertEqual(snapshot.cellReminders(week: 1, day: 1).map(\.title), ["New"])
    }

    @MainActor
    func testGridSnapshotCacheReusesMatchingInputs() {
        let course = Course(
            courseName: "A",
            teacher: "T",
            room: "101",
            location: "",
            dayOfWeek: 1,
            weeks: [1, 2],
            duration: [1]
        )
        let cache = TimetableGridSnapshotCache()

        let first = cache.snapshot(
            courses: [course],
            notes: [],
            occurrenceNotes: [],
            cellReminders: [],
            hidesWeekends: false,
            totalWeeks: 2
        )
        let second = cache.snapshot(
            courses: [course],
            notes: [],
            occurrenceNotes: [],
            cellReminders: [],
            hidesWeekends: false,
            totalWeeks: 2
        )

        XCTAssertEqual(cache.buildCount, 1)
        XCTAssertEqual(first.layouts(day: 1, week: 1).map(\.course.courseName), ["A"])
        XCTAssertEqual(second.layouts(day: 1, week: 2).map(\.course.courseName), ["A"])

        let weekdaysOnly = cache.snapshot(
            courses: [course],
            notes: [],
            occurrenceNotes: [],
            cellReminders: [],
            hidesWeekends: true,
            totalWeeks: 2
        )
        XCTAssertEqual(cache.buildCount, 2)
        XCTAssertEqual(weekdaysOnly.visibleDays, [1, 2, 3, 4, 5])

        _ = cache.snapshot(
            courses: [course],
            notes: [],
            occurrenceNotes: [],
            cellReminders: [],
            hidesWeekends: true,
            totalWeeks: 3
        )
        XCTAssertEqual(cache.buildCount, 3)
    }

    @MainActor
    func testCourseReminderAnchorDefaultsToFirstPeriodForOldSettings() {
        let course = Course(
            courseName: "森林生态学",
            teacher: "T",
            room: "101",
            location: "",
            dayOfWeek: 1,
            weeks: [1],
            duration: [2, 3]
        )
        let oldSetting = CourseReminderSetting(courseKey: course.stableCourseKey, minutesBefore: 20)

        XCTAssertNil(oldSetting.anchorPeriod)
        XCTAssertEqual(TimetableNotificationManager.resolvedAnchorPeriod(oldSetting.anchorPeriod, for: course), 2)
    }

    @MainActor
    func testCourseReminderTriggerDateUsesSelectedAnchorPeriod() throws {
        let course = Course(
            courseName: "森林生态学",
            teacher: "T",
            room: "101",
            location: "",
            dayOfWeek: 1,
            weeks: [1],
            duration: [1, 2]
        )
        let triggerDate = try XCTUnwrap(TimetableNotificationManager.reminderTriggerDate(
            for: course,
            week: 1,
            minutesBefore: 5,
            anchorPeriod: 2
        ))
        let expectedDate = try XCTUnwrap(Calendar.current.date(
            from: DateComponents(year: 2026, month: 3, day: 9, hour: 8, minute: 45)
        ))

        XCTAssertEqual(triggerDate, expectedDate)
    }

    func testCustomReminderMinutesAreClampedToSupportedRange() {
        XCTAssertEqual(TimetableNotificationManager.normalizedReminderMinutes(-5), 0)
        XCTAssertEqual(TimetableNotificationManager.normalizedReminderMinutes(0), 0)
        XCTAssertEqual(TimetableNotificationManager.normalizedReminderMinutes(1), 1)
        XCTAssertEqual(TimetableNotificationManager.normalizedReminderMinutes(180), 180)
        XCTAssertEqual(TimetableNotificationManager.normalizedReminderMinutes(181), 180)
    }

    func testPeriodRangeUsesOverlappingClassSlots() throws {
        let calendar = Calendar.current
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 8, minute: 10)))
        let end = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 9, minute: 0)))
        let gapStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 12, minute: 20)))
        let gapEnd = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 13, minute: 0)))

        XCTAssertEqual(TimetablePeriodSchedule.periodRange(overlapping: start, endDate: end), 1...2)
        XCTAssertNil(TimetablePeriodSchedule.periodRange(overlapping: gapStart, endDate: gapEnd))
        XCTAssertNil(TimetablePeriodSchedule.periodRange(overlapping: end, endDate: start))
    }

    @MainActor
    func testGridSnapshotDistinguishesCourseAndOccurrenceNotes() {
        let course = Course(
            courseName: "体育",
            teacher: "T",
            room: "操场",
            location: "",
            dayOfWeek: 1,
            weeks: [1, 2],
            duration: [1]
        )
        let courseNote = CourseNote(courseKey: course.stableCourseKey, text: "带衣服")
        let occurrenceNote = CourseOccurrenceNote(
            courseKey: course.stableCourseKey,
            occurrenceKey: course.occurrenceKey(week: 1),
            week: 1,
            dayOfWeek: 1,
            text: "带球鞋"
        )

        let allWeeksSnapshot = TimetableGridSnapshot.make(
            courses: [course],
            notes: [courseNote],
            occurrenceNotes: [],
            cellReminders: [],
            hidesWeekends: false,
            totalWeeks: 2
        )
        XCTAssertTrue(allWeeksSnapshot.hasNote(for: course, week: 1))
        XCTAssertTrue(allWeeksSnapshot.hasNote(for: course, week: 2))
        XCTAssertEqual(allWeeksSnapshot.note(for: course, week: 1), "带衣服")

        let occurrenceOnlySnapshot = TimetableGridSnapshot.make(
            courses: [course],
            notes: [],
            occurrenceNotes: [occurrenceNote],
            cellReminders: [],
            hidesWeekends: false,
            totalWeeks: 2
        )
        XCTAssertTrue(occurrenceOnlySnapshot.hasNote(for: course, week: 1))
        XCTAssertFalse(occurrenceOnlySnapshot.hasNote(for: course, week: 2))
        XCTAssertEqual(occurrenceOnlySnapshot.note(for: course, week: 1), "带球鞋")
    }

    func testEffectiveCourseNotePrefersOccurrenceThenFallsBackToCourse() {
        let course = Course(
            courseName: "体育",
            teacher: "T",
            room: "操场",
            location: "",
            dayOfWeek: 1,
            weeks: [1, 2],
            duration: [1]
        )
        let courseNote = CourseNote(courseKey: course.stableCourseKey, text: "带衣服")
        let occurrenceNote = CourseOccurrenceNote(
            courseKey: course.stableCourseKey,
            occurrenceKey: course.occurrenceKey(week: 2),
            week: 2,
            dayOfWeek: 1,
            text: "带球鞋"
        )
        let emptyOccurrenceNote = CourseOccurrenceNote(
            courseKey: course.stableCourseKey,
            occurrenceKey: course.occurrenceKey(week: 1),
            week: 1,
            dayOfWeek: 1,
            text: " "
        )

        XCTAssertEqual(
            TimetableNoteResolver.effectiveNote(
                for: course,
                week: 2,
                courseNotes: [courseNote],
                occurrenceNotes: [occurrenceNote]
            ),
            "带球鞋"
        )
        XCTAssertEqual(
            TimetableNoteResolver.effectiveNote(
                for: course,
                week: 1,
                courseNotes: [courseNote],
                occurrenceNotes: [emptyOccurrenceNote]
            ),
            "带衣服"
        )
    }

    func testNearestAvailableWeekPrefersExactThenClosest() {
        let records = [
            ParsedCourseRecord(courseName: "A", teacher: "", classInfo: "", room: "", location: "", dayOfWeek: 1, weeks: [2, 6], duration: [1]),
            ParsedCourseRecord(courseName: "B", teacher: "", classInfo: "", room: "", location: "", dayOfWeek: 2, weeks: [10], duration: [2])
        ]

        XCTAssertEqual(TimetableRefreshUseCase.nearestAvailableWeek(from: records, preferredWeek: 6), 6)
        XCTAssertEqual(TimetableRefreshUseCase.nearestAvailableWeek(from: records, preferredWeek: 8), 6)
    }

    @MainActor
    func testSchoolNetworkRequestsBypassLocalCache() throws {
        let manager = SchoolNetworkManager.shared
        let url = try XCTUnwrap(URL(string: "http://newjwxt.bjfu.edu.cn/jsxsd/xskb/xskb_list.do"))

        let request = manager.makeRequest(url: url)
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-cache")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Pragma"), "no-cache")

        let preparedRequest = manager.preparedRequest(from: URLRequest(url: url))
        XCTAssertEqual(preparedRequest.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(preparedRequest.value(forHTTPHeaderField: "Cache-Control"), "no-cache")
        XCTAssertEqual(preparedRequest.value(forHTTPHeaderField: "Pragma"), "no-cache")
    }

    @MainActor
    func testTimetableQueryFormPrefersCurrentSemesterOption() throws {
        let html = """
        <form action="/jsxsd/xskb/xskb_list.do" method="post">
          <input type="hidden" name="zc" value="">
          <select name="xnxq01id">
            <option value="2025-2026-2" selected>旧学期</option>
            <option value="2026-2027-1">当前学期</option>
          </select>
        </form>
        """

        let request = try XCTUnwrap(
            SchoolNetworkManager.shared.resolveTimetableRequest(
                from: html,
                preferredSemesterID: "2026-2027-1"
            )
        )
        let body = try XCTUnwrap(request.httpBody.flatMap { String(data: $0, encoding: .utf8) })

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertTrue(body.contains("xnxq01id=2026-2027-1"))
        XCTAssertFalse(body.contains("xnxq01id=2025-2026-2"))
    }

    func testNextSemesterTimetableFixtureUsesExistingParser() throws {
        let html = """
        <html>
          <body>
            <div id="kbcontent_1_1">
              森林生态学<br>
              王老师<br>
              1-18周<br>
              二教205
            </div>
            <div id="kbcontent_3_2">
              数据结构<br>
              李老师<br>
              2-16周<br>
              第二教学楼301
            </div>
          </body>
        </html>
        """

        let courses = try HTMLParser.parseTimetable(html: html)
        let debugDescription = courses.map {
            "\($0.courseName)|\($0.location)|\($0.room)|\($0.weeks.sorted())"
        }.joined(separator: "; ")

        XCTAssertEqual(courses.map(\.courseName).sorted(), ["数据结构", "森林生态学"])
        XCTAssertTrue(courses.contains { $0.location == "二教" && $0.room == "205" && $0.weeks.contains(18) }, debugDescription)
        XCTAssertTrue(courses.contains { $0.location == "二教" && $0.room == "301" && $0.weeks.contains(16) }, debugDescription)
        XCTAssertFalse(courses.contains { $0.weeks.contains(20) })
    }

    func testRecognizedEmptyTimetableParsesAsEmptyCourseList() throws {
        let html = """
        <html><body><div id="kbcontent_1_1"></div></body></html>
        """

        XCTAssertEqual(try HTMLParser.parseTimetable(html: html).count, 0)
    }

    func testRecognizedEmptyGraduateTimetableParsesAsEmptyCourseList() throws {
        XCTAssertEqual(try HTMLParser.parseTimetable(html: #"{"rows":[]}"#).count, 0)
    }

    func testTimetableParserSkipsOutOfRangeContentDayIDs() throws {
        let html = """
        <html>
          <body>
            <div id="kbcontent_0_1">
              越界课程<br>
              王老师<br>
              1-18周<br>
              二教205
            </div>
            <div id="kbcontent_8_1">
              另一个越界课程<br>
              李老师<br>
              1-18周<br>
              二教301
            </div>
            <div id="kbcontent_1_1">
              有效课程<br>
              张老师<br>
              1-2周<br>
              二教101
            </div>
          </body>
        </html>
        """

        let courses = try HTMLParser.parseTimetable(html: html)

        XCTAssertEqual(courses.map(\.courseName), ["有效课程"])
        XCTAssertEqual(courses.first?.dayOfWeek, 1)
        XCTAssertEqual(courses.first?.duration, [1, 2])
    }

    @MainActor
    func testTimetableQueryFormFallsBackToSelectedSemesterWhenPreferredMissing() throws {
        let html = """
        <form action="/jsxsd/xskb/xskb_list.do" method="post">
          <select name="xnxq01id">
            <option value="2025-2026-2" selected>旧学期</option>
            <option value="2025-2026-1">更早学期</option>
          </select>
        </form>
        """

        let request = try XCTUnwrap(
            SchoolNetworkManager.shared.resolveTimetableRequest(
                from: html,
                preferredSemesterID: "2026-2027-1"
            )
        )
        let body = try XCTUnwrap(request.httpBody.flatMap { String(data: $0, encoding: .utf8) })

        XCTAssertTrue(body.contains("xnxq01id=2025-2026-2"))
    }

    @MainActor
    func testCachedTimetableLandingURLRejectsMismatchedSemester() throws {
        let manager = SchoolNetworkManager.shared
        let baseURL = try XCTUnwrap(URL(string: "http://newjwxt.bjfu.edu.cn/jsxsd/xskb/xskb_list.do"))
        let currentURL = manager.timetableURL(baseURL, applyingSemesterID: "2026-2027-1")
        let oldURL = try XCTUnwrap(URL(string: "http://newjwxt.bjfu.edu.cn/jsxsd/xskb/xskb_list.do?xnxq01id=2025-2026-2"))

        XCTAssertTrue(manager.shouldUseCachedTimetableLandingURL(baseURL, preferredSemesterID: "2026-2027-1"))
        XCTAssertTrue(manager.shouldUseCachedTimetableLandingURL(currentURL, preferredSemesterID: "2026-2027-1"))
        XCTAssertFalse(manager.shouldUseCachedTimetableLandingURL(oldURL, preferredSemesterID: "2026-2027-1"))
    }

    @MainActor
    func testTimetableSemesterValidationRejectsExplicitMismatch() throws {
        let html = """
        <html>
          <body>
            <select name="xnxq01id">
              <option value="2025-2026-2" selected>旧学期</option>
              <option value="2026-2027-1">新学期</option>
            </select>
            <div id="kbcontent_1_1">课程</div>
          </body>
        </html>
        """

        XCTAssertThrowsError(
            try SchoolNetworkManager.shared.validateTimetableSemester(
                html: html,
                responseURL: nil,
                expectedSemesterID: "2026-2027-1"
            )
        ) { error in
            guard case SchoolNetworkError.timetableSemesterMismatch(let expected, let actual) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(expected, "2026-2027-1")
            XCTAssertEqual(actual, "2025-2026-2")
        }
    }

    func testTimetableBackgroundPaletteExtractsSoftColorsFromSolidImage() throws {
        let image = makePaletteTestImage(colors: [.systemRed])
        let palette = TimetableBackgroundPaletteExtractor.palette(from: try XCTUnwrap(image.cgImage))

        XCTAssertEqual(palette.lightHexes.count, 7)
        XCTAssertEqual(palette.darkHexes.count, 7)
        XCTAssertNotEqual(palette.lightHexes, TimetableBackgroundPalette.fallbackLightHexes)
        XCTAssertTrue(palette.lightHexes.allSatisfy { $0.hasPrefix("#") && $0.count == 7 })
    }

    func testTimetableBackgroundPaletteUsesMultipleImageColors() throws {
        let image = makePaletteTestImage(colors: [.systemBlue, .systemOrange])
        let bluePalette = TimetableBackgroundPaletteExtractor.palette(from: try XCTUnwrap(makePaletteTestImage(colors: [.systemBlue]).cgImage))
        let mixedPalette = TimetableBackgroundPaletteExtractor.palette(from: try XCTUnwrap(image.cgImage))

        XCTAssertEqual(mixedPalette.lightHexes.count, 7)
        XCTAssertNotEqual(mixedPalette.lightHexes, bluePalette.lightHexes)
    }

    func testTimetableBackgroundPaletteFallsBackForLowSaturationImage() throws {
        let image = makePaletteTestImage(colors: [UIColor(white: 0.5, alpha: 1)])
        let palette = TimetableBackgroundPaletteExtractor.palette(from: try XCTUnwrap(image.cgImage))

        XCTAssertEqual(palette.lightHexes, TimetableBackgroundPalette.fallbackLightHexes)
        XCTAssertEqual(palette.darkHexes, TimetableBackgroundPalette.fallbackDarkHexes)
    }

    func testTimetableBackgroundPaletteFallsBackForOverDarkImage() throws {
        let image = makePaletteTestImage(colors: [UIColor(red: 0.03, green: 0.04, blue: 0.05, alpha: 1)])
        let palette = TimetableBackgroundPaletteExtractor.palette(from: try XCTUnwrap(image.cgImage))

        XCTAssertEqual(palette.lightHexes, TimetableBackgroundPalette.fallbackLightHexes)
        XCTAssertEqual(palette.darkHexes, TimetableBackgroundPalette.fallbackDarkHexes)
    }

    func testCourseColorHashIndexStaysStable() {
        XCTAssertEqual(AppTheme.stableCourseColorIndex(for: "Data StructuresAlice", colorCount: 7), 3)
        XCTAssertEqual(AppTheme.stableCourseColorIndex(for: "森林生态王老师", colorCount: 7), 0)
        XCTAssertEqual(AppTheme.stableCourseColorIndex(for: "", colorCount: 7), 0)
        XCTAssertEqual(AppTheme.stableCourseColorIndex(for: "A", colorCount: 0), 0)
    }

    func testFloatingChromeDarkSelectionBackgroundDoesNotUseNearWhiteAccentSoft() {
        let color = UIColor(AppTheme.floatingChromeSelectedBackground(for: .green, colorScheme: .dark))
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        XCTAssertTrue(color.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        XCTAssertFalse(red > 0.88 && green > 0.88 && blue > 0.88)
        XCTAssertLessThanOrEqual(alpha, 0.35)
    }

    func testSchoolReauthenticationRecognizesSessionFailuresOnly() {
        XCTAssertTrue(SchoolReauthentication.requiresReauthentication(SchoolNetworkError.sessionExpired))
        XCTAssertTrue(SchoolReauthentication.requiresReauthentication(URLError(.userAuthenticationRequired)))
        XCTAssertFalse(SchoolReauthentication.requiresReauthentication(SchoolNetworkError.campusNetworkRequired))
        XCTAssertFalse(SchoolReauthentication.requiresReauthentication(SchoolNetworkError.featureUnavailable("未开放")))

        XCTAssertTrue(SchoolReauthentication.shouldPromptForUserInitiatedAccess(SchoolNetworkError.sessionExpired))
        XCTAssertTrue(SchoolReauthentication.shouldPromptForUserInitiatedAccess(SchoolNetworkError.campusNetworkRequired))
        XCTAssertFalse(SchoolReauthentication.shouldPromptForUserInitiatedAccess(SchoolNetworkError.featureUnavailable("未开放")))
    }

    @MainActor
    func testSchoolSessionPreflightImmediatelyRequiresLoginWithoutLocalSession() async {
        let manager = SchoolNetworkManager.shared
        manager.clearSession()

        let result = await manager.preflightAuthenticatedSession()

        XCTAssertEqual(result, .requiresReauthentication)
    }

    @MainActor
    func testLegacyFollowThemeIconPreferenceMigratesToConcretePreset() {
        XCTAssertEqual(LeafyAppIconAppearancePreference.allCases, [.green, .tiffanyBlue, .candyPink])
        XCTAssertEqual(
            LeafyAppIconManager.migratedIconPreference(
                rawValue: "followTheme",
                themeSnapshot: LeafyWidgetThemeSnapshot(
                    preferenceRaw: LeafyThemeColorPreferenceRaw.tiffanyBlue.rawValue,
                    customColorHex: LeafyThemeColorPreferenceRaw.defaultCustomColorHex
                )
            ),
            .tiffanyBlue
        )
        XCTAssertEqual(
            LeafyAppIconManager.migratedIconPreference(
                rawValue: "followTheme",
                themeSnapshot: LeafyWidgetThemeSnapshot(
                    preferenceRaw: LeafyThemeColorPreferenceRaw.custom.rawValue,
                    customColorHex: "#123456"
                )
            ),
            .green
        )
    }

    @MainActor
    func testMultipleResumeRecordsReplaceAndDeleteIndependently() throws {
        try? CareerDocumentFileStore.deleteAllFiles()
        defer { try? CareerDocumentFileStore.deleteAllFiles() }

        let schema = Schema([CareerResumeDocument.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let sourceDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LeafyResumeSources-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sourceDirectory) }

        let productSource = sourceDirectory.appendingPathComponent("product.pdf")
        let designSource = sourceDirectory.appendingPathComponent("design.pdf")
        let replacementSource = sourceDirectory.appendingPathComponent("product-v2.pdf")
        try Data("product-v1".utf8).write(to: productSource)
        try Data("design-v1".utf8).write(to: designSource)
        try Data("product-v2".utf8).write(to: replacementSource)

        let productFile = try CareerDocumentFileStore.importFile(from: productSource)
        let designFile = try CareerDocumentFileStore.importFile(from: designSource)
        let productResume = CareerResumeDocument(
            title: "产品实习版",
            note: "面向产品岗位",
            originalFilename: productSource.lastPathComponent,
            localFilename: productFile.localFilename,
            contentTypeIdentifier: productFile.contentTypeIdentifier
        )
        let designResume = CareerResumeDocument(
            title: "设计实习版",
            note: "面向设计岗位",
            originalFilename: designSource.lastPathComponent,
            localFilename: designFile.localFilename,
            contentTypeIdentifier: designFile.contentTypeIdentifier
        )
        context.insert(productResume)
        context.insert(designResume)
        try context.save()

        let previousFilename = productResume.localFilename
        let replacementFile = try CareerDocumentFileStore.importFile(from: replacementSource)
        productResume.originalFilename = replacementSource.lastPathComponent
        productResume.localFilename = replacementFile.localFilename
        productResume.contentTypeIdentifier = replacementFile.contentTypeIdentifier
        try context.save()
        try CareerDocumentFileStore.deleteFile(named: previousFilename)

        XCTAssertEqual(productResume.title, "产品实习版")
        XCTAssertEqual(productResume.note, "面向产品岗位")
        XCTAssertNotNil(CareerDocumentFileStore.fileURL(for: productResume))
        XCTAssertNotNil(CareerDocumentFileStore.fileURL(for: designResume))

        try CareerDocumentFileStore.deleteFile(named: designResume.localFilename)
        context.delete(designResume)
        try context.save()

        let remaining = try context.fetch(FetchDescriptor<CareerResumeDocument>())
        XCTAssertEqual(remaining.map(\.title), ["产品实习版"])

        try CareerDocumentFileStore.deleteAllFiles()
        XCTAssertNil(CareerDocumentFileStore.fileURL(for: productResume))
    }

    @MainActor
    func testGraduateLoginFormEncodingEscapesPlusInEncryptedPassword() throws {
        let payload = #"{"UserId":"123","Password":"a+b/c==","VeriCode":"0000","url":"","city":""}"#
        let body = SchoolNetworkManager.shared.formURLEncodedBody(queryItems: [
            URLQueryItem(name: "json", value: payload)
        ])
        let bodyString = try XCTUnwrap(String(data: body, encoding: .utf8))

        XCTAssertTrue(bodyString.contains("a%2Bb/c%3D%3D"))
        XCTAssertFalse(bodyString.contains("a+b/c"))
    }

    @MainActor
    func testGraduateLoginResponseAcceptsSuccessfulRedirect() throws {
        let redirect = try SchoolNetworkManager.shared.parseGraduateLoginRedirect(
            from: #"{"jg":"1","url":"student/default"}"#
        )

        XCTAssertEqual(redirect, "student/default")
    }

    @MainActor
    func testGraduateLoginResponseUsesServerFailureMessage() {
        XCTAssertThrowsError(
            try SchoolNetworkManager.shared.parseGraduateLoginRedirect(
                from: #"{"jg":"0","msg":"验证码错误"}"#
            )
        ) { error in
            XCTAssertEqual(error.localizedDescription, "验证码错误")
        }
    }

    @MainActor
    func testGraduateLoginResponseRejectsEmptyOrInvalidBodies() {
        XCTAssertThrowsError(
            try SchoolNetworkManager.shared.parseGraduateLoginRedirect(from: "")
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("研究生系统登录响应无法解密"))
        }

        XCTAssertThrowsError(
            try SchoolNetworkManager.shared.parseGraduateLoginRedirect(from: "not json")
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("研究生系统登录响应格式异常"))
        }
    }

    func testExamParserAcceptsBackendShape() throws {
        let html = """
        <table id="dataList">
          <tr><th>序号</th><th>开课学期</th><th>课程编号</th><th>课程名称</th><th>考试时间</th><th>考试地点</th></tr>
          <tr><td>1</td><td>2025-2026-2</td><td>DS-001</td><td>数据结构</td><td>2026-06-20 09:00~11:00</td><td>二教 205</td></tr>
        </table>
        """

        let exams = try HTMLParser.parseExams(html: html)

        XCTAssertEqual(exams, [
            ExamArrangement(id: 1, courseID: "DS-001", name: "数据结构", date: "2026-06-20", start: "09:00", end: "11:00", location: "二教 205")
        ])
    }

    func testExamParserAcceptsSplitDateAndTimeColumns() throws {
        let html = """
        <table id="dataList">
          <tr><th>序号</th><th>课程代码</th><th>课程名称</th><th>考试日期</th><th>考试时段</th><th>教室</th></tr>
          <tr><td>2</td><td>MATH-001</td><td>高等数学 A</td><td>2026/06/21</td><td>14:00-16:00</td><td>主楼 112</td></tr>
        </table>
        """

        let exams = try HTMLParser.parseExams(html: html)

        XCTAssertEqual(exams, [
            ExamArrangement(id: 2, courseID: "MATH-001", name: "高等数学 A", date: "2026-06-21", start: "14:00", end: "16:00", location: "主楼 112")
        ])
    }

    func testWidgetSignatureIgnoresGeneratedAtOnlyChanges() {
        let archiveA = makeWidgetSignatureArchive(generatedAt: Date(timeIntervalSince1970: 1))
        var archiveB = archiveA
        archiveB.generatedAt = Date(timeIntervalSince1970: 2)
        archiveB.snapshots[0].snapshot.generatedAt = Date(timeIntervalSince1970: 2)

        XCTAssertEqual(WidgetSnapshotSignature(archive: archiveA), WidgetSnapshotSignature(archive: archiveB))
    }

    func testWidgetSignatureTracksVisibleSnapshotTextChanges() {
        let baseline = makeWidgetSignatureArchive()

        var changedDisplayDate = baseline
        changedDisplayDate.snapshots[0].snapshot.displayDate = "Tomorrow"
        XCTAssertNotEqual(WidgetSnapshotSignature(archive: baseline), WidgetSnapshotSignature(archive: changedDisplayDate))

        var changedWeek = baseline
        changedWeek.snapshots[0].snapshot.weekText = "Week 2"
        XCTAssertNotEqual(WidgetSnapshotSignature(archive: baseline), WidgetSnapshotSignature(archive: changedWeek))

        var changedDay = baseline
        changedDay.snapshots[0].snapshot.dayText = "Tue"
        XCTAssertNotEqual(WidgetSnapshotSignature(archive: baseline), WidgetSnapshotSignature(archive: changedDay))

        var changedExam = baseline
        changedExam.snapshots[0].snapshot.nextExamText = "考试：高数 · 6月1日"
        XCTAssertNotEqual(WidgetSnapshotSignature(archive: baseline), WidgetSnapshotSignature(archive: changedExam))
    }

    func testWidgetSignatureTracksVisibleCourseChanges() {
        let baseline = makeWidgetSignatureArchive()

        var changedTitle = baseline
        changedTitle.snapshots[0].snapshot.courses[0].title = "B"
        XCTAssertNotEqual(WidgetSnapshotSignature(archive: baseline), WidgetSnapshotSignature(archive: changedTitle))

        var changedTime = baseline
        changedTime.snapshots[0].snapshot.courses[0].timeText = "09:00"
        XCTAssertNotEqual(WidgetSnapshotSignature(archive: baseline), WidgetSnapshotSignature(archive: changedTime))

        var changedLocation = baseline
        changedLocation.snapshots[0].snapshot.courses[0].locationText = "202"
        XCTAssertNotEqual(WidgetSnapshotSignature(archive: baseline), WidgetSnapshotSignature(archive: changedLocation))

        var changedNote = baseline
        changedNote.snapshots[0].snapshot.courses[0].noteText = "带教材"
        XCTAssertNotEqual(WidgetSnapshotSignature(archive: baseline), WidgetSnapshotSignature(archive: changedNote))

        var changedReminder = baseline
        changedReminder.snapshots[0].snapshot.courses[0].reminderText = "提前 10 分钟"
        XCTAssertNotEqual(WidgetSnapshotSignature(archive: baseline), WidgetSnapshotSignature(archive: changedReminder))
    }

    @MainActor
    func testWidgetSnapshotKeepsMoreThanFourCourses() throws {
        let date = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 8)))
        let courses = (1...5).map { index in
            Course(
                courseName: "Course \(index)",
                teacher: "T",
                room: "\(index)01",
                location: "Building",
                dayOfWeek: 1,
                weeks: [1],
                duration: [index]
            )
        }

        let archive = LeafyWidgetSnapshotBuilder.makeArchiveForTesting(
            courses: courses,
            isAuthenticated: true,
            date: date
        )
        let snapshot = try XCTUnwrap(archive.snapshot(for: 0))

        XCTAssertEqual(snapshot.status, .ready)
        XCTAssertEqual(snapshot.courses.count, 5)
        XCTAssertEqual(snapshot.courses.map(\.title), ["Course 1", "Course 2", "Course 3", "Course 4", "Course 5"])
    }

    @MainActor
    func testWidgetSnapshotUsesOccurrenceNoteBeforeCourseNote() throws {
        let firstWeekDate = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 8)))
        let secondWeekDate = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 16, hour: 8)))
        let course = Course(
            courseName: "体育",
            teacher: "T",
            room: "操场",
            location: "",
            dayOfWeek: 1,
            weeks: [1, 2],
            duration: [1]
        )
        let courseNote = CourseNote(courseKey: course.stableCourseKey, text: "带衣服")
        let occurrenceNote = CourseOccurrenceNote(
            courseKey: course.stableCourseKey,
            occurrenceKey: course.occurrenceKey(week: 1),
            week: 1,
            dayOfWeek: 1,
            text: "带球鞋"
        )

        let firstWeekArchive = LeafyWidgetSnapshotBuilder.makeArchiveForTesting(
            courses: [course],
            notes: [courseNote],
            occurrenceNotes: [occurrenceNote],
            isAuthenticated: true,
            date: firstWeekDate
        )
        let secondWeekArchive = LeafyWidgetSnapshotBuilder.makeArchiveForTesting(
            courses: [course],
            notes: [courseNote],
            occurrenceNotes: [occurrenceNote],
            isAuthenticated: true,
            date: secondWeekDate
        )

        XCTAssertEqual(try XCTUnwrap(firstWeekArchive.snapshot(for: 0)).courses.first?.noteText, "带球鞋")
        XCTAssertEqual(try XCTUnwrap(secondWeekArchive.snapshot(for: 0)).courses.first?.noteText, "带衣服")
    }

    @MainActor
    func testCalendarExportBuilderBuildsRangeAndLeafyURL() throws {
        let referenceDate = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 16, hour: 8)))
        let course = Course(
            courseName: "森林生态学",
            teacher: "陈老师",
            room: "101",
            location: "二教",
            dayOfWeek: 1,
            weeks: [1, 2, 3],
            duration: [1, 2]
        )
        let courseNote = CourseNote(courseKey: course.stableCourseKey, text: "带教材")
        let occurrenceNote = CourseOccurrenceNote(
            courseKey: course.stableCourseKey,
            occurrenceKey: course.occurrenceKey(week: 2),
            week: 2,
            dayOfWeek: 1,
            text: "交作业"
        )
        let reminder = TimetableCellReminder(
            week: 2,
            dayOfWeek: 1,
            period: 3,
            endPeriod: 4,
            title: "预习植物分类",
            location: "图书馆二层",
            note: "带笔记本",
            minutesBefore: 20
        )
        let exam = ExamArrangement(
            id: 7,
            courseID: "FOREST-001",
            name: "森林生态学",
            date: "2026-03-16",
            start: "09:00",
            end: "10:30",
            location: "二教 201"
        )

        let currentWeekDrafts = TimetableCalendarExportBuilder.drafts(
            courses: [course],
            courseNotes: [courseNote],
            occurrenceNotes: [occurrenceNote],
            cellReminders: [reminder],
            exams: [exam],
            range: .currentWeek,
            currentWeek: 2,
            referenceDate: referenceDate,
            totalWeeks: 3
        )
        let remainingDrafts = TimetableCalendarExportBuilder.drafts(
            courses: [course],
            courseNotes: [courseNote],
            occurrenceNotes: [occurrenceNote],
            range: .remainingSemester,
            currentWeek: 1,
            referenceDate: referenceDate,
            totalWeeks: 3
        )
        let fullDrafts = TimetableCalendarExportBuilder.drafts(
            courses: [course],
            courseNotes: [courseNote],
            occurrenceNotes: [occurrenceNote],
            range: .fullSemester,
            currentWeek: 2,
            referenceDate: referenceDate,
            totalWeeks: 3
        )
        let customSingleWeekDrafts = TimetableCalendarExportBuilder.drafts(
            courses: [course],
            courseNotes: [courseNote],
            occurrenceNotes: [occurrenceNote],
            range: .customWeeks,
            currentWeek: 1,
            referenceDate: referenceDate,
            totalWeeks: 3,
            customWeeks: 3...3
        )
        let customRangeDrafts = TimetableCalendarExportBuilder.drafts(
            courses: [course],
            courseNotes: [courseNote],
            occurrenceNotes: [occurrenceNote],
            cellReminders: [reminder],
            exams: [exam],
            range: .customWeeks,
            currentWeek: 1,
            referenceDate: referenceDate,
            totalWeeks: 3,
            customWeeks: 1...2
        )

        XCTAssertEqual(currentWeekDrafts.map(\.occurrenceKey), [
            course.occurrenceKey(week: 2),
            "exam:7",
            "cellReminder:\(reminder.cellKey)"
        ])
        XCTAssertEqual(remainingDrafts.map(\.occurrenceKey), [course.occurrenceKey(week: 2), course.occurrenceKey(week: 3)])
        XCTAssertEqual(fullDrafts.count, 3)
        XCTAssertEqual(customSingleWeekDrafts.map(\.occurrenceKey), [course.occurrenceKey(week: 3)])
        XCTAssertEqual(customRangeDrafts.map(\.occurrenceKey), [
            course.occurrenceKey(week: 1),
            course.occurrenceKey(week: 2),
            "exam:7",
            "cellReminder:\(reminder.cellKey)"
        ])
        XCTAssertEqual(TimetableCalendarExportBuilder.weekRange(
            for: .customWeeks,
            currentWeek: 1,
            referenceDate: referenceDate,
            totalWeeks: 3,
            customWeeks: 0...8
        ), 1...3)

        let draft = try XCTUnwrap(currentWeekDrafts.first)
        XCTAssertEqual(draft.title, "森林生态学")
        XCTAssertEqual(draft.location, "二教 101")
        XCTAssertTrue(draft.notes.contains("教师：陈老师"))
        XCTAssertTrue(draft.notes.contains("节次：第 1-2 节"))
        XCTAssertTrue(draft.notes.contains("周次：第 2 周"))
        XCTAssertTrue(draft.notes.contains("备注：交作业"))
        XCTAssertEqual(TimetableCalendarExportBuilder.occurrenceKey(from: draft.url), draft.occurrenceKey)

        let reminderDraft = try XCTUnwrap(currentWeekDrafts.first { $0.occurrenceKey == "cellReminder:\(reminder.cellKey)" })
        XCTAssertEqual(reminderDraft.title, "预习植物分类")
        XCTAssertEqual(reminderDraft.location, "图书馆二层")
        XCTAssertTrue(reminderDraft.notes.contains("类型：日程"))
        XCTAssertTrue(reminderDraft.notes.contains("地点：图书馆二层"))
        XCTAssertTrue(reminderDraft.notes.contains("节次：第 3-4 节"))
        XCTAssertTrue(reminderDraft.notes.contains("备注：带笔记本"))
        XCTAssertTrue(reminderDraft.notes.contains("本地通知：提前 20 分钟"))
        XCTAssertEqual(TimetableCalendarExportBuilder.occurrenceKey(from: reminderDraft.url), reminderDraft.occurrenceKey)

        let examDraft = try XCTUnwrap(currentWeekDrafts.first { $0.occurrenceKey == "exam:7" })
        XCTAssertEqual(examDraft.title, "考试：森林生态学")
        XCTAssertEqual(examDraft.location, "二教 201")
        XCTAssertTrue(examDraft.notes.contains("类型：考试"))
        XCTAssertTrue(examDraft.notes.contains("课程编号：FOREST-001"))
        XCTAssertEqual(TimetableCalendarExportBuilder.occurrenceKey(from: examDraft.url), examDraft.occurrenceKey)

        let currentWeekInterval = try XCTUnwrap(TimetableCalendarExportBuilder.exportInterval(
            for: .currentWeek,
            currentWeek: 2,
            referenceDate: referenceDate,
            totalWeeks: 3
        ))
        let remainingInterval = try XCTUnwrap(TimetableCalendarExportBuilder.exportInterval(
            for: .remainingSemester,
            currentWeek: 1,
            referenceDate: referenceDate,
            totalWeeks: 3
        ))
        let fullInterval = try XCTUnwrap(TimetableCalendarExportBuilder.exportInterval(
            for: .fullSemester,
            currentWeek: 2,
            referenceDate: referenceDate,
            totalWeeks: 3
        ))
        let calendar = Calendar.current
        let semesterStart = calendar.startOfDay(for: SemesterConfig.startOfSemesterDate)
        XCTAssertEqual(currentWeekInterval.start, try XCTUnwrap(calendar.date(byAdding: .day, value: 7, to: semesterStart)))
        XCTAssertEqual(currentWeekInterval.end, try XCTUnwrap(calendar.date(byAdding: .day, value: 14, to: semesterStart)))
        XCTAssertEqual(remainingInterval.start, currentWeekInterval.start)
        XCTAssertEqual(remainingInterval.end, try XCTUnwrap(calendar.date(byAdding: .day, value: 21, to: semesterStart)))
        XCTAssertEqual(fullInterval.start, semesterStart)
        XCTAssertEqual(fullInterval.end, remainingInterval.end)
    }

    @MainActor
    func testCalendarExportBuilderBuildsExamAndReminderDraftsWithoutCourses() throws {
        let referenceDate = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 16, hour: 8)))
        let reminder = TimetableCellReminder(week: 2, dayOfWeek: 1, period: 3, title: "社团面试")
        let exam = ExamArrangement(
            id: 8,
            courseID: "MATH-001",
            name: "高等数学",
            date: "2026-03-16",
            start: "14:00",
            end: "16:00",
            location: "主楼 112"
        )

        let drafts = TimetableCalendarExportBuilder.drafts(
            courses: [],
            courseNotes: [],
            occurrenceNotes: [],
            cellReminders: [reminder],
            exams: [exam],
            range: .currentWeek,
            currentWeek: 2,
            referenceDate: referenceDate,
            totalWeeks: 3
        )

        XCTAssertEqual(drafts.map(\.occurrenceKey), [
            "cellReminder:\(reminder.cellKey)",
            "exam:8"
        ])
        XCTAssertEqual(drafts.map(\.title), ["社团面试", "考试：高等数学"])
    }

    func testImageProcessorDownsamplesUpload() async throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 40)).image { context in
            UIColor.systemGreen.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 80, height: 40))
        }
        let data = try XCTUnwrap(image.pngData())

        let result = try await CommunityImageProcessor.shared.compressedJPEG(
            from: data,
            maxPixelDimension: 32,
            maxBytes: 80 * 1024
        )

        XCTAssertLessThanOrEqual(result.upload.data.count, 80 * 1024)
        XCTAssertLessThanOrEqual(result.upload.width ?? 0, 32)
        XCTAssertLessThanOrEqual(result.upload.height ?? 0, 32)
        XCTAssertNotNil(UIImage(data: result.previewData))
    }

    @MainActor
    func testCommunityFeedInitialLoadFetchesAndCachesPosts() async {
        let post = makeCommunityPost(title: "初始帖子")
        let repository = FakeCommunityRepository(postResponses: [[post]])
        let cache = FakeCommunityFeedCache()
        let viewModel = CommunityFeedViewModel(repository: repository, cache: cache)

        await viewModel.load()

        XCTAssertEqual(viewModel.posts, [post])
        XCTAssertEqual(cache.savedPostSnapshots.last, [post])
    }

    @MainActor
    func testCommunityFeedCacheFirstKeepsCachedPostsDuringRefresh() async {
        let cachedPost = makeCommunityPost(title: "缓存帖子")
        let freshPost = makeCommunityPost(title: "最新帖子")
        let repository = FakeCommunityRepository()
        let cache = FakeCommunityFeedCache(loadedPosts: [cachedPost])
        let viewModel = CommunityFeedViewModel(repository: repository, cache: cache)

        await repository.suspendFetches()
        let loadTask = Task {
            await viewModel.load()
        }
        await repository.waitForSuspendedFetch()

        XCTAssertEqual(viewModel.posts, [cachedPost])

        await repository.resumeSuspendedFetch(with: [freshPost])
        await loadTask.value

        XCTAssertEqual(viewModel.posts, [freshPost])
        XCTAssertEqual(cache.savedPostSnapshots.last, [freshPost])
    }

    @MainActor
    func testCommunityFeedRefreshFailurePreservesExistingPosts() async {
        let post = makeCommunityPost(title: "保留帖子")
        let repository = FakeCommunityRepository(postResponses: [[post]])
        let cache = FakeCommunityFeedCache()
        let viewModel = CommunityFeedViewModel(repository: repository, cache: cache)

        await viewModel.load()
        await repository.setFetchError(.failure("刷新失败"))
        await viewModel.load(mode: .refresh)

        XCTAssertEqual(viewModel.posts, [post])
        XCTAssertEqual(viewModel.errorMessage, "刷新失败")
    }

    @MainActor
    func testCommunityFeedInitialFailureSurfacesRecoverableError() async {
        let repository = FakeCommunityRepository()
        let viewModel = CommunityFeedViewModel(repository: repository, cache: FakeCommunityFeedCache())

        await repository.setFetchError(.failure("初次加载失败"))
        await viewModel.load()

        XCTAssertTrue(viewModel.posts.isEmpty)
        XCTAssertTrue(viewModel.items.isEmpty)
        XCTAssertEqual(viewModel.errorMessage, "初次加载失败")
    }

    func testCommunityFeedCacheDropsCorruptPayload() {
        let query = CommunityFeedQuery(search: "corrupt-\(UUID().uuidString)")
        let key = CommunityFeedCache.cacheKey(for: query)
        UserDefaults.standard.set(Data("not-json".utf8), forKey: key)
        defer {
            UserDefaults.standard.removeObject(forKey: key)
        }

        XCTAssertEqual(CommunityFeedCache().load(query: query), [])
    }

    @MainActor
    func testCommunityFeedMutationsUpdatePostsAndCache() async {
        let authorID = UUID()
        let firstPin = makeCommunityPostPin(postID: UUID(), priority: 7)
        let firstPost = makeCommunityPost(id: firstPin.postID, authorID: authorID, title: "第一条", pin: firstPin)
        let secondPost = makeCommunityPost(title: "第二条")
        let likedFirstPost = makeCommunityPost(
            id: firstPost.id,
            authorID: authorID,
            title: "第一条",
            likeCount: 1,
            viewerHasLiked: true,
            pin: firstPin
        )
        let repository = FakeCommunityRepository(postResponses: [[firstPost, secondPost]])
        let cache = FakeCommunityFeedCache()
        let viewModel = CommunityFeedViewModel(repository: repository, cache: cache)

        await viewModel.load()
        await repository.setLikeResponse(likedFirstPost, for: firstPost.id)

        let likeError = await viewModel.toggleLike(postID: firstPost.id)
        XCTAssertNil(likeError)
        XCTAssertEqual(viewModel.posts, [likedFirstPost, secondPost])
        XCTAssertEqual(cache.savedPostSnapshots.last, [likedFirstPost, secondPost])

        let deleteError = await viewModel.delete(post: secondPost)
        XCTAssertNil(deleteError)
        XCTAssertEqual(viewModel.posts, [likedFirstPost])
        XCTAssertEqual(cache.savedPostSnapshots.last, [likedFirstPost])

        let blockError = await viewModel.blockAuthor(of: likedFirstPost)
        XCTAssertNil(blockError)
        XCTAssertTrue(viewModel.posts.isEmpty)
        XCTAssertEqual(cache.savedPostSnapshots.last, [])
    }

    @MainActor
    func testCommunityFeedFavoriteMutationUpdatesPostsAndCache() async {
        let pin = makeCommunityPostPin(postID: UUID(), priority: 3)
        let post = makeCommunityPost(id: pin.postID, title: "待收藏", pin: pin)
        let favoritedPost = makeCommunityPost(
            id: post.id,
            authorID: post.authorID,
            title: "待收藏",
            viewerHasFavorited: true,
            pin: pin
        )
        let repository = FakeCommunityRepository(postResponses: [[post]])
        let cache = FakeCommunityFeedCache()
        let viewModel = CommunityFeedViewModel(repository: repository, cache: cache)

        await viewModel.load()
        await repository.setFavoriteResponse(favoritedPost, for: post.id)

        let favoriteError = await viewModel.toggleFavorite(postID: post.id)
        XCTAssertNil(favoriteError)
        XCTAssertEqual(viewModel.posts, [favoritedPost])
        XCTAssertEqual(viewModel.posts.first?.pin, pin)
        XCTAssertEqual(cache.savedPostSnapshots.last, [favoritedPost])
    }

    @MainActor
    func testCommunityFeedCacheIsScopedByQuery() async {
        let cachedDefaultPost = makeCommunityPost(title: "默认缓存")
        let categoryPost = makeCommunityPost(title: "分类帖子", category: "问答互助")
        let query = CommunityFeedQuery(category: "问答互助")
        let repository = FakeCommunityRepository(postResponses: [[categoryPost]])
        let cache = FakeCommunityFeedCache(loadedPosts: [cachedDefaultPost])
        let viewModel = CommunityFeedViewModel(repository: repository, cache: cache)

        await viewModel.load(query: query)

        XCTAssertEqual(viewModel.posts, [categoryPost])
        XCTAssertEqual(cache.savedPostSnapshots.last, [categoryPost])
    }

    @MainActor
    func testCommunityFeedDefaultQueryIncludesPublishedPollItems() async {
        let post = makeCommunityPost(title: "普通帖子", createdAt: "2026-05-14T00:00:00Z")
        let publishedPoll = makeCommunityPoll(question: "大家想在哪里自习？", createdAt: "2026-05-15T00:00:00Z")
        let pendingPoll = makeCommunityPoll(
            question: "待审核投票",
            status: "pending_review",
            createdAt: "2026-05-16T00:00:00Z"
        )
        let repository = FakeCommunityRepository(
            postResponses: [[post]],
            pollResponses: [[pendingPoll, publishedPoll]]
        )
        let viewModel = CommunityFeedViewModel(repository: repository, cache: FakeCommunityFeedCache())

        await viewModel.load()

        XCTAssertEqual(viewModel.posts, [post])
        XCTAssertEqual(viewModel.items, [.poll(publishedPoll), .post(post)])
    }

    @MainActor
    func testCommunityFeedKeepsPublishedPollWhileDeletionIsPending() async {
        let poll = makeCommunityPoll(
            question: "删除审核中仍展示吗？",
            deletionStatus: "pending"
        )
        let repository = FakeCommunityRepository(postResponses: [[]], pollResponses: [[poll]])
        let viewModel = CommunityFeedViewModel(repository: repository, cache: FakeCommunityFeedCache())

        await viewModel.load()

        XCTAssertEqual(viewModel.items, [.poll(poll)])
    }

    @MainActor
    func testCommunityFeedCategoryQueryDoesNotFetchPolls() async {
        let post = makeCommunityPost(title: "分类帖子", category: "问答互助")
        let poll = makeCommunityPoll(question: "不应混入分类")
        let repository = FakeCommunityRepository(postResponses: [[post]], pollResponses: [[poll]])
        let viewModel = CommunityFeedViewModel(repository: repository, cache: FakeCommunityFeedCache())

        await viewModel.load(query: CommunityFeedQuery(category: "问答互助"))

        let fetchedPollLimits = await repository.fetchedPollLimits()
        XCTAssertEqual(viewModel.items, [.post(post)])
        XCTAssertEqual(fetchedPollLimits, [])
    }

    @MainActor
    func testCommunityFeedPollVoteUpdatesFeedItem() async {
        let pollID = UUID()
        let optionID = UUID()
        let initialOption = makeCommunityPollOption(id: optionID, pollID: pollID, text: "图书馆")
        let updatedOption = makeCommunityPollOption(id: optionID, pollID: pollID, text: "图书馆", voteCount: 1)
        let poll = makeCommunityPoll(id: pollID, question: "今天去哪自习？", options: [initialOption])
        let updatedPoll = makeCommunityPoll(
            id: pollID,
            question: "今天去哪自习？",
            totalVoteCount: 1,
            viewerOptionID: optionID,
            options: [updatedOption]
        )
        let repository = FakeCommunityRepository(postResponses: [[]], pollResponses: [[poll]])
        await repository.setVotePollResponse(updatedPoll, for: pollID)
        let viewModel = CommunityFeedViewModel(repository: repository, cache: FakeCommunityFeedCache())

        await viewModel.load()
        let result = await viewModel.votePoll(pollID: pollID, optionID: optionID)

        XCTAssertEqual(result, updatedPoll)
        XCTAssertEqual(viewModel.items, [.poll(updatedPoll)])
    }

    func testCommunityFeedHotQueryHasSeparateCacheKeyAndFixedLimit() {
        let hotQuery = CommunityFeedQuery(category: "问答互助", search: "图书馆", limit: 50, mode: .hot(days: 7))

        XCTAssertNil(hotQuery.category)
        XCTAssertNil(hotQuery.search)
        XCTAssertEqual(hotQuery.limit, 10)
        XCTAssertNotEqual(hotQuery.cacheKey, CommunityFeedQuery.default.cacheKey)
        XCTAssertNotEqual(hotQuery.cacheKey, CommunityFeedQuery(category: "问答互助").cacheKey)
        XCTAssertNotEqual(hotQuery.cacheKey, CommunityFeedQuery(search: "图书馆").cacheKey)
    }

    @MainActor
    func testCommunityFeedPollFilterSkipsPostsAndOnlyReturnsPublishedPolls() async {
        let publishedPoll = makeCommunityPoll(question: "去哪里自习？")
        let pendingPoll = makeCommunityPoll(question: "待审核", status: "pending_review")
        let repository = FakeCommunityRepository(
            postResponses: [[makeCommunityPost(title: "不应请求")]],
            pollResponses: [[pendingPoll, publishedPoll]]
        )
        let viewModel = CommunityFeedViewModel(repository: repository, cache: FakeCommunityFeedCache())
        let query = CommunityFeedQuery(contentFilter: .polls)

        await viewModel.load(query: query)

        let fetchedPostQueries = await repository.fetchedPostQueries()
        XCTAssertEqual(fetchedPostQueries, [])
        XCTAssertEqual(viewModel.posts, [])
        XCTAssertEqual(viewModel.items, [.poll(publishedPoll)])
        XCTAssertFalse(viewModel.hasMoreItems)
        XCTAssertNotEqual(query.cacheKey, CommunityFeedQuery.default.cacheKey)
    }

    func testCommunityFeedOrderingPrioritizesPinnedPosts() {
        let lowID = UUID()
        let highID = UUID()
        let normalPost = makeCommunityPost(title: "普通", category: "学习交流")
        let lowPinnedPost = makeCommunityPost(
            id: lowID,
            title: "低优先级置顶",
            category: "学习交流",
            pin: makeCommunityPostPin(postID: lowID, priority: 1, startsAt: "2026-05-15T00:00:00Z")
        )
        let highPinnedPost = makeCommunityPost(
            id: highID,
            title: "高优先级置顶",
            category: "学习交流",
            pin: makeCommunityPostPin(postID: highID, priority: 10, startsAt: "2026-05-14T00:00:00Z")
        )

        let orderedPosts = CommunityFeedOrdering.ordered(
            [normalPost, lowPinnedPost, highPinnedPost],
            matching: .default
        )

        XCTAssertEqual(orderedPosts.map(\.id), [highPinnedPost.id, lowPinnedPost.id, normalPost.id])
    }

    func testCommunityFeedOrderingFiltersCategoryAndSearch() {
        let globalID = UUID()
        let matchingPost = makeCommunityPost(
            id: globalID,
            title: "图书馆座位提醒",
            category: "问答互助",
            pin: makeCommunityPostPin(postID: globalID, priority: 5)
        )
        let unrelatedPinnedID = UUID()
        let unrelatedPinnedPost = makeCommunityPost(
            id: unrelatedPinnedID,
            title: "食堂窗口推荐",
            category: "校园生活",
            pin: makeCommunityPostPin(postID: unrelatedPinnedID, priority: 9)
        )

        let orderedPosts = CommunityFeedOrdering.ordered(
            [unrelatedPinnedPost, matchingPost],
            matching: CommunityFeedQuery(category: "问答互助", search: "图书馆")
        )

        XCTAssertEqual(orderedPosts, [matchingPost])
    }

    func testCommunityFeedOrderingHotFiltersWindowAndSortsByScore() {
        let now = ISO8601DateFormatter().date(from: "2026-05-27T12:00:00Z")!
        let highScorePost = makeCommunityPost(
            title: "高分",
            commentCount: 3,
            likeCount: 2,
            status: "published",
            createdAt: "2026-05-26T00:00:00Z"
        )
        let tieNewerPost = makeCommunityPost(
            title: "同分较新",
            commentCount: 1,
            likeCount: 2,
            status: "published",
            createdAt: "2026-05-27T00:00:00Z"
        )
        let tieOlderPost = makeCommunityPost(
            title: "同分较旧",
            commentCount: 1,
            likeCount: 2,
            status: "published",
            createdAt: "2026-05-25T00:00:00Z"
        )
        let oldPost = makeCommunityPost(
            title: "过期",
            commentCount: 100,
            likeCount: 100,
            status: "published",
            createdAt: "2026-05-10T00:00:00Z"
        )
        let hiddenPost = makeCommunityPost(
            title: "不可见",
            commentCount: 100,
            likeCount: 100,
            status: "hidden",
            createdAt: "2026-05-27T00:00:00Z"
        )

        let orderedPosts = CommunityFeedOrdering.hot(
            [tieOlderPost, oldPost, hiddenPost, tieNewerPost, highScorePost],
            days: 7,
            limit: 10,
            now: now
        )

        XCTAssertEqual(orderedPosts.map(\.id), [highScorePost.id, tieNewerPost.id, tieOlderPost.id])
    }

    func testCommunityPostPinActiveWindow() {
        let activePin = makeCommunityPostPin(postID: UUID(), endsAt: "2099-01-01T00:00:00Z")
        let expiredPin = makeCommunityPostPin(postID: UUID(), endsAt: "2020-01-01T00:00:00Z")
        let futurePin = makeCommunityPostPin(postID: UUID(), startsAt: "2099-01-01T00:00:00Z")
        let inactivePin = makeCommunityPostPin(postID: UUID(), status: "inactive")

        XCTAssertTrue(activePin.isCurrentlyActive)
        XCTAssertFalse(expiredPin.isCurrentlyActive)
        XCTAssertFalse(futurePin.isCurrentlyActive)
        XCTAssertFalse(inactivePin.isCurrentlyActive)
    }

    func testCommunityFeedCapabilityFallbackRecognizesMissingFunctionErrors() {
        let messages = [
            "Could not find the function public.community_feed_v1(p_category, p_limit, p_search) in the schema cache",
            "Could not find the function public.community_hot_posts_v1(p_days, p_limit) in the schema cache",
            "Function public.toggle_post_like_v1 does not exist",
            "community-feed returned 404"
        ]

        for message in messages {
            XCTAssertTrue(
                CommunityService.isMissingCommunityFeedCapabilityMessage(message),
                "Expected fallback for: \(message)"
            )
        }
    }

    func testCommunityFeedCapabilityFallbackIgnoresBusinessErrors() {
        let messages = [
            "COMMUNITY_TERMS_REQUIRED",
            "CANNOT_LIKE_OWN_POST",
            "community_feed_v1 rejected malformed input"
        ]

        for message in messages {
            XCTAssertFalse(
                CommunityService.isMissingCommunityFeedCapabilityMessage(message),
                "Unexpected fallback for: \(message)"
            )
        }
    }

    func testCommunityPostDeepLinkParsesSupportedURLs() throws {
        let postID = UUID()
        let universalLink = URL(string: "https://myleafy.space/share/community/post/\(postID.uuidString)")!
        let customScheme = URL(string: "leafy://community-post?id=\(postID.uuidString)")!

        XCTAssertEqual(CommunityPostDeepLink(url: universalLink)?.postID, postID)
        XCTAssertEqual(CommunityPostDeepLink(url: customScheme)?.postID, postID)
        XCTAssertNil(CommunityPostDeepLink(url: URL(string: "https://myleafy.space/share/community/post/not-a-uuid")!))
    }

    func testFirstValueMapKeepsFirstRemoteValueForDuplicateKeys() throws {
        let postID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        let profileID = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
        let pollID = UUID(uuidString: "00000000-0000-0000-0000-000000000103")!
        let firstOptionID = UUID(uuidString: "00000000-0000-0000-0000-000000000201")!
        let secondOptionID = UUID(uuidString: "00000000-0000-0000-0000-000000000202")!
        let firstSignedURL = URL(string: "https://example.com/first")!
        let secondSignedURL = URL(string: "https://example.com/second")!

        let postOrder = LeafyFirstValueMap.build([(postID, 0), (postID, 1)])
        let profileMap = LeafyFirstValueMap.build([(profileID, "first"), (profileID, "second")])
        let signedMap = LeafyFirstValueMap.build([("images/post.jpg", firstSignedURL), ("images/post.jpg", secondSignedURL)])
        let voteMap = LeafyFirstValueMap.build([(pollID, firstOptionID), (pollID, secondOptionID)])

        XCTAssertEqual(postOrder[postID], 0)
        XCTAssertEqual(profileMap[profileID], "first")
        XCTAssertEqual(signedMap["images/post.jpg"], firstSignedURL)
        XCTAssertEqual(voteMap[pollID], firstOptionID)
    }

    func testRootTabVisibleCasesHideCommunityWhenDisabled() {
        XCTAssertEqual(RootTab.visibleCases(isCommunityEnabled: true), [.leafy, .timetable, .community, .academics, .profile])
        XCTAssertEqual(RootTab.visibleCases(isCommunityEnabled: false), [.leafy, .timetable, .academics, .profile])
    }

    func testRootTabAllCasesOnlyContainPrimaryDestinations() {
        XCTAssertEqual(RootTab.allCases, [.leafy, .timetable, .community, .academics, .profile])
    }

    func testAcademicRootTabUsesCampusProductName() {
        XCTAssertEqual(RootTab.academics.title(language: .zhHans), "校园")
    }

    func testCampusIdentityScopeKeySeparatesSchoolPortalAndCustomSupabase() {
        let undergraduate = CampusIdentity(
            campusID: .bjfu,
            eduID: "20260001",
            displayName: "同学",
            portal: .undergraduate
        )
        let graduate = CampusIdentity(
            campusID: .bjfu,
            eduID: "20260001",
            displayName: "同学",
            portal: .graduate
        )
        let custom = CampusIdentity(
            campusID: .custom,
            eduID: "00000000-0000-0000-0000-000000000001",
            displayName: "user@example.com",
            portal: .undergraduate,
            kind: .customSupabase
        )

        XCTAssertNotEqual(undergraduate.scopeKey, graduate.scopeKey)
        XCTAssertNotEqual(undergraduate.scopeKey, custom.scopeKey)
        XCTAssertNotEqual(graduate.scopeKey, custom.scopeKey)
    }

    func testCampusIdentityActivationOnlyNotifiesWhenScopeChanges() throws {
        let suiteName = "campus-identity-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            CampusIdentityStore.clear(defaults: defaults)
            defaults.removePersistentDomain(forName: suiteName)
        }

        var notificationCount = 0
        let observer = NotificationCenter.default.addObserver(
            forName: .campusIdentityDidChange,
            object: nil,
            queue: nil
        ) { _ in
            notificationCount += 1
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
        }

        let initial = CampusIdentity(
            campusID: .bjfu,
            eduID: "20260001",
            displayName: "同学",
            portal: .undergraduate
        )
        CampusIdentityStore.activate(initial, defaults: defaults)
        XCTAssertEqual(notificationCount, 1)

        let renamed = CampusIdentity(
            campusID: .bjfu,
            eduID: "20260001",
            displayName: "新名字",
            portal: .undergraduate
        )
        CampusIdentityStore.activate(renamed, defaults: defaults)
        XCTAssertEqual(notificationCount, 1)
        XCTAssertEqual(CampusIdentityStore.currentIdentity(defaults: defaults)?.displayName, "新名字")

        let graduate = CampusIdentity(
            campusID: .bjfu,
            eduID: "20260001",
            displayName: "新名字",
            portal: .graduate
        )
        CampusIdentityStore.activate(graduate, defaults: defaults)
        XCTAssertEqual(notificationCount, 2)

        let differentAccount = CampusIdentity(
            campusID: .bjfu,
            eduID: "20260002",
            displayName: "另一位同学",
            portal: .graduate
        )
        CampusIdentityStore.activate(differentAccount, defaults: defaults)
        XCTAssertEqual(notificationCount, 3)
    }

    func testCustomCampusAuthCallbackOnlyAcceptsAuthCallbackURL() {
        XCTAssertTrue(CustomCampusAuthCallback.isCallback(URL(string: "leafy://auth/callback?code=abc")!))
        XCTAssertFalse(CustomCampusAuthCallback.isCallback(URL(string: "leafy://community-post?id=00000000-0000-0000-0000-000000000001")!))
        XCTAssertFalse(CustomCampusAuthCallback.isCallback(URL(string: "https://myleafy.space/auth/callback?code=abc")!))
    }

    func testCustomCampusAuthSessionBuildsCustomCampusIdentity() {
        let userID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let session = CustomCampusAuthSession(authUserID: userID, email: "user@example.com")
        let identity = session.campusIdentity

        XCTAssertEqual(identity.campusID, .custom)
        XCTAssertEqual(identity.eduID, userID.uuidString)
        XCTAssertEqual(identity.displayName, "user@example.com")
        XCTAssertEqual(identity.kind, .customSupabase)
        XCTAssertTrue(identity.isCustom)
    }

    func testCustomCampusAuthNormalizesEmailOTPCode() {
        XCTAssertEqual(CustomCampusAuthService.normalizeCodeForTesting(" 123 456 "), "123456")
        XCTAssertEqual(CustomCampusAuthService.normalizeCodeForTesting("12-34-56"), "123456")
        XCTAssertEqual(CustomCampusAuthService.normalizeCodeForTesting("12 34 56 78"), "12345678")
    }

    func testCustomCampusAuthMapsRecoverableSupabaseSignupErrors() {
        let invalidCredentials = AuthError.api(
            message: "Invalid login credentials",
            errorCode: .invalidCredentials,
            underlyingData: Data(),
            underlyingResponse: HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 400, httpVersion: nil, headerFields: nil)!
        )
        let emailNotConfirmed = AuthError.api(
            message: "Email not confirmed",
            errorCode: .emailNotConfirmed,
            underlyingData: Data(),
            underlyingResponse: HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 400, httpVersion: nil, headerFields: nil)!
        )
        let expiredCode = AuthError.api(
            message: "Email link is expired",
            errorCode: .otpExpired,
            underlyingData: Data(),
            underlyingResponse: HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 400, httpVersion: nil, headerFields: nil)!
        )
        let rateLimited = AuthError.api(
            message: "Email rate limit exceeded",
            errorCode: .overEmailSendRateLimit,
            underlyingData: Data(),
            underlyingResponse: HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 429, httpVersion: nil, headerFields: nil)!
        )
        let existingUser = AuthError.api(
            message: "User already registered",
            errorCode: .userAlreadyExists,
            underlyingData: Data(),
            underlyingResponse: HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 422, httpVersion: nil, headerFields: nil)!
        )

        XCTAssertTrue(CustomCampusAuthService.mapAuthErrorForTesting(invalidCredentials) is CustomCampusAuthError)
        XCTAssertEqual(
            CustomCampusAuthService.mapAuthErrorForTesting(invalidCredentials).localizedDescription,
            CustomCampusAuthError.invalidCredentials.localizedDescription
        )
        XCTAssertEqual(
            CustomCampusAuthService.mapAuthErrorForTesting(emailNotConfirmed, email: "user@example.com").localizedDescription,
            CustomCampusAuthError.emailNotConfirmed("user@example.com").localizedDescription
        )
        XCTAssertEqual(
            CustomCampusAuthService.mapAuthErrorForTesting(expiredCode).localizedDescription,
            CustomCampusAuthError.expiredCode.localizedDescription
        )
        XCTAssertEqual(
            CustomCampusAuthService.mapAuthErrorForTesting(rateLimited).localizedDescription,
            CustomCampusAuthError.emailRateLimited.localizedDescription
        )
        XCTAssertEqual(
            CustomCampusAuthService.mapAuthErrorForTesting(existingUser).localizedDescription,
            CustomCampusAuthError.userAlreadyExists.localizedDescription
        )
    }

    func testCustomCampusAuthMapsPKCECallbackFailures() {
        let expired = AuthError.pkceGrantCodeExchange(
            message: "Email link is expired",
            error: "access_denied",
            code: ErrorCode.otpExpired.rawValue
        )
        let missingFlowState = AuthError.pkceGrantCodeExchange(
            message: "Flow state not found",
            error: "server_error",
            code: ErrorCode.flowStateNotFound.rawValue
        )

        XCTAssertEqual(
            CustomCampusAuthService.mapCallbackErrorForTesting(expired).localizedDescription,
            CustomCampusAuthError.callbackLinkInvalid.localizedDescription
        )
        XCTAssertEqual(
            CustomCampusAuthService.mapCallbackErrorForTesting(missingFlowState).localizedDescription,
            CustomCampusAuthError.callbackNeedsOriginalDevice.localizedDescription
        )
    }

    func testCustomCampusCSVParserParsesTimetableGradesAndExams() throws {
        let timetableCSV = """
        courseName,teacher,classInfo,room,location,dayOfWeek,weeks,duration
        数据结构,林青,演示班,二教 205,二教,1,"1-4","1,2"
        """
        let timetable = try CustomCampusCSVParser.parseTimetable(timetableCSV)
        XCTAssertEqual(timetable.count, 1)
        XCTAssertEqual(timetable[0].courseName, "数据结构")
        XCTAssertEqual(timetable[0].dayOfWeek, 1)
        XCTAssertEqual(timetable[0].weeks, [1, 2, 3, 4])
        XCTAssertEqual(timetable[0].duration, [1, 2])

        let gradeCSV = """
        term,courseName,credit,score,type
        2025-2026-2,数据结构,3.0,92,必修
        """
        let grades = try CustomCampusCSVParser.parseGrades(gradeCSV)
        XCTAssertEqual(grades, [
            CustomCampusImportedGrade(term: "2025-2026-2", courseName: "数据结构", credit: "3.0", score: "92", type: "必修")
        ])

        let examCSV = """
        courseID,name,date,start,end,location
        DS-001,数据结构,2026-06-20,09:00,11:00,二教 205
        """
        let exams = try CustomCampusCSVParser.parseExams(examCSV)
        XCTAssertEqual(exams, [
            ExamArrangement(id: 1, courseID: "DS-001", name: "数据结构", date: "2026-06-20", start: "09:00", end: "11:00", location: "二教 205")
        ])
    }

    func testCustomCampusCSVParserReportsMissingColumns() {
        let csv = """
        term,courseName,score,type
        2025-2026-2,数据结构,92,必修
        """

        XCTAssertThrowsError(try CustomCampusCSVParser.parseGrades(csv)) { error in
            guard case CustomCampusImportError.missingColumns(let columns) = error else {
                return XCTFail("Expected missingColumns, got \(error)")
            }
            XCTAssertEqual(columns, ["credit"])
        }
    }

    func testCatalogSuggestionInputKeepsTeacherNameInRepository() async throws {
        let repository = FakeCommunityRepository()
        let input = CatalogSuggestionInput(
            type: .course,
            name: "森林生态学导论",
            unit: "林学院",
            teacherName: "王老师",
            category: "公选课",
            credit: 2,
            initialStars: 4,
            note: "建议补充"
        )

        try await repository.submitCatalogSuggestion(input: input)

        let submittedSuggestions = await repository.submittedCatalogSuggestions()
        XCTAssertEqual(submittedSuggestions, [input])
        XCTAssertEqual(submittedSuggestions.first?.teacherName, "王老师")
        XCTAssertEqual(submittedSuggestions.first?.initialStars, 4)
    }

    func testFavoritedProfileListRemovesPostWhenUnfavorited() {
        let favoritedPost = makeCommunityPost(viewerHasFavorited: true)
        let otherPost = makeCommunityPost(title: "其他收藏", viewerHasFavorited: true)
        let unfavoritedPost = makeCommunityPost(
            id: favoritedPost.id,
            authorID: favoritedPost.authorID,
            viewerHasFavorited: false
        )

        let updatedPosts = ProfileCommunityPostListReducer.applyingPostChange(
            unfavoritedPost,
            to: [favoritedPost, otherPost],
            kind: .favorited
        )

        XCTAssertEqual(updatedPosts, [otherPost])
    }

    func testAppStoreReviewCoordinatorRequiresThreeDifferentSyncDays() {
        let defaults = makeReviewUserDefaults()
        let notificationCenter = NotificationCenter()

        AppStoreReviewCoordinator.recordSuccessfulSync(
            kind: .timetable,
            date: reviewDate(2026, 5, 10),
            calendar: reviewTestCalendar,
            userDefaults: defaults,
            notificationCenter: notificationCenter
        )
        AppStoreReviewCoordinator.recordSuccessfulSync(
            kind: .timetable,
            date: reviewDate(2026, 5, 10),
            calendar: reviewTestCalendar,
            userDefaults: defaults,
            notificationCenter: notificationCenter
        )
        AppStoreReviewCoordinator.recordSuccessfulSync(
            kind: .timetable,
            date: reviewDate(2026, 5, 11),
            calendar: reviewTestCalendar,
            userDefaults: defaults,
            notificationCenter: notificationCenter
        )

        XCTAssertFalse(AppStoreReviewCoordinator.shouldRequestReview(
            now: reviewDate(2026, 5, 12),
            appVersion: "1.0",
            isDemoMode: false,
            isSceneActive: true,
            userDefaults: defaults
        ))
    }

    func testAppStoreReviewCoordinatorAllowsThirdDifferentSyncDay() {
        let defaults = makeReviewUserDefaults()
        seedThreeReviewSyncDays(defaults: defaults)

        XCTAssertTrue(AppStoreReviewCoordinator.shouldRequestReview(
            now: reviewDate(2026, 5, 13),
            appVersion: "1.0",
            isDemoMode: false,
            isSceneActive: true,
            userDefaults: defaults
        ))
    }

    func testAppStoreReviewCoordinatorBlocksDemoInactiveAndSameVersion() {
        let defaults = makeReviewUserDefaults()
        seedThreeReviewSyncDays(defaults: defaults)
        let now = reviewDate(2026, 5, 13)

        XCTAssertFalse(AppStoreReviewCoordinator.shouldRequestReview(
            now: now,
            appVersion: "1.0",
            isDemoMode: true,
            isSceneActive: true,
            userDefaults: defaults
        ))
        XCTAssertFalse(AppStoreReviewCoordinator.shouldRequestReview(
            now: now,
            appVersion: "1.0",
            isDemoMode: false,
            isSceneActive: false,
            userDefaults: defaults
        ))

        AppStoreReviewCoordinator.markReviewRequestAttempted(
            now: now,
            appVersion: "1.0",
            userDefaults: defaults
        )

        XCTAssertFalse(AppStoreReviewCoordinator.shouldRequestReview(
            now: reviewTestCalendar.date(byAdding: .day, value: 121, to: now)!,
            appVersion: "1.0",
            isDemoMode: false,
            isSceneActive: true,
            userDefaults: defaults
        ))
    }

    func testAppStoreReviewCoordinatorCooldownAppliesAcrossVersions() {
        let defaults = makeReviewUserDefaults()
        seedThreeReviewSyncDays(defaults: defaults)
        let attemptedAt = reviewDate(2026, 5, 13)

        AppStoreReviewCoordinator.markReviewRequestAttempted(
            now: attemptedAt,
            appVersion: "1.0",
            userDefaults: defaults
        )

        XCTAssertFalse(AppStoreReviewCoordinator.shouldRequestReview(
            now: reviewTestCalendar.date(byAdding: .day, value: 119, to: attemptedAt)!,
            appVersion: "2.0",
            isDemoMode: false,
            isSceneActive: true,
            userDefaults: defaults
        ))
        XCTAssertTrue(AppStoreReviewCoordinator.shouldRequestReview(
            now: reviewTestCalendar.date(byAdding: .day, value: 121, to: attemptedAt)!,
            appVersion: "2.0",
            isDemoMode: false,
            isSceneActive: true,
            userDefaults: defaults
        ))
    }

    func testTimetableScheduleProjectionSnapshotIndexesAndSortsByWeekDay() {
        let earlyCountdown = CustomCountdownEvent(
            id: "early",
            title: "Early",
            targetDate: semesterDate(week: 2, day: 1, hour: 8, minute: 10)
        )
        let lateCountdown = CustomCountdownEvent(
            id: "late",
            title: "Late",
            targetDate: semesterDate(week: 2, day: 1, hour: 9, minute: 55)
        )
        let otherDayCountdown = CustomCountdownEvent(
            id: "other",
            title: "Other",
            targetDate: semesterDate(week: 2, day: 2, hour: 8, minute: 10)
        )
        let exams = [
            ExamArrangement(id: 2, courseID: "B", name: "Second", date: "2026-03-16", start: "09:50", end: "10:35", location: "102"),
            ExamArrangement(id: 1, courseID: "A", name: "First", date: "2026-03-16", start: "08:00", end: "08:45", location: "101")
        ]

        let snapshot = TimetableScheduleProjectionSnapshot.make(
            countdownEvents: [lateCountdown, otherDayCountdown, earlyCountdown],
            exams: exams
        )

        XCTAssertEqual(snapshot.countdowns(week: 2, day: 1).map(\.title), ["Early", "Late"])
        XCTAssertEqual(snapshot.countdowns(week: 2, day: 2).map(\.title), ["Other"])
        XCTAssertEqual(snapshot.exams(week: 2, day: 1).map(\.name), ["First", "Second"])
        XCTAssertTrue(snapshot.exams(week: 19, day: 7).isEmpty)
    }

    func testProfileCacheSummaryBuildsEmptyCacheRows() throws {
        let summary = ProfileCacheSummary.make(
            language: .zhHans,
            courseCount: 0,
            gradeCount: 0,
            timetableLastSyncAt: nil,
            gradeRankingCount: 0,
            gradeRankingLastSyncAt: nil,
            gradeCreditTotal: nil,
            examCount: 0,
            examLastSyncAt: nil,
            graduationRequirementCount: 0,
            graduationRequirementLastSyncAt: nil,
            classroomsLastSyncAt: nil,
            noteCount: 0,
            reminderCount: 0,
            cellReminderCount: 0,
            favoriteClassroomCount: 0,
            postgraduateTargetCount: 0,
            learningMaterialCount: 0,
            learningProjectCount: 0,
            learningTaskCount: 0,
            studyTimeRecordCount: 0,
            fitnessTestRecordCount: 0
        )

        XCTAssertEqual(summary.rows.count, 10)
        XCTAssertEqual(try XCTUnwrap(summary.rows.first { $0.title == "所得学分" }).value, "未缓存")
        XCTAssertEqual(try XCTUnwrap(summary.rows.first { $0.title == "课表" }).detail, "暂无同步记录")
        XCTAssertEqual(try XCTUnwrap(summary.rows.first { $0.title == "本地数据" }).value, "0 条备注 / 0 个收藏")
        XCTAssertEqual(try XCTUnwrap(summary.rows.first { $0.title == "学习空间" }).value, "0 个空间 / 0 份资料")
        XCTAssertEqual(try XCTUnwrap(summary.rows.first { $0.title == "体测记录" }).value, "0 条记录")
    }

    func testProfileCacheSummaryBuildsPopulatedCacheRows() throws {
        let syncedAt = reviewDate(2026, 5, 14)
        let summary = ProfileCacheSummary.make(
            language: .zhHans,
            courseCount: 6,
            gradeCount: 12,
            timetableLastSyncAt: syncedAt,
            gradeRankingCount: 3,
            gradeRankingLastSyncAt: syncedAt,
            gradeCreditTotal: 42.5,
            examCount: 2,
            examLastSyncAt: syncedAt,
            graduationRequirementCount: 9,
            graduationRequirementLastSyncAt: syncedAt,
            classroomsLastSyncAt: syncedAt,
            noteCount: 4,
            reminderCount: 5,
            cellReminderCount: 6,
            favoriteClassroomCount: 7,
            postgraduateTargetCount: 3,
            learningMaterialCount: 8,
            learningProjectCount: 2,
            learningTaskCount: 10,
            studyTimeRecordCount: 11,
            fitnessTestRecordCount: 9
        )

        XCTAssertEqual(try XCTUnwrap(summary.rows.first { $0.title == "所得学分" }).value, "42.5 学分")
        XCTAssertEqual(try XCTUnwrap(summary.rows.first { $0.title == "考试安排" }).value, "2 条考试")
        XCTAssertEqual(try XCTUnwrap(summary.rows.first { $0.title == "本地数据" }).detail, "11 个提醒")
        XCTAssertEqual(try XCTUnwrap(summary.rows.first { $0.title == "学习空间" }).value, "2 个空间 / 8 份资料")
        XCTAssertEqual(try XCTUnwrap(summary.rows.first { $0.title == "学习空间" }).detail, "10 个任务 / 11 条记录")
        XCTAssertEqual(try XCTUnwrap(summary.rows.first { $0.title == "体测记录" }).value, "9 条记录")
        XCTAssertTrue(try XCTUnwrap(summary.rows.first { $0.title == "课表" }).detail.contains("最近同步："))
    }

    func testAcademicPrimaryTabPlacesLearningBeforeSports() throws {
        let tabs = AcademicPrimaryTab.allCases
        let learningIndex = try XCTUnwrap(tabs.firstIndex(of: .learning))
        let sportsIndex = try XCTUnwrap(tabs.firstIndex(of: .sports))

        XCTAssertEqual(learningIndex + 1, sportsIndex)
    }

    func testLearningMaterialCategoryFallsBackToOther() {
        XCTAssertEqual(LearningMaterialCategory.normalized("四六级"), .cet)
        XCTAssertEqual(LearningMaterialCategory.normalized("未知"), .other)
    }

    func testLearningFixedSpaceOrder() {
        XCTAssertEqual(LearningMaterialCategory.fixedSpaceOrder, [.cet, .exam, .courseware, .other])
    }

    func testLearningProjectKindFallsBackToGeneral() {
        XCTAssertEqual(LearningProjectKind.normalized("course"), .course)
        XCTAssertEqual(LearningProjectKind.normalized("unknown"), .general)
    }

    func testPostgraduateTargetStateFallsBackToActive() {
        XCTAssertEqual(PostgraduateTargetState.normalized("focused"), .focused)
        XCTAssertEqual(PostgraduateTargetState.normalized("unknown"), .active)
    }

    func testPostgraduateSourceTrustLevelFallsBackToCurated() {
        XCTAssertEqual(PostgraduateSourceTrustLevel.normalized("official"), .official)
        XCTAssertEqual(PostgraduateSourceTrustLevel.normalized("unknown"), .curated)
    }

    func testPostgraduatePublishedSourceExposesOfficialURLAndKind() {
        let source = PostgraduateSource(
            id: UUID(),
            title: "北林招生简章",
            summary: "招生政策",
            sourceURLString: "https://graduate.bjfu.edu.cn/",
            sourceKindRawValue: PostgraduateSourceKind.admissionNotice.rawValue,
            trustLevelRawValue: PostgraduateSourceTrustLevel.official.rawValue,
            school: "北京林业大学",
            unit: nil,
            major: nil,
            examYear: 2026,
            publishedAt: nil,
            verifiedAt: nil,
            status: "published",
            createdAt: nil,
            updatedAt: nil
        )

        XCTAssertEqual(source.sourceURL?.scheme, "https")
        XCTAssertEqual(source.sourceKind, .admissionNotice)
        XCTAssertEqual(source.trustLevel, .official)
    }

    func testPostgraduateSourceMatcherPrefersExactTargetMatch() throws {
        let target = PostgraduateTarget(
            school: "北京林业大学",
            unit: "园林学院",
            major: "风景园林",
            examYear: 2026
        )
        let exactID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let schoolID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let generalID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000003"))
        let sources = [
            PostgraduateSource(
                id: generalID,
                title: "研招网",
                summary: "硕士专业目录",
                sourceURLString: "https://yz.chsi.com.cn/",
                sourceKindRawValue: PostgraduateSourceKind.majorCatalog.rawValue,
                trustLevelRawValue: PostgraduateSourceTrustLevel.official.rawValue,
                school: nil,
                unit: nil,
                major: nil,
                examYear: nil,
                publishedAt: nil,
                verifiedAt: nil,
                status: "published",
                createdAt: nil,
                updatedAt: nil
            ),
            PostgraduateSource(
                id: schoolID,
                title: "北京林业大学硕士招生简章",
                summary: "学校招生信息",
                sourceURLString: "https://graduate.bjfu.edu.cn/",
                sourceKindRawValue: PostgraduateSourceKind.admissionNotice.rawValue,
                trustLevelRawValue: PostgraduateSourceTrustLevel.official.rawValue,
                school: "北京林业大学",
                unit: nil,
                major: nil,
                examYear: 2026,
                publishedAt: nil,
                verifiedAt: nil,
                status: "published",
                createdAt: nil,
                updatedAt: nil
            ),
            PostgraduateSource(
                id: exactID,
                title: "北京林业大学风景园林复试线",
                summary: "园林学院风景园林复试信息",
                sourceURLString: "https://graduate.bjfu.edu.cn/",
                sourceKindRawValue: PostgraduateSourceKind.scoreLine.rawValue,
                trustLevelRawValue: PostgraduateSourceTrustLevel.verifiedUser.rawValue,
                school: "北京林业大学",
                unit: "园林学院",
                major: "风景园林",
                examYear: 2026,
                publishedAt: nil,
                verifiedAt: nil,
                status: "published",
                createdAt: nil,
                updatedAt: nil
            )
        ]

        let sorted = PostgraduateSourceMatcher.sortedSources(for: target, from: sources)

        XCTAssertEqual(sorted.map(\.id), [exactID, schoolID, generalID])
    }

    func testPostgraduateTimelineSpansPreviousYearThroughAdmissionYear() {
        let nodes = PostgraduateTimelineBuilder.nodes(
            forExamYear: 2027,
            now: reviewDate(2026, 1, 1),
            calendar: reviewTestCalendar
        )

        XCTAssertEqual(nodes.map(\.phase), PostgraduateTimelinePhase.allCases)
        XCTAssertEqual(nodes.first?.periodText, "2026年3-6月")
        XCTAssertEqual(nodes.last?.periodText, "2027年4-6月")
    }

    func testPostgraduateTimelineMarksCurrentPhaseFromMonthWindow() {
        let nodes = PostgraduateTimelineBuilder.nodes(
            forExamYear: 2027,
            now: reviewDate(2026, 10, 12),
            calendar: reviewTestCalendar
        )

        XCTAssertEqual(nodes.first { $0.phase == .catalog }?.status, .completed)
        XCTAssertEqual(nodes.first { $0.phase == .registration }?.status, .current)
        XCTAssertEqual(nodes.first { $0.phase == .confirmation }?.status, .upcoming)
    }

    func testPostgraduateTargetSelectorPrefersFocusedAndSkipsArchived() throws {
        let archivedID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000101"))
        let activeID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000102"))
        let focusedID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000103"))
        let archived = PostgraduateTarget(
            id: archivedID,
            school: "归档大学",
            major: "林学",
            examYear: 2026,
            stateRawValue: PostgraduateTargetState.archived.rawValue
        )
        let active = PostgraduateTarget(
            id: activeID,
            school: "活跃大学",
            major: "生态学",
            examYear: 2026
        )
        let focused = PostgraduateTarget(
            id: focusedID,
            school: "聚焦大学",
            major: "风景园林",
            examYear: 2028,
            stateRawValue: PostgraduateTargetState.focused.rawValue
        )

        let selected = PostgraduateTargetSelector.primaryTarget(
            from: [archived, active, focused],
            currentYear: 2026
        )
        let activeTargets = PostgraduateTargetSelector.sortedActiveTargets(
            from: [archived, active, focused],
            currentYear: 2026
        )

        XCTAssertEqual(selected?.id, focusedID)
        XCTAssertEqual(activeTargets.map(\.id), [focusedID, activeID])
        XCTAssertFalse(activeTargets.contains { $0.id == archivedID })
    }

    func testPostgraduateSourcePresentationKeepsGeneralFallbackForTarget() throws {
        let target = PostgraduateTarget(
            school: "北京林业大学",
            unit: "园林学院",
            major: "风景园林",
            examYear: 2027
        )
        let exactID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000201"))
        let generalID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000202"))
        let unrelatedID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000203"))
        let sources = [
            PostgraduateSource(
                id: unrelatedID,
                title: "其他学校招生简章",
                summary: "无关来源",
                sourceURLString: "https://example.com/",
                sourceKindRawValue: PostgraduateSourceKind.admissionNotice.rawValue,
                trustLevelRawValue: PostgraduateSourceTrustLevel.official.rawValue,
                school: "其他学校",
                unit: nil,
                major: "软件工程",
                examYear: 2027,
                publishedAt: nil,
                verifiedAt: nil,
                status: "published",
                createdAt: nil,
                updatedAt: nil
            ),
            PostgraduateSource(
                id: generalID,
                title: "研招网硕士专业目录",
                summary: "通用来源",
                sourceURLString: "https://yz.chsi.com.cn/zsml/",
                sourceKindRawValue: PostgraduateSourceKind.majorCatalog.rawValue,
                trustLevelRawValue: PostgraduateSourceTrustLevel.official.rawValue,
                school: nil,
                unit: nil,
                major: nil,
                examYear: nil,
                publishedAt: nil,
                verifiedAt: nil,
                status: "published",
                createdAt: nil,
                updatedAt: nil
            ),
            PostgraduateSource(
                id: exactID,
                title: "北京林业大学风景园林复试线",
                summary: "园林学院风景园林复试信息",
                sourceURLString: "https://graduate.bjfu.edu.cn/",
                sourceKindRawValue: PostgraduateSourceKind.scoreLine.rawValue,
                trustLevelRawValue: PostgraduateSourceTrustLevel.curated.rawValue,
                school: "北京林业大学",
                unit: "园林学院",
                major: "风景园林",
                examYear: 2027,
                publishedAt: nil,
                verifiedAt: nil,
                status: "published",
                createdAt: nil,
                updatedAt: nil
            )
        ]

        let sorted = PostgraduateSourcePresentation.sortedSources(for: target, from: sources)

        XCTAssertEqual(sorted.map(\.id), [exactID, generalID])
    }

    func testLearningWorkspaceSummaryScopesFixedAndProjectContent() throws {
        let projectID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000123"))
        let now = reviewDate(2026, 5, 14)
        let sameWeek = reviewDate(2026, 5, 13)
        let oldDate = reviewDate(2026, 4, 1)
        let materials = [
            LearningMaterialDocument(title: "CET", categoryRawValue: LearningMaterialCategory.cet.rawValue, originalFilename: "cet.pdf", localFilename: "cet.pdf", contentTypeIdentifier: UTType.pdf.identifier),
            LearningMaterialDocument(projectID: projectID.uuidString, title: "Project", originalFilename: "p.pdf", localFilename: "p.pdf", contentTypeIdentifier: UTType.pdf.identifier)
        ]
        let tasks = [
            LearningProjectTask(categoryRawValue: LearningMaterialCategory.cet.rawValue, title: "背单词"),
            LearningProjectTask(projectID: projectID.uuidString, title: "刷题", isCompleted: true)
        ]
        let records = [
            StudyTimeRecord(categoryRawValue: LearningMaterialCategory.cet.rawValue, startedAt: sameWeek, endedAt: sameWeek.addingTimeInterval(3600), content: "听力", location: "图书馆"),
            StudyTimeRecord(projectID: projectID.uuidString, startedAt: oldDate, endedAt: oldDate.addingTimeInterval(1800), content: "项目", location: "图书馆")
        ]

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!

        let fixed = LearningWorkspaceSummary.make(destination: .fixed(.cet), materials: materials, tasks: tasks, records: records, now: now, calendar: calendar)
        XCTAssertEqual(fixed.materialCount, 1)
        XCTAssertEqual(fixed.pendingTaskCount, 1)
        XCTAssertEqual(fixed.weekDuration, 3600)

        let project = LearningWorkspaceSummary.make(destination: .project(projectID), materials: materials, tasks: tasks, records: records, now: now, calendar: calendar)
        XCTAssertEqual(project.materialCount, 1)
        XCTAssertEqual(project.completedTaskCount, 1)
        XCTAssertEqual(project.totalDuration, 1800)
    }

    func testStudyTimeRecordsWithoutTopicBelongToOtherSpace() throws {
        let projectID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000125"))
        let now = reviewDate(2026, 5, 14)
        let unscopedRecord = StudyTimeRecord(startedAt: now, endedAt: now.addingTimeInterval(900), content: "专注学习", location: "图书馆")
        let fixedRecord = StudyTimeRecord(categoryRawValue: LearningMaterialCategory.exam.rawValue, startedAt: now, endedAt: now.addingTimeInterval(1200), content: "专业课", location: "图书馆")
        let projectRecord = StudyTimeRecord(projectID: projectID.uuidString, startedAt: now, endedAt: now.addingTimeInterval(1800), content: "项目", location: "图书馆")
        let records = [unscopedRecord, fixedRecord, projectRecord]

        XCTAssertTrue(unscopedRecord.belongs(to: .fixed(.other)))
        XCTAssertEqual(LearningWorkspaceSummary.make(destination: .fixed(.other), materials: [], tasks: [], records: records, now: now).totalDuration, 900)
        XCTAssertEqual(LearningWorkspaceSummary.make(destination: .fixed(.exam), materials: [], tasks: [], records: records, now: now).totalDuration, 1200)
        XCTAssertEqual(LearningWorkspaceSummary.make(destination: .project(projectID), materials: [], tasks: [], records: records, now: now).totalDuration, 1800)
        let index = LearningWorkspaceIndex.make(materials: [], tasks: [], records: records, now: now)
        XCTAssertEqual(index.summary(for: .fixed(.other)).totalDuration, 900)
        XCTAssertEqual(records.learningDuration, 3900)
    }

    @MainActor
    func testLearningWorkspaceIndexMatchesSummaryScopes() throws {
        let projectID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000124"))
        let now = reviewDate(2026, 5, 14)
        let sameWeek = reviewDate(2026, 5, 13)
        let materials = [
            LearningMaterialDocument(title: "CET", categoryRawValue: LearningMaterialCategory.cet.rawValue, originalFilename: "cet.pdf", localFilename: "cet.pdf", contentTypeIdentifier: UTType.pdf.identifier),
            LearningMaterialDocument(projectID: projectID.uuidString, title: "Project", originalFilename: "p.pdf", localFilename: "p.pdf", contentTypeIdentifier: UTType.pdf.identifier)
        ]
        let tasks = [
            LearningProjectTask(categoryRawValue: LearningMaterialCategory.cet.rawValue, title: "背单词"),
            LearningProjectTask(projectID: projectID.uuidString, title: "刷题", isCompleted: true)
        ]
        let records = [
            StudyTimeRecord(categoryRawValue: LearningMaterialCategory.cet.rawValue, startedAt: sameWeek, endedAt: sameWeek.addingTimeInterval(3600), content: "听力", location: "图书馆"),
            StudyTimeRecord(projectID: projectID.uuidString, startedAt: sameWeek, endedAt: sameWeek.addingTimeInterval(1800), content: "项目", location: "图书馆")
        ]

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let index = LearningWorkspaceIndex.make(materials: materials, tasks: tasks, records: records, now: now, calendar: calendar)

        XCTAssertEqual(
            index.summary(for: .fixed(.cet)),
            LearningWorkspaceSummary.make(destination: .fixed(.cet), materials: materials, tasks: tasks, records: records, now: now, calendar: calendar)
        )
        XCTAssertEqual(
            index.summary(for: .project(projectID)),
            LearningWorkspaceSummary.make(destination: .project(projectID), materials: materials, tasks: tasks, records: records, now: now, calendar: calendar)
        )
        XCTAssertEqual(index.tasks(for: .fixed(.cet)).map(\.title), ["背单词"])
    }

    @MainActor
    func testGradePresentationSnapshotMatchesExistingAnalyticsAndGrouping() {
        let grades = [
            Grade(term: "2025-2026-2", courseName: "森林生态学", credit: "2.0", score: "92", type: "必修"),
            Grade(term: "2025-2026-1", courseName: "高等数学", credit: "4.0", score: "85", type: "必修")
        ]

        let snapshot = GradePresentationSnapshot.make(grades: grades, creditSummary: nil)
        let directAnalytics = GradeAnalytics.calculate(from: grades, creditSummary: nil)

        XCTAssertEqual(snapshot.analytics.totalCredits, directAnalytics.totalCredits)
        XCTAssertEqual(snapshot.analytics.effectiveCourseCount, directAnalytics.effectiveCourseCount)
        XCTAssertEqual(snapshot.sortedTerms, ["2025-2026-2", "2025-2026-1"])
        XCTAssertEqual(snapshot.groupedGrades["2025-2026-2"]?.map(\.courseName), ["森林生态学"])
    }

    @MainActor
    func testPassFailGradeKeepsRawScoreAndSkipsNumericStatistics() {
        let grades = [
            Grade(term: "2025-2026-2", courseName: "劳动教育", credit: "1.0", score: "合格", type: "必修"),
            Grade(term: "2025-2026-2", courseName: "森林生态学", credit: "2.0", score: "90", type: "必修")
        ]

        let analytics = GradeAnalytics.calculate(from: grades, creditSummary: nil)
        let passFailCourse = analytics.courses.first { $0.name == "劳动教育" }

        XCTAssertEqual(passFailCourse?.rawScore, "合格")
        XCTAssertNil(passFailCourse?.score)
        XCTAssertEqual(passFailCourse?.isPassed, true)
        XCTAssertEqual(passFailCourse?.isIncludedInStatistics, false)
        XCTAssertEqual(analytics.totalCredits, 3.0)
        XCTAssertEqual(analytics.passedCredits, 3.0)
        XCTAssertEqual(analytics.passRate, 1.0)
        XCTAssertEqual(analytics.weightedAverage, 90.0)
        XCTAssertEqual(analytics.medianScore, 90.0)
        XCTAssertEqual(analytics.scoreDistribution.first { $0.range == "90+" }?.count, 1)
        XCTAssertEqual(analytics.scoreDistribution.first { $0.range == "60-69" }?.count, 0)
    }

    @MainActor
    func testFailingTextGradeCountsAsRiskWithoutPassedCredits() {
        let grades = [
            Grade(term: "2025-2026-2", courseName: "劳动教育", credit: "1.0", score: "不合格", type: "必修"),
            Grade(term: "2025-2026-2", courseName: "森林生态学", credit: "2.0", score: "良好", type: "必修")
        ]

        let analytics = GradeAnalytics.calculate(from: grades, creditSummary: nil)
        let failingCourse = analytics.courses.first { $0.name == "劳动教育" }
        let gradedCourse = analytics.courses.first { $0.name == "森林生态学" }

        XCTAssertEqual(failingCourse?.rawScore, "不合格")
        XCTAssertNil(failingCourse?.score)
        XCTAssertEqual(failingCourse?.isPassed, false)
        XCTAssertEqual(failingCourse?.isIncludedInStatistics, false)
        XCTAssertEqual(gradedCourse?.score, 85)
        XCTAssertEqual(analytics.totalCredits, 3.0)
        XCTAssertEqual(analytics.passedCredits, 2.0)
        XCTAssertEqual(analytics.passRate, 0.5)
        XCTAssertEqual(analytics.riskCourseCount, 1)
        XCTAssertEqual(analytics.weightedAverage, 85.0)
    }

    @MainActor
    func testWeeklyTimetableProjectionPrecomputesVisibleLayoutsAndMetadata() {
        let selection = TimetableDaySelection(
            week: 1,
            day: 1,
            date: SemesterConfig.startOfSemesterDate
        )
        let mondayCourse = Course(
            courseName: "森林生态学",
            teacher: "T",
            room: "101",
            location: "",
            dayOfWeek: 1,
            weeks: [1],
            duration: [1, 2]
        )
        let saturdayCourse = Course(
            courseName: "周末课程",
            teacher: "T",
            room: "102",
            location: "",
            dayOfWeek: 6,
            weeks: [1],
            duration: [1]
        )
        let note = CourseNote(courseKey: mondayCourse.stableCourseKey, text: "带实验服")
        let reminder = TimetableCellReminder(week: 1, dayOfWeek: 1, period: 3, title: "预习")
        let exam = ExamArrangement(
            id: 1,
            courseID: "exam-1",
            name: "植物学考试",
            date: "2026-03-09",
            start: "08:00",
            end: "09:00",
            location: "二教"
        )

        let weekdaysOnly = WeeklyTimetableProjection.make(
            selection: selection,
            courses: [mondayCourse, saturdayCourse],
            cellReminders: [reminder],
            exams: [exam],
            courseNotes: [note],
            occurrenceNotes: [],
            includesWeekends: false
        )
        let fullWeek = WeeklyTimetableProjection.make(
            selection: selection,
            courses: [mondayCourse, saturdayCourse],
            cellReminders: [reminder],
            exams: [exam],
            courseNotes: [note],
            occurrenceNotes: [],
            includesWeekends: true
        )

        XCTAssertEqual(weekdaysOnly.days, [1, 2, 3, 4, 5])
        XCTAssertEqual(weekdaysOnly.layouts(for: 1).map(\.course.courseName), ["森林生态学"])
        XCTAssertTrue(weekdaysOnly.layouts(for: 6).isEmpty)
        XCTAssertTrue(weekdaysOnly.hasNote(for: mondayCourse))
        XCTAssertEqual(weekdaysOnly.reminders.map(\.title), ["预习"])
        XCTAssertEqual(weekdaysOnly.examProjections.map(\.name), ["植物学考试"])
        XCTAssertEqual(fullWeek.layouts(for: 6).map(\.course.courseName), ["周末课程"])
    }

    func testImageDataDecoderHandlesValidAndInvalidData() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.systemGreen.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        let data = try XCTUnwrap(image.pngData())

        XCTAssertNotNil(ImageDataDecoder.decodedImage(from: data, targetSize: CGSize(width: 4, height: 4)))
        XCTAssertNil(ImageDataDecoder.decodedImage(from: Data("not-an-image".utf8)))
    }

    func testImageDataDecoderAppliesOrientationTransform() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let sourceImage = UIGraphicsImageRenderer(size: CGSize(width: 6, height: 10), format: format).image { context in
            UIColor.systemRed.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 6, height: 10))
        }
        let orientedData = try XCTUnwrap(jpegData(from: sourceImage, orientation: 6))

        let decoded = try XCTUnwrap(ImageDataDecoder.decodedImage(from: orientedData, scale: 1))

        XCTAssertEqual(decoded.imageOrientation, .up)
        XCTAssertEqual(Int(decoded.size.width), 10)
        XCTAssertEqual(Int(decoded.size.height), 6)
    }

    private func jpegData(from image: UIImage, orientation: UInt32) -> Data? {
        guard let cgImage = image.cgImage else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }

        let properties: [CFString: Any] = [
            kCGImagePropertyOrientation: orientation
        ]
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    func testLearningProjectContentRelocationMovesProjectContentToUnfiled() throws {
        let projectID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000456"))
        let now = reviewDate(2026, 5, 14)
        let updatedAt = reviewDate(2026, 5, 15)
        let material = LearningMaterialDocument(projectID: projectID.uuidString, title: "Project", originalFilename: "p.pdf", localFilename: "p.pdf", contentTypeIdentifier: UTType.pdf.identifier)
        let task = LearningProjectTask(projectID: projectID.uuidString, title: "刷题")
        let record = StudyTimeRecord(projectID: projectID.uuidString, startedAt: now, endedAt: now.addingTimeInterval(1800), content: "项目", location: "图书馆")
        let otherMaterial = LearningMaterialDocument(title: "Other", originalFilename: "o.pdf", localFilename: "o.pdf", contentTypeIdentifier: UTType.pdf.identifier)
        let materials = [material, otherMaterial]
        let tasks = [task]
        let records = [record]

        LearningProjectContentRelocation.moveToUnfiled(
            projectID: projectID,
            materials: materials,
            tasks: tasks,
            records: records,
            updatedAt: updatedAt
        )

        XCTAssertEqual(material.projectID, "")
        XCTAssertEqual(material.category, .other)
        XCTAssertEqual(material.updatedAt, updatedAt)
        XCTAssertEqual(task.projectID, "")
        XCTAssertEqual(task.category, .other)
        XCTAssertEqual(record.projectID, "")
        XCTAssertEqual(record.category, .other)

        let project = LearningWorkspaceSummary.make(destination: .project(projectID), materials: materials, tasks: tasks, records: records, now: now)
        XCTAssertEqual(project, LearningWorkspaceSummary(materialCount: 0, taskCount: 0, completedTaskCount: 0, recordCount: 0, totalDuration: 0, weekDuration: 0))

        let other = LearningWorkspaceSummary.make(destination: .fixed(.other), materials: materials, tasks: tasks, records: records, now: now)
        XCTAssertEqual(other.materialCount, 2)
        XCTAssertEqual(other.taskCount, 1)
        XCTAssertEqual(other.recordCount, 1)
        XCTAssertEqual(other.totalDuration, 1800)
    }

    @MainActor
    func testDeletingFixedWorkspaceContentsLeavesOtherDestinationsUntouched() throws {
        let schema = Schema([
            LearningMaterialDocument.self,
            LearningProjectTask.self,
            StudyTimeRecord.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let projectID = UUID()
        let now = Date()

        let targetMaterial = LearningMaterialDocument(
            title: "考试资料",
            categoryRawValue: LearningMaterialCategory.exam.rawValue,
            originalFilename: "exam.pdf",
            localFilename: "missing-\(UUID().uuidString).pdf",
            contentTypeIdentifier: UTType.pdf.identifier
        )
        let otherMaterial = LearningMaterialDocument(
            title: "其他资料",
            categoryRawValue: LearningMaterialCategory.other.rawValue,
            originalFilename: "other.pdf",
            localFilename: "missing-\(UUID().uuidString).pdf",
            contentTypeIdentifier: UTType.pdf.identifier
        )
        let projectTask = LearningProjectTask(projectID: projectID.uuidString, title: "项目任务")
        let targetTask = LearningProjectTask(categoryRawValue: LearningMaterialCategory.exam.rawValue, title: "考试任务")
        let targetRecord = StudyTimeRecord(
            categoryRawValue: LearningMaterialCategory.exam.rawValue,
            startedAt: now,
            endedAt: now.addingTimeInterval(1800),
            content: "复习",
            location: "图书馆"
        )

        [targetMaterial, otherMaterial].forEach(context.insert)
        [projectTask, targetTask].forEach(context.insert)
        context.insert(targetRecord)
        try context.save()

        try LearningProjectContentRelocation.deleteContents(
            in: .fixed(.exam),
            materials: [targetMaterial, otherMaterial],
            tasks: [projectTask, targetTask],
            records: [targetRecord],
            modelContext: context
        )

        XCTAssertEqual(try context.fetch(FetchDescriptor<LearningMaterialDocument>()).map(\.id), [otherMaterial.id])
        XCTAssertEqual(try context.fetch(FetchDescriptor<LearningProjectTask>()).map(\.id), [projectTask.id])
        XCTAssertTrue(try context.fetch(FetchDescriptor<StudyTimeRecord>()).isEmpty)
    }

    func testLearningMaterialDisplayTypeUsesContentTypeAndFilename() {
        XCTAssertEqual(
            LearningMaterialDocument.displayType(contentTypeIdentifier: UTType.pdf.identifier, originalFilename: "exam.pdf"),
            "PDF"
        )
        XCTAssertEqual(
            LearningMaterialDocument.displayType(contentTypeIdentifier: UTType.data.identifier, originalFilename: "课件.pptx"),
            "PPT"
        )
        XCTAssertEqual(
            LearningMaterialDocument.displayType(contentTypeIdentifier: UTType.data.identifier, originalFilename: "成绩表.xlsx"),
            "表格"
        )
        XCTAssertEqual(
            LearningMaterialDocument.displayType(contentTypeIdentifier: UTType.data.identifier, originalFilename: "notes.unknown"),
            "文件"
        )
    }

    func testLearningMaterialLocalFilenameKeepsExtensionWhenPresent() throws {
        let uuid = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))

        XCTAssertEqual(
            LearningMaterialLocalFile.localFilename(originalExtension: ".pptx", uuid: uuid),
            "00000000-0000-0000-0000-000000000001.pptx"
        )
        XCTAssertEqual(
            LearningMaterialLocalFile.localFilename(originalExtension: "", uuid: uuid),
            "00000000-0000-0000-0000-000000000001"
        )
    }

    func testFitnessTestItemDefaultUnits() {
        XCTAssertEqual(FitnessTestItem.height.defaultUnit, .centimeter)
        XCTAssertEqual(FitnessTestItem.weight.defaultUnit, .kilogram)
        XCTAssertEqual(FitnessTestItem.vitalCapacity.defaultUnit, .milliliter)
        XCTAssertEqual(FitnessTestItem.sprint50m.defaultUnit, .second)
        XCTAssertEqual(FitnessTestItem.pullUps.defaultUnit, .count)
        XCTAssertEqual(FitnessTestItem.run800m.defaultUnit, .minuteSecond)
        XCTAssertEqual(FitnessTestItem.run1000m.defaultUnit, .minuteSecond)
    }

    func testFitnessTestMinuteSecondFormatting() {
        XCTAssertEqual(FitnessTestRecordFormatter.minuteSecondText(seconds: 214), "3分34秒")
        XCTAssertEqual(FitnessTestRecordFormatter.valueText(value: 486, unit: .minuteSecond), "8分6秒")
    }

    @MainActor
    func testFitnessTestRecordsSortByTestDateDescending() {
        let older = FitnessTestRecord(
            testedAt: reviewDate(2026, 5, 1),
            itemRawValue: FitnessTestItem.height.rawValue,
            value: 170,
            unitRawValue: FitnessTestUnit.centimeter.rawValue,
            createdAt: reviewDate(2026, 5, 1)
        )
        let newer = FitnessTestRecord(
            testedAt: reviewDate(2026, 5, 3),
            itemRawValue: FitnessTestItem.weight.rawValue,
            value: 60,
            unitRawValue: FitnessTestUnit.kilogram.rawValue,
            createdAt: reviewDate(2026, 5, 3)
        )
        let sameDateLaterCreated = FitnessTestRecord(
            testedAt: reviewDate(2026, 5, 3),
            itemRawValue: FitnessTestItem.sprint50m.rawValue,
            value: 8.2,
            unitRawValue: FitnessTestUnit.second.rawValue,
            createdAt: reviewDate(2026, 5, 4)
        )

        let sorted = FitnessTestRecordFormatter.sortedRecords([older, newer, sameDateLaterCreated])

        XCTAssertEqual(sorted.map(\.itemRawValue), [
            FitnessTestItem.sprint50m.rawValue,
            FitnessTestItem.weight.rawValue,
            FitnessTestItem.height.rawValue
        ])
    }
}

private var reviewTestCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}

private func makeReviewUserDefaults() -> UserDefaults {
    let suiteName = "leafy.tests.appStoreReview.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

private func reviewDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
    reviewTestCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
}

private func semesterDate(week: Int, day: Int, hour: Int, minute: Int) -> Date {
    let calendar = Calendar.current
    let dayOffset = (week - 1) * 7 + (day - 1)
    let date = calendar.date(byAdding: .day, value: dayOffset, to: SemesterConfig.startOfSemesterDate)!
    return calendar.date(
        bySettingHour: hour,
        minute: minute,
        second: 0,
        of: date
    )!
}

private func seedThreeReviewSyncDays(defaults: UserDefaults) {
    let notificationCenter = NotificationCenter()
    for day in 10...12 {
        AppStoreReviewCoordinator.recordSuccessfulSync(
            kind: .timetable,
            date: reviewDate(2026, 5, day),
            calendar: reviewTestCalendar,
            userDefaults: defaults,
            notificationCenter: notificationCenter
        )
    }
}

private final class FakeCommunityFeedCache: CommunityFeedCaching {
    var loadedPosts: [CommunityPost]
    private(set) var savedPostSnapshots: [[CommunityPost]] = []
    private var loadedPostsByKey: [String: [CommunityPost]]

    init(loadedPosts: [CommunityPost] = []) {
        self.loadedPosts = loadedPosts
        self.loadedPostsByKey = [CommunityFeedQuery.default.cacheKey: loadedPosts]
    }

    func load(query: CommunityFeedQuery) -> [CommunityPost] {
        loadedPostsByKey[query.cacheKey] ?? []
    }

    func save(_ posts: [CommunityPost], query: CommunityFeedQuery) {
        savedPostSnapshots.append(posts)
        loadedPosts = posts
        loadedPostsByKey[query.cacheKey] = posts
    }
}

private actor FakeCommunityRepository: CommunityRepository {
    private var postResponses: [[CommunityPost]]
    private var pollResponses: [[CommunityPoll]]
    private var fetchError: CommunityRepositoryTestError?
    private var shouldSuspendFetch = false
    private var suspendedFetchContinuation: CheckedContinuation<[CommunityPost], Error>?
    private var suspendedFetchWaiters: [CheckedContinuation<Void, Never>] = []
    private var likeResponses: [UUID: CommunityPost] = [:]
    private var favoriteResponses: [UUID: CommunityPost] = [:]
    private var votePollResponses: [UUID: CommunityPoll] = [:]
    private var pollFetchLimits: [Int] = []
    private var postFetchQueries: [CommunityFeedQuery] = []
    private var catalogSuggestionInputs: [CatalogSuggestionInput] = []

    init(postResponses: [[CommunityPost]] = [[]], pollResponses: [[CommunityPoll]] = [[]]) {
        self.postResponses = postResponses
        self.pollResponses = pollResponses
    }

    func setFetchError(_ error: CommunityRepositoryTestError?) {
        fetchError = error
    }

    func suspendFetches() {
        shouldSuspendFetch = true
    }

    func waitForSuspendedFetch() async {
        if suspendedFetchContinuation != nil { return }

        await withCheckedContinuation { continuation in
            suspendedFetchWaiters.append(continuation)
        }
    }

    func resumeSuspendedFetch(with posts: [CommunityPost]) {
        shouldSuspendFetch = false
        let continuation = suspendedFetchContinuation
        suspendedFetchContinuation = nil
        continuation?.resume(returning: posts)
    }

    func setLikeResponse(_ post: CommunityPost, for postID: UUID) {
        likeResponses[postID] = post
    }

    func setFavoriteResponse(_ post: CommunityPost, for postID: UUID) {
        favoriteResponses[postID] = post
    }

    func setVotePollResponse(_ poll: CommunityPoll, for pollID: UUID) {
        votePollResponses[pollID] = poll
    }

    func fetchedPollLimits() -> [Int] {
        pollFetchLimits
    }

    func fetchedPostQueries() -> [CommunityFeedQuery] {
        postFetchQueries
    }

    func submittedCatalogSuggestions() -> [CatalogSuggestionInput] {
        catalogSuggestionInputs
    }

    func ensureAnonymousSession() async throws {}

    func fetchPosts(query: CommunityFeedQuery) async throws -> [CommunityPost] {
        postFetchQueries.append(query)
        if let fetchError {
            throw fetchError
        }

        if shouldSuspendFetch {
            return try await withCheckedThrowingContinuation { continuation in
                suspendedFetchContinuation = continuation
                suspendedFetchWaiters.forEach { $0.resume() }
                suspendedFetchWaiters.removeAll()
            }
        }

        guard !postResponses.isEmpty else { return [] }
        guard postResponses.count > 1 else { return postResponses[0] }
        return postResponses.removeFirst()
    }

    func fetchPost(postID: UUID) async throws -> CommunityPost? {
        nil
    }

    func fetchComments(postID: UUID) async throws -> [CommunityComment] {
        []
    }

    func createComment(postID: UUID, body: String) async throws -> CommunityComment {
        throw CommunityRepositoryTestError.failure("未实现")
    }

    func togglePostLike(postID: UUID) async throws -> CommunityPost {
        guard let post = likeResponses[postID] else {
            throw CommunityRepositoryTestError.failure("缺少点赞返回")
        }

        return post
    }

    func togglePostFavorite(postID: UUID) async throws -> CommunityPost {
        guard let post = favoriteResponses[postID] else {
            throw CommunityRepositoryTestError.failure("缺少收藏返回")
        }

        return post
    }

    func reportPost(postID: UUID, reason: String) async throws {}

    func reportComment(commentID: UUID, reason: String) async throws {}

    func blockUser(userID: UUID, reason: String?) async throws {}

    func deletePost(postID: UUID) async throws {}

    func deleteComment(commentID: UUID) async throws {}

    func hasAcceptedCurrentTerms() async throws -> Bool {
        true
    }

    func createPost(input: CreatePostInput, images: [CommunityImageUpload]) async throws -> CommunityPost {
        throw CommunityRepositoryTestError.failure("未实现")
    }

    func fetchPolls(limit: Int) async throws -> [CommunityPoll] {
        pollFetchLimits.append(limit)
        guard !pollResponses.isEmpty else { return [] }
        guard pollResponses.count > 1 else { return pollResponses[0] }
        return pollResponses.removeFirst()
    }

    func fetchMyAuthoredPolls(limit: Int) async throws -> [CommunityPoll] {
        []
    }

    func fetchMyVotedPolls(limit: Int) async throws -> [CommunityPoll] {
        []
    }

    func createPoll(input: CreatePollInput) async throws -> CommunityPoll {
        throw CommunityRepositoryTestError.failure("未实现")
    }

    func votePoll(pollID: UUID, optionID: UUID) async throws -> CommunityPoll {
        guard let poll = votePollResponses[pollID] else {
            throw CommunityRepositoryTestError.failure("缺少投票返回")
        }

        return poll
    }

    func requestPollDeletion(pollID: UUID, reason: String?) async throws -> CommunityPoll {
        throw CommunityRepositoryTestError.failure("未实现")
    }

    func deleteOwnPoll(pollID: UUID) async throws {}

    func fetchTeacherRatingSummaries(search: String, limit: Int, offset: Int) async throws -> [TeacherRatingSummary] {
        []
    }

    func fetchCourseRatingSummaries(search: String, category: String?, limit: Int, offset: Int) async throws -> [CourseRatingSummary] {
        []
    }

    func fetchDishRatingSummaries(search: String, canteen: String?, location: String?, limit: Int, offset: Int) async throws -> [DishRatingSummary] {
        []
    }

    func submitCatalogSuggestion(input: CatalogSuggestionInput) async throws {
        catalogSuggestionInputs.append(input)
    }

    func fetchUnreadNotificationCount() async throws -> Int {
        0
    }
}

private enum CommunityRepositoryTestError: LocalizedError, Sendable {
    case failure(String)

    var errorDescription: String? {
        switch self {
        case .failure(let message):
            return message
        }
    }
}

private func makeWidgetSignatureArchive(
    generatedAt: Date = Date(timeIntervalSince1970: 1)
) -> LeafyWidgetSnapshotArchive {
    LeafyWidgetSnapshotArchive(
        generatedAt: generatedAt,
        snapshots: [
            LeafyWidgetDaySnapshot(
                dayOffset: 0,
                snapshot: LeafyWidgetSnapshot(
                    generatedAt: generatedAt,
                    status: .ready,
                    displayDate: "Today",
                    weekText: "Week",
                    dayText: "Mon",
                    headline: "今日课表",
                    subtitle: "下一节：A",
                    syncText: "最近同步：12:00",
                    lastFailureText: nil,
                    nextExamText: nil,
                    courses: [
                        LeafyWidgetCourse(
                            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                            title: "A",
                            timeText: "08:00",
                            periodText: "第 1 节",
                            locationText: "101",
                            teacherText: nil,
                            noteText: nil,
                            reminderText: nil,
                            accentIndex: 0,
                            isActive: false
                        )
                    ]
                )
            )
        ]
    )
}

private func timetableMetrics(
    width: CGFloat,
    height: CGFloat,
    dayCount: Int,
    controlScale: CGFloat = 1,
    allowsAgendaList: Bool = true
) -> TimetableResponsiveLayout.Metrics {
    TimetableResponsiveLayout.metrics(
        for: CGSize(width: width, height: height),
        dayCount: dayCount,
        totalClasses: 13,
        axisWidth: 34 * controlScale,
        headerHeight: 52 * controlScale,
        horizontalPadding: 4 * controlScale,
        daySpacing: 5 * controlScale,
        weekSpacing: 6 * controlScale,
        rowSpacing: 1.5 * controlScale,
        minimumRowHeight: 26 * controlScale,
        cardInset: 1.5 * controlScale,
        laneSpacing: 2 * controlScale,
        bottomClearance: 16 * controlScale,
        controlScale: controlScale,
        interPaneSpacing: 8,
        allowsAgendaList: allowsAgendaList
    )
}

private func makePaletteTestImage(colors: [UIColor], size: CGSize = CGSize(width: 80, height: 80)) -> UIImage {
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { context in
        guard !colors.isEmpty else {
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            return
        }

        let stripeWidth = size.width / CGFloat(colors.count)
        for (index, color) in colors.enumerated() {
            color.setFill()
            context.fill(CGRect(
                x: CGFloat(index) * stripeWidth,
                y: 0,
                width: index == colors.count - 1 ? size.width - CGFloat(index) * stripeWidth : stripeWidth,
                height: size.height
            ))
        }
    }
}

private func makeCommunityPost(
    id: UUID = UUID(),
    authorID: UUID = UUID(),
    title: String = "帖子",
    body: String = "正文",
    category: String? = "学习交流",
    commentCount: Int = 0,
    likeCount: Int = 0,
    status: String = "active",
    createdAt: String = "2026-05-14T00:00:00Z",
    viewerHasLiked: Bool = false,
    viewerHasFavorited: Bool = false,
    pin: CommunityPostPin? = nil
) -> CommunityPost {
    CommunityPost(
        id: id,
        authorID: authorID,
        title: title,
        body: body,
        category: category,
        isAnonymous: false,
        commentCount: commentCount,
        likeCount: likeCount,
        status: status,
        createdAt: createdAt,
        updatedAt: createdAt,
        viewerHasLiked: viewerHasLiked,
        viewerHasFavorited: viewerHasFavorited,
        pin: pin,
        author: nil,
        images: []
    )
}

private func makeCommunityPostPin(
    id: UUID = UUID(),
    postID: UUID,
    scope: CommunityPostPinScope = .global,
    category: String? = nil,
    priority: Int = 0,
    startsAt: String = "2026-05-14T00:00:00Z",
    endsAt: String? = nil,
    status: String = "active"
) -> CommunityPostPin {
    CommunityPostPin(
        id: id,
        postID: postID,
        scope: scope,
        category: category,
        priority: priority,
        startsAt: startsAt,
        endsAt: endsAt,
        status: status,
        reason: nil,
        createdAt: startsAt
    )
}

private func makeCommunityPoll(
    id: UUID = UUID(),
    authorID: UUID = UUID(),
    question: String = "投票",
    detail: String? = nil,
    status: String = "published",
    totalVoteCount: Int = 0,
    viewerOptionID: UUID? = nil,
    closesAt: String? = nil,
    createdAt: String = "2026-05-14T00:00:00Z",
    deletionStatus: String = "none",
    options: [CommunityPollOption]? = nil
) -> CommunityPoll {
    let resolvedOptions = options ?? [
        makeCommunityPollOption(pollID: id, text: "选项 A"),
        makeCommunityPollOption(pollID: id, text: "选项 B", sortOrder: 1)
    ]
    return CommunityPoll(
        id: id,
        authorID: authorID,
        question: question,
        detail: detail,
        status: status,
        totalVoteCount: totalVoteCount,
        viewerOptionID: viewerOptionID,
        closesAt: closesAt,
        deletionStatus: deletionStatus,
        createdAt: createdAt,
        updatedAt: createdAt,
        author: nil,
        options: resolvedOptions
    )
}

private func makeCommunityPollOption(
    id: UUID = UUID(),
    pollID: UUID = UUID(),
    text: String = "选项",
    sortOrder: Int = 0,
    voteCount: Int = 0,
    createdAt: String = "2026-05-14T00:00:00Z"
) -> CommunityPollOption {
    CommunityPollOption(
        id: id,
        pollID: pollID,
        text: text,
        sortOrder: sortOrder,
        voteCount: voteCount,
        createdAt: createdAt
    )
}

final class PerformanceProjectionTests: XCTestCase {
    @MainActor
    func testConversationProjectionFiltersOnceAndIndexesActions() {
        let selectedID = UUID()
        let otherID = UUID()
        let selected = CampusAIConversation(id: selectedID, title: "Selected")
        let other = CampusAIConversation(id: otherID, title: "Other")
        let firstMessage = CampusAIMessage(
            conversationID: selectedID.uuidString,
            roleRawValue: CampusAIMessageRole.user.rawValue,
            text: "Question"
        )
        let secondMessage = CampusAIMessage(
            conversationID: selectedID.uuidString,
            roleRawValue: CampusAIMessageRole.assistant.rawValue,
            text: "Answer"
        )
        let unrelatedMessage = CampusAIMessage(
            conversationID: otherID.uuidString,
            roleRawValue: CampusAIMessageRole.user.rawValue,
            text: "Other"
        )
        let indexedAction = CampusAIActionRecord(
            conversationID: selectedID.uuidString,
            messageID: secondMessage.id.uuidString,
            kindRawValue: CampusAIActionKind.createCountdown.rawValue,
            title: "Countdown",
            detail: "Detail",
            payloadJSON: "{}",
            statusRawValue: CampusAIActionStatus.pending.rawValue
        )
        let unrelatedAction = CampusAIActionRecord(
            conversationID: otherID.uuidString,
            messageID: unrelatedMessage.id.uuidString,
            kindRawValue: CampusAIActionKind.createCountdown.rawValue,
            title: "Other",
            detail: "Detail",
            payloadJSON: "{}",
            statusRawValue: CampusAIActionStatus.pending.rawValue
        )

        let projection = CampusAIConversationProjection(
            selectedConversationID: selectedID,
            conversations: [other, selected],
            messages: [firstMessage, unrelatedMessage, secondMessage],
            actionRecords: [unrelatedAction, indexedAction]
        )

        XCTAssertEqual(projection.conversation?.id, selectedID)
        XCTAssertEqual(projection.messages.map(\.id), [firstMessage.id, secondMessage.id])
        XCTAssertEqual(projection.actionRecords(for: firstMessage).count, 0)
        XCTAssertEqual(projection.actionRecords(for: secondMessage).map(\.id), [indexedAction.id])
    }

    @MainActor
    func testChatSessionKeepsTransientStreamingTextOutOfPersistentMessage() {
        let session = CampusAIChatSession()
        let conversationID = UUID()
        let messageID = UUID()

        session.markStreaming(conversationID: conversationID, messageID: messageID)
        XCTAssertEqual(session.append(delta: "Leafy", messageID: messageID), "Leafy")
        XCTAssertEqual(session.append(delta: " AI", messageID: messageID), "Leafy AI")
        XCTAssertEqual(session.displayText(for: messageID), "Leafy AI")

        session.cancel()
        XCTAssertNil(session.displayText(for: messageID))
        XCTAssertEqual(session.streamingText, "")
        XCTAssertFalse(session.isSending)
    }

    @MainActor
    func testRatingCatalogWorkspaceLoadsEachSectionOnceOnDemand() {
        let workspace = RatingCatalogWorkspace()

        XCTAssertTrue(workspace.teachers.beginInitialLoad())
        XCTAssertFalse(workspace.teachers.beginInitialLoad())
        XCTAssertFalse(workspace.courses.hasStartedInitialLoad)
        XCTAssertFalse(workspace.dishes.hasStartedInitialLoad)

        XCTAssertTrue(workspace.courses.beginInitialLoad())
        XCTAssertTrue(workspace.teachers.hasStartedInitialLoad)
        XCTAssertTrue(workspace.courses.hasStartedInitialLoad)
        XCTAssertFalse(workspace.dishes.hasStartedInitialLoad)
    }

    func testMasonryProjectionPreservesAlternatingOrder() {
        let columns = CommunityMasonryColumns(items: Array(0..<7))

        XCTAssertEqual(columns.left, [0, 2, 4, 6])
        XCTAssertEqual(columns.right, [1, 3, 5])
    }

    func testCompactTimestampFormatterKeepsExistingFeedFormat() throws {
        let calendar = Calendar.current
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 22, hour: 9, minute: 5)))

        XCTAssertEqual(CommunityCompactTimestampFormatter.string(from: date), "7/22 09:05")
    }

    @MainActor
    func testTimetableCacheAcceptsOnePrebuiltRenderInput() {
        let course = Course(
            courseName: "A",
            teacher: "T",
            room: "101",
            location: "",
            dayOfWeek: 1,
            weeks: [1],
            duration: [1]
        )
        let input = TimetableRenderInput(
            courses: [course],
            notes: [],
            occurrenceNotes: [],
            cellReminders: [],
            hidesWeekends: false
        )
        let cache = TimetableGridSnapshotCache()

        let first = cache.snapshot(input: input, totalWeeks: 2)
        let second = cache.snapshot(input: input, totalWeeks: 2)

        XCTAssertEqual(cache.buildCount, 1)
        XCTAssertEqual(first.layouts(day: 1, week: 1).map(\.course.courseName), ["A"])
        XCTAssertEqual(second.layouts(day: 1, week: 1).map(\.course.courseName), ["A"])
    }
}
