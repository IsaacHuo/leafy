import SwiftData
import SwiftSoup
import SwiftUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct TimetableLayoutMetrics: Equatable {
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

@MainActor
final class TimetableLayoutMetricsCache {
    private var key: TimetableLayoutMetricsCacheKey?
    private var cachedMetrics: TimetableLayoutMetrics?

    func metrics(
        size: CGSize,
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
        allowsAgendaList: Bool
    ) -> TimetableLayoutMetrics {
        let key = TimetableLayoutMetricsCacheKey(
            width: size.width,
            height: size.height,
            dayCount: dayCount,
            totalClasses: totalClasses,
            axisWidth: axisWidth,
            headerHeight: headerHeight,
            horizontalPadding: horizontalPadding,
            daySpacing: daySpacing,
            weekSpacing: weekSpacing,
            rowSpacing: rowSpacing,
            minimumRowHeight: minimumRowHeight,
            cardInset: cardInset,
            laneSpacing: laneSpacing,
            bottomClearance: bottomClearance,
            controlScale: controlScale,
            interPaneSpacing: interPaneSpacing,
            allowsAgendaList: allowsAgendaList
        )

        if self.key == key, let cachedMetrics {
            return cachedMetrics
        }

        let responsiveMetrics = TimetableResponsiveLayout.metrics(
            for: size,
            dayCount: dayCount,
            totalClasses: totalClasses,
            axisWidth: axisWidth,
            headerHeight: headerHeight,
            horizontalPadding: horizontalPadding,
            daySpacing: daySpacing,
            weekSpacing: weekSpacing,
            rowSpacing: rowSpacing,
            minimumRowHeight: minimumRowHeight,
            cardInset: cardInset,
            laneSpacing: laneSpacing,
            bottomClearance: bottomClearance,
            controlScale: controlScale,
            interPaneSpacing: interPaneSpacing,
            allowsAgendaList: allowsAgendaList
        )

        let metrics = TimetableLayoutMetrics(
            rowHeight: responsiveMetrics.rowHeight,
            rowSpacing: responsiveMetrics.rowSpacing,
            cardInset: responsiveMetrics.cardInset,
            laneSpacing: responsiveMetrics.laneSpacing,
            dayColumnWidth: responsiveMetrics.dayColumnWidth,
            daySpacing: responsiveMetrics.daySpacing,
            weekSpacing: responsiveMetrics.weekSpacing,
            gridHeight: responsiveMetrics.gridHeight,
            allowsVerticalScroll: responsiveMetrics.allowsVerticalScroll,
            weekStride: responsiveMetrics.weekStride,
            containerWidth: responsiveMetrics.containerWidth,
            containerHeight: responsiveMetrics.containerHeight,
            horizontalPadding: responsiveMetrics.horizontalPadding,
            mode: responsiveMetrics.mode
        )
        self.key = key
        cachedMetrics = metrics
        return metrics
    }
}

struct TimetableLayoutMetricsCacheKey: Equatable {
    let width: CGFloat
    let height: CGFloat
    let dayCount: Int
    let totalClasses: Int
    let axisWidth: CGFloat
    let headerHeight: CGFloat
    let horizontalPadding: CGFloat
    let daySpacing: CGFloat
    let weekSpacing: CGFloat
    let rowSpacing: CGFloat
    let minimumRowHeight: CGFloat
    let cardInset: CGFloat
    let laneSpacing: CGFloat
    let bottomClearance: CGFloat
    let controlScale: CGFloat
    let interPaneSpacing: CGFloat
    let allowsAgendaList: Bool
}

struct TimetableDayMetadata: Hashable {
    let week: Int
    let day: Int
    let date: Date
    let isToday: Bool
    let dayTitle: String
    let numericDateText: String
    let chineseDateText: String
    let event: SchoolCalendarEvent?
    let countdowns: [TimetableCountdownProjection]
    let exams: [TimetableExamProjection]
    let projectionSignature: TimetableScheduleProjectionSignature

    var hasExam: Bool {
        !exams.isEmpty
    }
}

@MainActor
final class TimetableDayMetadataCache {
    private var identity: TimetableDayMetadataCacheIdentity?
    private var metadataByDay: [TimetableDayMetadataCacheKey: TimetableDayMetadata] = [:]

    func metadata(
        day: Int,
        week: Int,
        semesterStartDate: Date,
        calendarEvents: [SchoolCalendarEvent],
        scheduleSnapshot: TimetableScheduleProjectionSnapshot,
        language: AppLanguagePreference
    ) -> TimetableDayMetadata {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let identity = TimetableDayMetadataCacheIdentity(
            semesterStartDate: calendar.startOfDay(for: semesterStartDate),
            calendarEvents: calendarEvents,
            scheduleSignature: scheduleSnapshot.signature,
            language: language,
            today: today
        )
        if self.identity != identity {
            self.identity = identity
            metadataByDay.removeAll(keepingCapacity: true)
        }

        let key = TimetableDayMetadataCacheKey(week: week, day: day)
        if let metadata = metadataByDay[key] {
            return metadata
        }

        var components = DateComponents()
        components.day = (week - 1) * 7 + (day - 1)
        let date = calendar.date(byAdding: components, to: semesterStartDate) ?? Date()
        let numericComponents = calendar.dateComponents([.month, .day], from: date)
        let metadata = TimetableDayMetadata(
            week: week,
            day: day,
            date: date,
            isToday: calendar.isDate(date, inSameDayAs: today),
            dayTitle: language.weekdayTitle(for: day),
            numericDateText: String(format: "%02d-%02d", numericComponents.month ?? 1, numericComponents.day ?? 1),
            chineseDateText: DateFormatters.chineseDay.string(from: date),
            event: AcademicCalendarEvents.event(on: date, calendar: calendar),
            countdowns: scheduleSnapshot.countdowns(week: week, day: day),
            exams: scheduleSnapshot.exams(week: week, day: day),
            projectionSignature: scheduleSnapshot.signature
        )
        metadataByDay[key] = metadata
        return metadata
    }
}

struct TimetableDayMetadataCacheIdentity: Equatable {
    let semesterStartDate: Date
    let calendarEvents: [SchoolCalendarEvent]
    let scheduleSignature: TimetableScheduleProjectionSignature
    let language: AppLanguagePreference
    let today: Date
}

struct TimetableDayMetadataCacheKey: Hashable {
    let week: Int
    let day: Int
}

@MainActor
final class TimetableAgendaItemCache {
    private var identity: TimetableAgendaItemCacheIdentity?
    private var itemsByDay: [TimetableDayMetadataCacheKey: [TimetableAgendaItem]] = [:]

    func items(
        metadata: TimetableDayMetadata,
        gridSnapshot: TimetableGridSnapshot,
        totalClasses: Int
    ) -> [TimetableAgendaItem] {
        let identity = TimetableAgendaItemCacheIdentity(
            gridSignature: gridSnapshot.signature,
            totalWeeks: gridSnapshot.totalWeeks,
            projectionSignature: metadata.projectionSignature,
            totalClasses: totalClasses
        )
        if self.identity != identity {
            self.identity = identity
            itemsByDay.removeAll(keepingCapacity: true)
        }

        let key = TimetableDayMetadataCacheKey(week: metadata.week, day: metadata.day)
        if let items = itemsByDay[key] {
            return items
        }

        var items = gridSnapshot.layouts(day: metadata.day, week: metadata.week).map { layout in
            TimetableAgendaItem.course(
                layout.course,
                week: metadata.week,
                day: metadata.day,
                date: metadata.date
            )
        }

        items.append(contentsOf: metadata.countdowns.map { projection in
            TimetableAgendaItem.countdown(
                projection,
                week: metadata.week,
                day: metadata.day,
                date: metadata.date
            )
        })

        items.append(contentsOf: metadata.exams.map { projection in
            TimetableAgendaItem.exam(
                projection,
                week: metadata.week,
                day: metadata.day,
                date: metadata.date
            )
        })

        for period in 1...totalClasses {
            guard let reminder = gridSnapshot.cellReminder(week: metadata.week, day: metadata.day, period: period) else { continue }
            items.append(
                .cellReminder(
                    reminder,
                    week: metadata.week,
                    day: metadata.day,
                    date: metadata.date
                )
            )
        }

        let sortedItems = items.sorted()
        itemsByDay[key] = sortedItems
        return sortedItems
    }
}

struct TimetableAgendaItemCacheIdentity: Equatable {
    let gridSignature: TimetableGridInputSignature
    let totalWeeks: Int
    let projectionSignature: TimetableScheduleProjectionSignature
    let totalClasses: Int
}

struct TimetableBackgroundImageLayer: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.leafyThemeColorPreference) private var themeColorPreference

    let image: UIImage
    let displayMode: TimetableBackgroundDisplayMode
    let imageOpacity: Double
    let blurRadius: Double
    let overlayOpacity: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: displayMode.contentMode)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                    .blur(radius: blurRadius)
                    .opacity(imageOpacity)

                maskColor
                    .opacity(overlayOpacity)

                AppTheme.pageGradient(for: themeColorPreference)
                    .opacity(colorScheme == .dark ? 0.18 : 0.28)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
    }

    private var maskColor: Color {
        colorScheme == .dark ? .black : AppTheme.background
    }
}

struct TimetableDaySelection: Identifiable {
    let week: Int
    let day: Int
    let date: Date

    var id: String {
        "\(week)-\(day)"
    }
}

struct SelectedCourseContext: Identifiable {
    let course: Course
    let week: Int
    let day: Int
    let date: Date

    var id: String {
        "\(course.id.uuidString)-\(week)-\(day)"
    }
}

struct CourseProgressOccurrence: Hashable, Comparable {
    let week: Int
    let dayOfWeek: Int
    let firstPeriod: Int

    static func < (lhs: CourseProgressOccurrence, rhs: CourseProgressOccurrence) -> Bool {
        if lhs.week != rhs.week { return lhs.week < rhs.week }
        if lhs.dayOfWeek != rhs.dayOfWeek { return lhs.dayOfWeek < rhs.dayOfWeek }
        return lhs.firstPeriod < rhs.firstPeriod
    }
}

struct TimetableCellReminderContext: Identifiable {
    let week: Int
    let day: Int
    let period: Int
    let date: Date
    let occupiedPeriods: Set<Int>
    let totalPeriods: Int
    let reminder: TimetableCellReminder?
    var allowsDateSelection = false

    var id: String {
        "\(TimetableCellReminder.cellKey(week: week, dayOfWeek: day, period: period))-\(reminder?.id.uuidString ?? "new")"
    }
}

enum TimetableAgendaItemKind {
    case course(Course)
    case cellReminder(TimetableCellReminder, period: Int)
    case countdown(TimetableCountdownProjection)
    case exam(TimetableExamProjection)
}

struct TimetableAgendaItem: Identifiable {
    let id: String
    let week: Int
    let day: Int
    let date: Date
    let sortPeriod: Int
    let title: String
    let detail: String
    let periodText: String
    let timeText: String
    let systemImage: String
    let tint: Color
    let kind: TimetableAgendaItemKind

    static func course(_ course: Course, week: Int, day: Int, date: Date) -> TimetableAgendaItem {
        let periods = course.duration.sorted()
        let startPeriod = periods.first ?? 1
        let endPeriod = periods.last ?? startPeriod
        let startText = TimetablePeriodSchedule.slot(for: startPeriod)?.startText
        let endText = TimetablePeriodSchedule.slot(for: endPeriod)?.endText

        return TimetableAgendaItem(
            id: "course-\(course.id.uuidString)-\(week)-\(day)",
            week: week,
            day: day,
            date: date,
            sortPeriod: startPeriod,
            title: course.displayCourseName,
            detail: course.timetableCardLocationText,
            periodText: periodRangeText(start: startPeriod, end: endPeriod),
            timeText: timeRangeText(start: startText, end: endText),
            systemImage: "book.closed.fill",
            tint: AppTheme.accent,
            kind: .course(course)
        )
    }

    static func cellReminder(_ reminder: TimetableCellReminder, week: Int, day: Int, date: Date) -> TimetableAgendaItem {
        TimetableAgendaItem(
            id: "reminder-\(reminder.id.uuidString)-\(week)-\(day)",
            week: week,
            day: day,
            date: date,
            sortPeriod: reminder.period,
            title: reminder.title,
            detail: cellReminderDetail(reminder),
            periodText: periodRangeText(start: reminder.displayStartPeriod, end: reminder.displayEndPeriod),
            timeText: cellReminderTimeText(reminder),
            systemImage: "bell.fill",
            tint: AppTheme.accentSecondary,
            kind: .cellReminder(reminder, period: reminder.period)
        )
    }

    static func countdown(_ projection: TimetableCountdownProjection, week: Int, day: Int, date: Date) -> TimetableAgendaItem {
        TimetableAgendaItem(
            id: "countdown-\(projection.id)",
            week: week,
            day: day,
            date: date,
            sortPeriod: projection.period,
            title: projection.title,
            detail: DateFormatters.headerWithTime.string(from: projection.targetDate),
            periodText: "\(projection.period)",
            timeText: TimetablePeriodSchedule.slot(for: projection.period)?.startText ?? "",
            systemImage: "timer",
            tint: AppTheme.warning,
            kind: .countdown(projection)
        )
    }

    static func exam(_ projection: TimetableExamProjection, week: Int, day: Int, date: Date) -> TimetableAgendaItem {
        TimetableAgendaItem(
            id: "exam-\(projection.id)",
            week: week,
            day: day,
            date: date,
            sortPeriod: projection.period,
            title: projection.name,
            detail: projection.location.isEmpty ? projection.startText : "\(projection.startText) \(projection.location)",
            periodText: "\(projection.period)",
            timeText: projection.startText,
            systemImage: "exclamationmark.triangle.fill",
            tint: AppTheme.warning,
            kind: .exam(projection)
        )
    }

    private static func periodRangeText(start: Int, end: Int) -> String {
        start == end ? "\(start)" : "\(start)-\(end)"
    }

    private static func timeRangeText(start: String?, end: String?) -> String {
        switch (start, end) {
        case let (start?, end?):
            return "\(start)\n\(end)"
        case let (start?, nil):
            return start
        default:
            return ""
        }
    }

    private static func cellReminderDetail(_ reminder: TimetableCellReminder) -> String {
        var parts: [String] = []
        let location = reminder.locationText
        if !location.isEmpty {
            parts.append(location)
        }
        parts.append(reminder.minutesBefore > 0 ? L10n.text("%d 分钟前提醒", reminder.minutesBefore) : L10n.text("不提醒"))
        return parts.joined(separator: " · ")
    }

    private static func cellReminderTimeText(_ reminder: TimetableCellReminder) -> String {
        if let startDate = reminder.resolvedStartDate,
           let endDate = reminder.resolvedEndDate,
           endDate > startDate {
            return "\(DateFormatters.timeOnly.string(from: startDate))\n\(DateFormatters.timeOnly.string(from: endDate))"
        }

        let startText = TimetablePeriodSchedule.slot(for: reminder.displayStartPeriod)?.startText
        let endText = TimetablePeriodSchedule.slot(for: reminder.displayEndPeriod)?.endText
        return timeRangeText(start: startText, end: endText)
    }
}

extension TimetableAgendaItem: Comparable {
    static func < (lhs: TimetableAgendaItem, rhs: TimetableAgendaItem) -> Bool {
        if lhs.sortPeriod != rhs.sortPeriod {
            return lhs.sortPeriod < rhs.sortPeriod
        }
        return lhs.title.localizedCompare(rhs.title) == .orderedAscending
    }

    static func == (lhs: TimetableAgendaItem, rhs: TimetableAgendaItem) -> Bool {
        lhs.id == rhs.id
    }
}

extension Course {
    var normalizedCourseNameForProgress: String {
        courseName.normalizedCourseProgressKey
    }

    var firstPeriodForProgress: Int {
        duration.sorted().first ?? 0
    }
}

extension String {
    var normalizedCourseProgressKey: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
    }
}

struct TimetableWeather {
    let temperature: Double
    let condition: String

    var displayText: String {
        "\(Int(temperature.rounded()))° \(condition)"
    }
}
