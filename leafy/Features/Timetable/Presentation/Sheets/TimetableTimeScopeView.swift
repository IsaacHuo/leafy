import SwiftData
import SwiftSoup
import SwiftUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct TimetableTimeScopeSnapshot: Equatable {
    let referenceDate: Date
    let currentWeek: Int
    let weekStartDate: Date
    let weekEndDate: Date
    let displayedMonthDate: Date
    let monthTitle: String
    let weekdaySymbols: [String]
    let monthDays: [TimetableTimeScopeDay]
    let yearMonths: [TimetableTimeScopeMonthMark]
    let currentDateText: String
    let weekRangeText: String
    let weekInMonthText: String
    let nextHolidayTitle: String
    let nextHolidayCountdownText: String
    let summerStartDate: Date
    let summerStartText: String
    let summerCountdownText: String
    let winterCountdownText: String

    static func make(
        currentWeek: Int,
        referenceDate: Date,
        displayedMonthDate requestedDisplayedMonthDate: Date? = nil,
        language: AppLanguagePreference,
        calendar baseCalendar: Calendar = .current
    ) -> TimetableTimeScopeSnapshot {
        var calendar = baseCalendar
        calendar.firstWeekday = 2

        let today = calendar.startOfDay(for: referenceDate)
        let weekStart = calendar.startOfDay(for: calendar.date(
            byAdding: .day,
            value: max(currentWeek - 1, 0) * 7,
            to: SemesterConfig.startOfSemesterDate
        ) ?? SemesterConfig.startOfSemesterDate)
        let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        let displayedMonthDate = requestedDisplayedMonthDate.map { calendar.startOfDay(for: $0) } ?? weekStart
        let monthInterval = calendar.dateInterval(of: .month, for: displayedMonthDate)
        let monthStart = monthInterval?.start ?? displayedMonthDate
        let leadingDays = (calendar.component(.weekday, from: monthStart) + 5) % 7
        let gridStart = calendar.date(byAdding: .day, value: -leadingDays, to: monthStart) ?? monthStart
        let monthDays = (0..<42).compactMap { offset -> TimetableTimeScopeDay? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: gridStart) else { return nil }
            let startOfDay = calendar.startOfDay(for: date)
            let event = AcademicCalendarEvents.event(on: startOfDay, calendar: calendar)
            return TimetableTimeScopeDay(
                date: startOfDay,
                dayNumber: calendar.component(.day, from: startOfDay),
                isInDisplayedMonth: calendar.isDate(startOfDay, equalTo: displayedMonthDate, toGranularity: .month),
                isToday: calendar.isDate(startOfDay, inSameDayAs: today),
                isInCurrentWeek: startOfDay >= weekStart && startOfDay <= weekEnd,
                event: event
            )
        }

        let weekMonthStart = calendar.dateInterval(of: .month, for: weekStart)?.start ?? weekStart
        let weekMonthLeadingDays = (calendar.component(.weekday, from: weekMonthStart) + 5) % 7
        let weekRow = max(1, ((calendar.component(.day, from: weekStart) + weekMonthLeadingDays - 1) / 7) + 1)
        let summerStart = calendar.startOfDay(for: calendar.date(
            byAdding: .day,
            value: SemesterConfig.supportedWeeks * 7,
            to: SemesterConfig.startOfSemesterDate
        ) ?? SemesterConfig.startOfSemesterDate)
        let yearMonths = makeYearMonths(
            displayedMonthDate: displayedMonthDate,
            semesterStart: calendar.startOfDay(for: SemesterConfig.startOfSemesterDate),
            summerStart: summerStart,
            calendar: calendar,
            language: language
        )

        let nextHoliday = AcademicCalendarEvents.nextNationalHoliday(from: today, calendar: calendar)

        let nextHolidayTitle = nextHoliday?.title ?? L10n.text("暂无已配置假期", language: language)
        let nextHolidayCountdownText: String = {
            guard let startDate = nextHoliday?.startDate else {
                return L10n.text("校历更新后显示", language: language)
            }
            return countdownText(
                prefix: nextHolidayTitle,
                targetDate: startDate,
                today: today,
                calendar: calendar,
                language: language
            )
        }()

        return TimetableTimeScopeSnapshot(
            referenceDate: today,
            currentWeek: currentWeek,
            weekStartDate: weekStart,
            weekEndDate: weekEnd,
            displayedMonthDate: displayedMonthDate,
            monthTitle: monthTitle(for: displayedMonthDate, calendar: calendar, language: language),
            weekdaySymbols: ["一", "二", "三", "四", "五", "六", "日"],
            monthDays: monthDays,
            yearMonths: yearMonths,
            currentDateText: currentDateText(for: today, language: language),
            weekRangeText: shortDateRange(from: weekStart, to: weekEnd, language: language),
            weekInMonthText: L10n.text("本周位于本月第 %d 周", language: language, weekRow),
            nextHolidayTitle: nextHolidayTitle,
            nextHolidayCountdownText: nextHolidayCountdownText,
            summerStartDate: summerStart,
            summerStartText: shortDate(for: summerStart, language: language),
            summerCountdownText: countdownText(
                prefix: L10n.text("暑假", language: language),
                targetDate: summerStart,
                today: today,
                calendar: calendar,
                language: language
            ),
            winterCountdownText: L10n.text("寒假：下学期校历更新后显示", language: language)
        )
    }

    private static func makeYearMonths(
        displayedMonthDate: Date,
        semesterStart: Date,
        summerStart: Date,
        calendar: Calendar,
        language: AppLanguagePreference
    ) -> [TimetableTimeScopeMonthMark] {
        let year = calendar.component(.year, from: displayedMonthDate)
        let summerStartYear = calendar.component(.year, from: summerStart)
        let summerVisualEnd: Date = {
            if summerStartYear == year,
               let septemberStart = calendar.date(from: DateComponents(year: year, month: 9, day: 1)),
               summerStart < septemberStart {
                return septemberStart
            }
            return calendar.date(byAdding: .day, value: 45, to: summerStart) ?? summerStart
        }()

        return (1...12).compactMap { month -> TimetableTimeScopeMonthMark? in
            guard let start = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
                  let end = calendar.date(byAdding: .month, value: 1, to: start)
            else { return nil }

            return TimetableTimeScopeMonthMark(
                month: month,
                label: "\(month)",
                isDisplayedMonth: calendar.isDate(start, equalTo: displayedMonthDate, toGranularity: .month),
                isInSemester: intervalsOverlap(start, end, semesterStart, summerStart),
                isInSummer: summerStartYear == year && intervalsOverlap(start, end, summerStart, summerVisualEnd)
            )
        }
    }

    private static func intervalsOverlap(_ firstStart: Date, _ firstEnd: Date, _ secondStart: Date, _ secondEnd: Date) -> Bool {
        firstStart < secondEnd && secondStart < firstEnd
    }

    private static func countdownText(
        prefix: String,
        targetDate: Date,
        today: Date,
        calendar: Calendar,
        language: AppLanguagePreference
    ) -> String {
        let target = calendar.startOfDay(for: targetDate)
        let days = calendar.dateComponents([.day], from: today, to: target).day ?? 0
        if days < 0 {
            return L10n.text("%@已开始", language: language, prefix)
        }
        if days == 0 {
            return L10n.text("%@今天开始", language: language, prefix)
        }
        return L10n.text("%@还有 %d 天", language: language, prefix, days)
    }

    private static func currentDateText(for date: Date, language: AppLanguagePreference) -> String {
        DateFormatters.fullDateWithWeekday.string(from: date)
    }

    private static func monthTitle(for date: Date, calendar: Calendar, language: AppLanguagePreference) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language.localeIdentifier)
        formatter.dateFormat = "yyyy年M月"
        formatter.calendar = calendar
        return formatter.string(from: date)
    }

    private static func shortDateRange(from start: Date, to end: Date, language: AppLanguagePreference) -> String {
        "\(shortDate(for: start, language: language)) - \(shortDate(for: end, language: language))"
    }

    private static func shortDate(for date: Date, language: AppLanguagePreference) -> String {
        DateFormatters.chineseDay.string(from: date)
    }
}

struct TimetableTimeScopeDay: Identifiable, Equatable {
    let date: Date
    let dayNumber: Int
    let isInDisplayedMonth: Bool
    let isToday: Bool
    let isInCurrentWeek: Bool
    let event: SchoolCalendarEvent?

    var id: TimeInterval {
        date.timeIntervalSince1970
    }
}

struct TimetableTimeScopeMonthMark: Identifiable, Equatable {
    let month: Int
    let label: String
    let isDisplayedMonth: Bool
    let isInSemester: Bool
    let isInSummer: Bool

    var id: Int { month }
}

struct TimetableTimeScopeView: View {
    @Environment(\.leafyControlScale) private var leafyControlScale
    @Environment(\.leafyThemeColorPreference) private var themeColorPreference
    @Environment(\.leafyLanguage) private var leafyLanguage

    let snapshot: TimetableTimeScopeSnapshot
    let onDismiss: () -> Void

    @State private var hasAppeared = false
    @State private var isGatherOverlayVisible = true
    @State private var displayedSnapshot: TimetableTimeScopeSnapshot
    @State private var monthTransitionDirection = 1

    init(
        snapshot: TimetableTimeScopeSnapshot,
        onDismiss: @escaping () -> Void
    ) {
        self.snapshot = snapshot
        self.onDismiss = onDismiss
        _displayedSnapshot = State(initialValue: snapshot)
    }

    var body: some View {
        ZStack {
            LeafyPageBackground()
                .ignoresSafeArea()

            AppTheme.background.opacity(0.82)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: AppSpacing.card) {
                    header
                    monthCalendar
                    yearStrip
                    summaryCards
                    winterNote
                }
                .padding(.horizontal, AppSpacing.page)
                .padding(.top, 28 * leafyControlScale)
                .padding(.bottom, 48 * leafyControlScale)
            }

            if isGatherOverlayVisible {
                TimetableTimeScopeCornerGatherOverlay(isGathered: hasAppeared)
                    .transition(.opacity)
            }
        }
        .onChange(of: leafyLanguage) { _, newLanguage in
            displayedSnapshot = makeDisplayedSnapshot(
                displayedMonthDate: displayedSnapshot.displayedMonthDate,
                language: newLanguage
            )
        }
        .onChange(of: snapshot) { _, newSnapshot in
            displayedSnapshot = makeDisplayedSnapshot(
                displayedMonthDate: displayedSnapshot.displayedMonthDate,
                language: leafyLanguage,
                baseSnapshot: newSnapshot
            )
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.42)) {
                hasAppeared = true
            }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(520))
                withAnimation(.easeOut(duration: 0.16)) {
                    isGatherOverlayVisible = false
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: AppSpacing.card) {
            Button(action: onDismiss) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18 * leafyControlScale, weight: .bold))
                    .foregroundStyle(AppTheme.accentEmphasis(for: themeColorPreference))
                    .frame(width: 44 * leafyControlScale, height: 44 * leafyControlScale)
                    .contentShape(Circle())
                    .leafyGlassSurface(in: Circle(), isInteractive: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("返回课表")

            VStack(alignment: .leading, spacing: 4 * leafyControlScale) {
                Text("时间视角")
                    .font(.system(size: 26 * leafyControlScale, weight: .bold))
                    .foregroundStyle(AppTheme.primaryText)
                Text(displayedSnapshot.currentDateText)
                    .font(.system(size: 13 * leafyControlScale, weight: .medium))
                    .foregroundStyle(AppTheme.secondaryText)
            }

            Spacer(minLength: AppSpacing.compact)
        }
    }

    private var summaryCards: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: AppSpacing.compact) {
                scopeMetricCard(
                    icon: "calendar.day.timeline.left",
                    title: "第 \(displayedSnapshot.currentWeek) 周",
                    value: displayedSnapshot.weekInMonthText,
                    detail: displayedSnapshot.weekRangeText,
                    tint: AppTheme.accent(for: themeColorPreference)
                )
                scopeMetricCard(
                    icon: "sparkles",
                    title: displayedSnapshot.nextHolidayTitle,
                    value: displayedSnapshot.nextHolidayCountdownText,
                    detail: "下一个假期",
                    tint: AppTheme.warning
                )
                scopeMetricCard(
                    icon: "sun.max.fill",
                    title: "暑假",
                    value: displayedSnapshot.summerCountdownText,
                    detail: "\(displayedSnapshot.summerStartText) 开始",
                    tint: Color.yellow
                )
            }

            VStack(spacing: AppSpacing.compact) {
                scopeMetricCard(
                    icon: "calendar.day.timeline.left",
                    title: "第 \(displayedSnapshot.currentWeek) 周",
                    value: displayedSnapshot.weekInMonthText,
                    detail: displayedSnapshot.weekRangeText,
                    tint: AppTheme.accent(for: themeColorPreference)
                )
                scopeMetricCard(
                    icon: "sparkles",
                    title: displayedSnapshot.nextHolidayTitle,
                    value: displayedSnapshot.nextHolidayCountdownText,
                    detail: "下一个假期",
                    tint: AppTheme.warning
                )
                scopeMetricCard(
                    icon: "sun.max.fill",
                    title: "暑假",
                    value: displayedSnapshot.summerCountdownText,
                    detail: "\(displayedSnapshot.summerStartText) 开始",
                    tint: Color.yellow
                )
            }
        }
    }

    private func scopeMetricCard(icon: String, title: String, value: String, detail: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8 * leafyControlScale) {
            HStack(spacing: 7 * leafyControlScale) {
                Image(systemName: icon)
                    .font(.system(size: 13 * leafyControlScale, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 23 * leafyControlScale, height: 23 * leafyControlScale)
                    .background(tint.opacity(0.14), in: Circle())

                Text(title)
                    .font(.system(size: 12 * leafyControlScale, weight: .semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }

            Text(value)
                .font(.system(size: 17 * leafyControlScale, weight: .bold))
                .foregroundStyle(AppTheme.primaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.78)

            Text(detail)
                .font(.system(size: 11 * leafyControlScale, weight: .medium))
                .foregroundStyle(AppTheme.tertiaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13 * leafyControlScale)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                .stroke(AppTheme.separator, lineWidth: 1)
        )
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 10 * leafyControlScale)
    }

    private var monthCalendar: some View {
        TimetableTimeScopeMonthCalendar(
            snapshot: displayedSnapshot,
            hasAppeared: hasAppeared,
            monthTransitionDirection: monthTransitionDirection,
            onChangeMonth: changeDisplayedMonth
        )
    }

    private var yearStrip: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            HStack {
                Text("年份缩略")
                    .font(.system(size: 17 * leafyControlScale, weight: .bold))
                    .foregroundStyle(AppTheme.primaryText)
                Spacer()
                HStack(spacing: 10 * leafyControlScale) {
                    legendDot(color: AppTheme.accent(for: themeColorPreference), title: "学期")
                    legendDot(color: AppTheme.warning, title: "暑假")
                }
            }

            HStack(spacing: 4 * leafyControlScale) {
                ForEach(displayedSnapshot.yearMonths) { mark in
                    TimetableTimeScopeMonthMarkView(mark: mark)
                }
            }
            .frame(height: 52 * leafyControlScale)
        }
        .padding(16 * leafyControlScale)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
                .stroke(AppTheme.separator, lineWidth: 1)
        )
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 16 * leafyControlScale)
        .animation(.spring(response: 0.42, dampingFraction: 0.9).delay(0.18), value: hasAppeared)
    }

    private func legendDot(color: Color, title: String) -> some View {
        HStack(spacing: 4 * leafyControlScale) {
            Circle()
                .fill(color)
                .frame(width: 7 * leafyControlScale, height: 7 * leafyControlScale)
            Text(title)
                .font(.system(size: 10 * leafyControlScale, weight: .medium))
                .foregroundStyle(AppTheme.secondaryText)
        }
    }

    private var winterNote: some View {
        HStack(spacing: 10 * leafyControlScale) {
            Image(systemName: "snowflake")
                .font(.system(size: 15 * leafyControlScale, weight: .semibold))
                .foregroundStyle(AppTheme.secondaryText)
                .frame(width: 30 * leafyControlScale, height: 30 * leafyControlScale)
                .background(AppTheme.fill.opacity(0.82), in: Circle())

            Text(displayedSnapshot.winterCountdownText)
                .font(.system(size: 13 * leafyControlScale, weight: .medium))
                .foregroundStyle(AppTheme.secondaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.82)

            Spacer(minLength: 0)
        }
        .padding(13 * leafyControlScale)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                .stroke(AppTheme.separator, lineWidth: 1)
        )
    }

    private func changeDisplayedMonth(by delta: Int) {
        guard let nextMonth = Calendar.current.date(
            byAdding: .month,
            value: delta,
            to: displayedSnapshot.displayedMonthDate
        ) else {
            return
        }

        monthTransitionDirection = delta > 0 ? 1 : -1
        let nextSnapshot = makeDisplayedSnapshot(displayedMonthDate: nextMonth, language: leafyLanguage)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
            displayedSnapshot = nextSnapshot
        }
    }

    private func makeDisplayedSnapshot(
        displayedMonthDate: Date,
        language: AppLanguagePreference,
        baseSnapshot: TimetableTimeScopeSnapshot? = nil
    ) -> TimetableTimeScopeSnapshot {
        let sourceSnapshot = baseSnapshot ?? snapshot
        return TimetableTimeScopeSnapshot.make(
            currentWeek: sourceSnapshot.currentWeek,
            referenceDate: sourceSnapshot.referenceDate,
            displayedMonthDate: displayedMonthDate,
            language: language
        )
    }
}

struct TimetableTimeScopeMonthCalendar: View {
    @Environment(\.leafyControlScale) private var leafyControlScale
    @Environment(\.leafyThemeColorPreference) private var themeColorPreference
    @Environment(\.leafyLanguage) private var leafyLanguage

    let snapshot: TimetableTimeScopeSnapshot
    let hasAppeared: Bool
    let monthTransitionDirection: Int
    let onChangeMonth: (Int) -> Void

    @GestureState private var monthDragTranslation: CGFloat = 0

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 28), spacing: 6 * leafyControlScale), count: 7)
    }

    var body: some View {
        monthCalendarContent
            .contentShape(RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
            .simultaneousGesture(monthSwipeGesture)
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    onChangeMonth(1)
                case .decrement:
                    onChangeMonth(-1)
                @unknown default:
                    break
                }
            }
    }

    private var monthCalendarContent: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            monthCalendarHeader
            monthWeekdayGrid
            monthDayGrid
        }
        .padding(16 * leafyControlScale)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
                .stroke(AppTheme.separator, lineWidth: 1)
        )
    }

    private var monthCalendarHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4 * leafyControlScale) {
                Text(snapshot.monthTitle)
                    .font(.system(size: 22 * leafyControlScale, weight: .bold))
                    .foregroundStyle(AppTheme.primaryText)
                Text(L10n.text("本周范围 %@", language: leafyLanguage, snapshot.weekRangeText))
                    .font(.system(size: 12 * leafyControlScale, weight: .medium))
                    .foregroundStyle(AppTheme.secondaryText)
            }

            Spacer(minLength: AppSpacing.compact)

            Label(L10n.text("滑动切换", language: leafyLanguage), systemImage: "arrow.left.and.right")
                .font(.system(size: 12 * leafyControlScale, weight: .semibold))
                .foregroundStyle(AppTheme.accentEmphasis(for: themeColorPreference))
                .padding(.horizontal, 10 * leafyControlScale)
                .padding(.vertical, 6 * leafyControlScale)
                .background(AppTheme.accentSoft(for: themeColorPreference), in: Capsule())
                .labelStyle(.titleAndIcon)
        }
    }

    private var monthWeekdayGrid: some View {
        LazyVGrid(columns: columns, spacing: 6 * leafyControlScale) {
            ForEach(snapshot.weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.system(size: 11 * leafyControlScale, weight: .semibold))
                    .foregroundStyle(AppTheme.tertiaryText)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var monthDayGrid: some View {
        ZStack {
            LazyVGrid(columns: columns, spacing: 6 * leafyControlScale) {
                ForEach(Array(snapshot.monthDays.enumerated()), id: \.element.id) { index, day in
                    TimetableTimeScopeDayCell(day: day)
                        .frame(minHeight: 42 * leafyControlScale)
                        .opacity(hasAppeared ? 1 : 0)
                        .scaleEffect(hasAppeared ? 1 : 0.9)
                        .animation(
                            .spring(response: 0.36, dampingFraction: 0.9).delay(Double(index) * 0.012),
                            value: hasAppeared
                        )
                }
            }
            .id(snapshot.displayedMonthDate)
            .transition(monthGridTransition)
        }
        .clipped()
        .offset(x: limitedMonthDragOffset)
    }

    private var limitedMonthDragOffset: CGFloat {
        let maxOffset = 92 * leafyControlScale
        return min(max(monthDragTranslation * 0.58, -maxOffset), maxOffset)
    }

    private var monthGridTransition: AnyTransition {
        let insertionEdge: Edge = monthTransitionDirection > 0 ? .trailing : .leading
        let removalEdge: Edge = monthTransitionDirection > 0 ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: insertionEdge).combined(with: .opacity),
            removal: .move(edge: removalEdge).combined(with: .opacity)
        )
    }

    private var monthSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .updating($monthDragTranslation) { value, state, _ in
                guard abs(value.translation.width) > abs(value.translation.height) * 0.72 else { return }
                state = value.translation.width
            }
            .onEnded { value in
                let horizontalDistance = value.translation.width
                let verticalDistance = value.translation.height
                let projectedDistance = value.predictedEndTranslation.width
                let effectiveDistance = abs(projectedDistance) > abs(horizontalDistance) ? projectedDistance : horizontalDistance
                guard abs(effectiveDistance) > max(34 * leafyControlScale, abs(verticalDistance) * 1.12) else {
                    return
                }

                onChangeMonth(effectiveDistance < 0 ? 1 : -1)
            }
    }
}

struct TimetableTimeScopeCornerGatherOverlay: View {
    @Environment(\.leafyControlScale) private var leafyControlScale
    @Environment(\.colorScheme) private var colorScheme

    let isGathered: Bool

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let target = CGPoint(
                x: size.width * 0.5,
                y: min(max(size.height * 0.34, 220 * leafyControlScale), size.height * 0.5)
            )
            let panelSize = CGSize(width: size.width * 0.5 + 2, height: size.height * 0.5 + 2)

            ZStack {
                cornerPanel(
                    from: CGPoint(x: panelSize.width * 0.5, y: panelSize.height * 0.5),
                    target: target,
                    panelSize: panelSize
                )
                cornerPanel(
                    from: CGPoint(x: size.width - panelSize.width * 0.5, y: panelSize.height * 0.5),
                    target: target,
                    panelSize: panelSize
                )
                cornerPanel(
                    from: CGPoint(x: panelSize.width * 0.5, y: size.height - panelSize.height * 0.5),
                    target: target,
                    panelSize: panelSize
                )
                cornerPanel(
                    from: CGPoint(x: size.width - panelSize.width * 0.5, y: size.height - panelSize.height * 0.5),
                    target: target,
                    panelSize: panelSize
                )
            }
            .frame(width: size.width, height: size.height)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func cornerPanel(from start: CGPoint, target: CGPoint, panelSize: CGSize) -> some View {
        RoundedRectangle(cornerRadius: isGathered ? AppRadius.large : 0, style: .continuous)
            .fill(panelFill)
            .frame(
                width: isGathered ? 34 * leafyControlScale : panelSize.width,
                height: isGathered ? 34 * leafyControlScale : panelSize.height
            )
            .position(isGathered ? target : start)
            .opacity(isGathered ? 0 : 1)
            .scaleEffect(isGathered ? 0.36 : 1)
    }

    private var panelFill: Color {
        colorScheme == .dark ? AppTheme.background.opacity(0.96) : AppTheme.cardBackground.opacity(0.96)
    }
}

struct TimetableTimeScopeDayCell: View {
    @Environment(\.leafyControlScale) private var leafyControlScale
    @Environment(\.leafyThemeColorPreference) private var themeColorPreference

    let day: TimetableTimeScopeDay

    var body: some View {
        VStack(spacing: 3 * leafyControlScale) {
            Text("\(day.dayNumber)")
                .font(.system(size: 14 * leafyControlScale, weight: day.isToday || day.isInCurrentWeek ? .bold : .medium))
                .foregroundStyle(foreground)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Circle()
                .fill(eventDotColor)
                .frame(width: 4 * leafyControlScale, height: 4 * leafyControlScale)
                .opacity(day.event == nil ? 0 : 1)
        }
        .frame(maxWidth: .infinity, minHeight: 42 * leafyControlScale)
        .background(background, in: RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                .stroke(strokeColor, lineWidth: day.isToday ? 1.2 : 1)
        )
        .opacity(day.isInDisplayedMonth ? 1 : 0.34)
    }

    private var foreground: Color {
        if day.isToday {
            return AppTheme.textOnAccent(for: themeColorPreference)
        }
        if day.isInCurrentWeek {
            return AppTheme.accentEmphasis(for: themeColorPreference)
        }
        return AppTheme.primaryText
    }

    private var background: Color {
        if day.isToday {
            return AppTheme.accent(for: themeColorPreference)
        }
        if day.isInCurrentWeek {
            return AppTheme.accentSoft(for: themeColorPreference).opacity(0.9)
        }
        if day.event?.kind == .holiday {
            return AppTheme.accentSoft(for: themeColorPreference).opacity(0.64)
        }
        if day.event?.kind == .closure {
            return AppTheme.warning.opacity(0.15)
        }
        if day.event?.kind == .solarTerm {
            return solarTermFill
        }
        return AppTheme.fill.opacity(0.55)
    }

    private var strokeColor: Color {
        if day.isToday {
            return AppTheme.accentEmphasis(for: themeColorPreference).opacity(0.45)
        }
        if day.isInCurrentWeek {
            return AppTheme.accent(for: themeColorPreference).opacity(0.24)
        }
        return AppTheme.separator
    }

    private var eventDotColor: Color {
        if day.isToday {
            return AppTheme.textOnAccent(for: themeColorPreference)
        }
        switch day.event?.kind {
        case .holiday:
            return AppTheme.accentEmphasis(for: themeColorPreference)
        case .closure:
            return AppTheme.warning
        case .solarTerm:
            return solarTermAccent
        case nil:
            return AppTheme.warning
        }
    }

    private var solarTermFill: Color {
        switch day.event?.solarTermSeason {
        case .spring:
            return Color.green.opacity(0.18)
        case .summer:
            return Color.yellow.opacity(0.22)
        case .autumn:
            return Color.orange.opacity(0.20)
        case .winter:
            return Color.cyan.opacity(0.18)
        case nil:
            return AppTheme.fill.opacity(0.82)
        }
    }

    private var solarTermAccent: Color {
        switch day.event?.solarTermSeason {
        case .spring:
            return Color.green.opacity(0.82)
        case .summer:
            return Color.yellow.opacity(0.86)
        case .autumn:
            return Color.orange.opacity(0.86)
        case .winter:
            return Color.cyan.opacity(0.82)
        case nil:
            return AppTheme.secondaryText
        }
    }
}

struct TimetableTimeScopeMonthMarkView: View {
    @Environment(\.leafyControlScale) private var leafyControlScale
    @Environment(\.leafyThemeColorPreference) private var themeColorPreference

    let mark: TimetableTimeScopeMonthMark

    var body: some View {
        VStack(spacing: 5 * leafyControlScale) {
            RoundedRectangle(cornerRadius: 5 * leafyControlScale, style: .continuous)
                .fill(fill)
                .overlay(
                    RoundedRectangle(cornerRadius: 5 * leafyControlScale, style: .continuous)
                        .stroke(stroke, lineWidth: mark.isDisplayedMonth ? 1.4 : 1)
                )
                .frame(height: 25 * leafyControlScale)

            Text(mark.label)
                .font(.system(size: 9 * leafyControlScale, weight: mark.isDisplayedMonth ? .bold : .medium))
                .foregroundStyle(mark.isDisplayedMonth ? AppTheme.accentEmphasis(for: themeColorPreference) : AppTheme.tertiaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .frame(maxWidth: .infinity)
    }

    private var fill: Color {
        if mark.isDisplayedMonth {
            return AppTheme.accent(for: themeColorPreference).opacity(0.82)
        }
        if mark.isInSummer {
            return AppTheme.warning.opacity(0.48)
        }
        if mark.isInSemester {
            return AppTheme.accentSoft(for: themeColorPreference).opacity(0.72)
        }
        return AppTheme.fill.opacity(0.62)
    }

    private var stroke: Color {
        mark.isDisplayedMonth ? AppTheme.accentEmphasis(for: themeColorPreference) : AppTheme.separator
    }
}
