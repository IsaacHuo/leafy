import SwiftData
import SwiftSoup
import SwiftUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct TimetableExportSheet: View {
    let currentWeek: Int
    let courses: [Course]
    let courseNotes: [CourseNote]
    let occurrenceNotes: [CourseOccurrenceNote]
    let cellReminders: [TimetableCellReminder]
    let exams: [ExamArrangement]
    let lastSyncAt: Date?
    let lastFailureMessage: String?
    let includesWeekendsByDefault: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.leafyLanguage) private var leafyLanguage
    @State private var selectedRange: TimetableCalendarExportRange = .remainingSemester
    @State private var isExportingCalendar = false
    @State private var isClearingCalendar = false
    @State private var isClearConfirmationPresented = false
    @State private var customStartWeek: Int
    @State private var customEndWeek: Int
    @State private var selectedDaySummary: TimetableDaySelection?
    @State private var showingWeekSchedule = false
    @State private var operationAlert: LeafyOperationAlert?

    init(
        currentWeek: Int,
        courses: [Course],
        courseNotes: [CourseNote],
        occurrenceNotes: [CourseOccurrenceNote],
        cellReminders: [TimetableCellReminder],
        exams: [ExamArrangement],
        lastSyncAt: Date?,
        lastFailureMessage: String?,
        includesWeekendsByDefault: Bool
    ) {
        self.currentWeek = currentWeek
        self.courses = courses
        self.courseNotes = courseNotes
        self.occurrenceNotes = occurrenceNotes
        self.cellReminders = cellReminders
        self.exams = exams
        self.lastSyncAt = lastSyncAt
        self.lastFailureMessage = lastFailureMessage
        self.includesWeekendsByDefault = includesWeekendsByDefault
        let initialWeek = max(1, min(currentWeek, SemesterConfig.supportedWeeks))
        _customStartWeek = State(initialValue: initialWeek)
        _customEndWeek = State(initialValue: initialWeek)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.card) {
                    calendarExportSection
                    shareViewsSection
                }
                .padding(AppSpacing.page)
            }
            .background(LeafyPageBackground())
            .navigationTitle("导出课表")
            .leafyInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .leafyTrailing) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
            .sheet(item: $selectedDaySummary) { selection in
                DayScheduleSummarySheet(
                    selection: selection,
                    courses: courses,
                    exams: exams,
                    lastSyncAt: lastSyncAt,
                    lastFailureMessage: lastFailureMessage
                )
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showingWeekSchedule) {
                WeekScheduleSheet(
                    selection: currentWeekSelection,
                    courses: courses,
                    cellReminders: cellReminders,
                    exams: exams,
                    courseNotes: courseNotes,
                    occurrenceNotes: occurrenceNotes,
                    includesWeekendsByDefault: includesWeekendsByDefault
                )
                .presentationDetents([.large])
            }
            .alert("清理已导出课表事件？", isPresented: $isClearConfirmationPresented) {
                Button("取消", role: .cancel) {}
                Button("清理", role: .destructive) {
                    Task { await clearExportedCourses() }
                }
            } message: {
                Text("将移除本学期所有由 \(AppBrand.displayName) 写入系统日历的课程、考试和提醒事件。")
            }
            .leafyOperationAlert($operationAlert)
        }
    }

    private var calendarExportSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                LeafyIconBadge(systemName: "calendar.badge.plus")

                VStack(alignment: .leading, spacing: 4) {
                    Text("导出到系统日历")
                        .leafyHeadline()
                        .foregroundStyle(AppTheme.primaryText)
                    Text("重复导出会覆盖更新 \(AppBrand.displayName) 已写入的课程、考试和提醒事件。")
                        .microCaption()
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }

            Picker("导出范围", selection: $selectedRange) {
                ForEach(TimetableCalendarExportRange.allCases) { range in
                    Text(range.title).tag(range)
                }
            }
            .pickerStyle(.segmented)

            if selectedRange == .customWeeks {
                customWeekRangeControls
            }

            Button {
                Task { await exportToCalendar() }
            } label: {
                ZStack {
                    Label("导出到本地日历", systemImage: "calendar.badge.plus")
                        .frame(maxWidth: .infinity, alignment: .center)
                    if isExportingCalendar {
                        HStack {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .leafyBody()
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.accent)
            .disabled(isExportingCalendar || isClearingCalendar || exportableItemCount == 0)

            Divider()

            Button(role: .destructive) {
                isClearConfirmationPresented = true
            } label: {
                ZStack {
                    Label("清理已导出课表事件", systemImage: "trash")
                        .frame(maxWidth: .infinity, alignment: .center)
                    if isClearingCalendar {
                        HStack {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .leafyBody()
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .disabled(isExportingCalendar || isClearingCalendar)
        }
        .padding(18)
        .leafyCardStyle()
    }

    private var customWeekRangeControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("自定义周次", systemImage: "calendar")
                    .leafyBody()
                    .foregroundStyle(AppTheme.primaryText)

                Spacer()

                Text(customWeekRangeTitle)
                    .microCaption()
                    .foregroundStyle(AppTheme.secondaryText)
            }

            customWeekMenu(title: "开始", week: customStartWeek) { week in
                selectCustomStartWeek(week)
            }

            customWeekMenu(title: "结束", week: customEndWeek) { week in
                selectCustomEndWeek(week)
            }
        }
    }

    private func customWeekMenu(
        title: String,
        week: Int,
        onSelect: @escaping (Int) -> Void
    ) -> some View {
        Menu {
            ForEach(1...totalWeeks, id: \.self) { candidateWeek in
                Button("第 \(candidateWeek) 周") {
                    onSelect(candidateWeek)
                }
            }
        } label: {
            HStack(spacing: 10) {
                Text(title)
                    .foregroundStyle(AppTheme.secondaryText)

                Spacer()

                Text("第 \(week) 周")
                    .foregroundStyle(AppTheme.primaryText)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.tertiaryText)
            }
            .leafyBody()
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(AppTheme.accentSoft.opacity(0.22), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var shareViewsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("分享视图")
                .leafyHeadline()

            Button {
                selectedDaySummary = todaySelection
            } label: {
                exportActionRow(title: "今日视图", subtitle: "生成今天的日程卡片", icon: "sun.max")
            }
            .buttonStyle(.plain)

            Divider()

            Button {
                showingWeekSchedule = true
            } label: {
                exportActionRow(title: "本周视图", subtitle: "生成当前周的课表卡片", icon: "calendar")
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .leafyCardStyle()
    }

    private func exportActionRow(title: String, subtitle: String, icon: String) -> some View {
        HStack(spacing: 12) {
            LeafyIconBadge(systemName: icon)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .leafyBody()
                    .foregroundStyle(AppTheme.primaryText)
                Text(subtitle)
                    .microCaption()
                    .foregroundStyle(AppTheme.secondaryText)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppTheme.tertiaryText)
        }
        .contentShape(Rectangle())
    }

    private var todaySelection: TimetableDaySelection {
        let date = Date()
        let schedule = SemesterConfig.weekAndDay(for: date)
        return TimetableDaySelection(week: schedule.week, day: schedule.day, date: date)
    }

    private var currentWeekSelection: TimetableDaySelection {
        TimetableDaySelection(
            week: currentWeek,
            day: 1,
            date: dateFor(day: 1, week: currentWeek)
        )
    }

    private var totalWeeks: Int {
        max(1, SemesterConfig.supportedWeeks)
    }

    private var exportableItemCount: Int {
        courses.count + cellReminders.count + exams.count
    }

    private var customWeekRange: ClosedRange<Int> {
        let startWeek = clampedCustomWeek(customStartWeek)
        let endWeek = clampedCustomWeek(customEndWeek)
        return min(startWeek, endWeek)...max(startWeek, endWeek)
    }

    private var customWeekRangeTitle: String {
        if customWeekRange.lowerBound == customWeekRange.upperBound {
            return "第 \(customWeekRange.lowerBound) 周"
        }
        return "第 \(customWeekRange.lowerBound)-\(customWeekRange.upperBound) 周"
    }

    private func dateFor(day: Int, week: Int) -> Date {
        let offset = (week - 1) * 7 + (day - 1)
        return Calendar.current.date(byAdding: .day, value: offset, to: SemesterConfig.startOfSemesterDate) ?? Date()
    }

    private func clampedCustomWeek(_ week: Int) -> Int {
        max(1, min(week, totalWeeks))
    }

    private func selectCustomStartWeek(_ week: Int) {
        customStartWeek = clampedCustomWeek(week)
        if customEndWeek < customStartWeek {
            customEndWeek = customStartWeek
        }
    }

    private func selectCustomEndWeek(_ week: Int) {
        customEndWeek = clampedCustomWeek(week)
        if customStartWeek > customEndWeek {
            customStartWeek = customEndWeek
        }
    }

    @MainActor
    private func exportToCalendar() async {
        guard !isExportingCalendar else { return }
        isExportingCalendar = true
        defer { isExportingCalendar = false }

        do {
            let result = try await TimetableCalendarExportService().export(
                courses: courses,
                courseNotes: courseNotes,
                occurrenceNotes: occurrenceNotes,
                cellReminders: cellReminders,
                exams: exams,
                range: selectedRange,
                currentWeek: currentWeek,
                customWeeks: selectedRange == .customWeeks ? customWeekRange : nil
            )
            operationAlert = .success(result.message)
        } catch {
            operationAlert = .failure(error.localizedDescription)
        }
    }

    @MainActor
    private func clearExportedCourses() async {
        guard !isClearingCalendar else { return }
        isClearingCalendar = true
        defer { isClearingCalendar = false }

        do {
            let result = try await TimetableCalendarExportService().clearExportedCourses()
            operationAlert = .success(result.message)
        } catch {
            operationAlert = .failure(error.localizedDescription)
        }
    }
}

struct DayScheduleSummarySheet: View {
    let selection: TimetableDaySelection
    let courses: [Course]
    let exams: [ExamArrangement]
    let lastSyncAt: Date?
    let lastFailureMessage: String?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.leafyLanguage) private var leafyLanguage
    @Environment(\.leafyDependencies) private var dependencies
    @ObservedObject private var sessionManager = CommunitySessionManager.shared
    @State private var sharePreviewImage: UIImage?
    @State private var shareErrorMessage: String?
    @State private var weatherText = L10n.text("天气加载中")

    var body: some View {
        NavigationStack {
            ScrollView {
                DayScheduleSummaryCard(
                    selection: selection,
                    courses: courses,
                    exams: exams,
                    weatherText: weatherText,
                    lastSyncAt: lastSyncAt,
                    lastFailureMessage: lastFailureMessage
                ) {
                    generateSharePreview()
                }
                .padding(AppSpacing.page)
            }
            .background(LeafyPageBackground())
            .navigationTitle(Calendar.current.isDateInToday(selection.date) ? L10n.text("今日视图", language: leafyLanguage) : L10n.text("日程视图", language: leafyLanguage))
            .leafyInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .leafyTrailing) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
            .task {
                await sessionManager.restoreProfileIfPossible()
                await loadWeather()
            }
            .sheet(isPresented: Binding(
                get: { sharePreviewImage != nil },
                set: { if !$0 { sharePreviewImage = nil } }
            )) {
                if let sharePreviewImage {
                    DayScheduleImagePreviewSheet(image: sharePreviewImage)
                }
            }
            .alert("无法生成分享图片", isPresented: Binding(
                get: { shareErrorMessage != nil },
                set: { if !$0 { shareErrorMessage = nil } }
            )) {
                Button("确定", role: .cancel) {}
            } message: {
                Text(shareErrorMessage ?? "")
            }
        }
    }

    private var shareDisplayName: String {
        let candidates = [
            sessionManager.profile?.resolvedDisplayName,
            ActiveCampusContext.networkManager.authenticatedDisplayName,
            ActiveCampusContext.networkManager.authenticatedEduID,
            ActiveCampusContext.descriptor.defaultStudentDisplayName
        ]

        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? L10n.text(ActiveCampusContext.descriptor.defaultStudentDisplayName, language: leafyLanguage)
    }

    @MainActor
    private func generateSharePreview() {
        let content = DayScheduleShareImageCard(
            selection: selection,
            courses: courses,
            weatherText: weatherText,
            displayName: shareDisplayName
        )
        .frame(width: 360)
        .padding(18)
        .background(
            LinearGradient(
                colors: [
                    AppTheme.background,
                    AppTheme.accentSoft.opacity(0.42),
                    AppTheme.background
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )

        let renderer = ImageRenderer(content: content)
        renderer.scale = LeafyImageCodec.displayScale

        guard let image = renderer.leafyPlatformImage else {
            shareErrorMessage = L10n.text("请稍后重试，或先截图保存当前卡片。", language: leafyLanguage)
            return
        }

        sharePreviewImage = image
    }

    @MainActor
    private func loadWeather() async {
        do {
            let weather = try await dependencies.weatherService.fetchCurrentWeather()
            weatherText = TimetableWeather(
                temperature: weather.temperature,
                condition: weather.condition
            ).displayText
        } catch {
            weatherText = L10n.text("天气暂不可用")
        }
    }
}

struct WeekScheduleSheet: View {
    let selection: TimetableDaySelection
    let courses: [Course]
    let cellReminders: [TimetableCellReminder]
    let exams: [ExamArrangement]
    let courseNotes: [CourseNote]
    let occurrenceNotes: [CourseOccurrenceNote]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.leafyLanguage) private var leafyLanguage
    @ObservedObject private var sessionManager = CommunitySessionManager.shared
    @State private var includesWeekends: Bool
    @State private var sharePreviewImage: UIImage?
    @State private var shareErrorMessage: String?

    init(
        selection: TimetableDaySelection,
        courses: [Course],
        cellReminders: [TimetableCellReminder],
        exams: [ExamArrangement],
        courseNotes: [CourseNote],
        occurrenceNotes: [CourseOccurrenceNote],
        includesWeekendsByDefault: Bool = true
    ) {
        self.selection = selection
        self.courses = courses
        self.cellReminders = cellReminders
        self.exams = exams
        self.courseNotes = courseNotes
        self.occurrenceNotes = occurrenceNotes
        _includesWeekends = State(initialValue: includesWeekendsByDefault)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                WeekScheduleCard(
                    selection: selection,
                    courses: courses,
                    cellReminders: cellReminders,
                    exams: exams,
                    courseNotes: courseNotes,
                    occurrenceNotes: occurrenceNotes,
                    includesWeekends: $includesWeekends
                ) {
                    generateSharePreview()
                }
                .padding(AppSpacing.page)
            }
            .background(LeafyPageBackground())
            .navigationTitle(L10n.text("本周视图", language: leafyLanguage))
            .leafyInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .leafyTrailing) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
            .task {
                await sessionManager.restoreProfileIfPossible()
            }
            .sheet(isPresented: Binding(
                get: { sharePreviewImage != nil },
                set: { if !$0 { sharePreviewImage = nil } }
            )) {
                if let sharePreviewImage {
                    DayScheduleImagePreviewSheet(image: sharePreviewImage)
                }
            }
            .alert("无法生成分享图片", isPresented: Binding(
                get: { shareErrorMessage != nil },
                set: { if !$0 { shareErrorMessage = nil } }
            )) {
                Button("确定", role: .cancel) {}
            } message: {
                Text(shareErrorMessage ?? "")
            }
        }
    }

    private var shareDisplayName: String {
        let candidates = [
            sessionManager.profile?.resolvedDisplayName,
            ActiveCampusContext.networkManager.authenticatedDisplayName,
            ActiveCampusContext.networkManager.authenticatedEduID,
            ActiveCampusContext.descriptor.defaultStudentDisplayName
        ]

        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? L10n.text(ActiveCampusContext.descriptor.defaultStudentDisplayName, language: leafyLanguage)
    }

    @MainActor
    private func generateSharePreview() {
        let content = WeekScheduleShareImageCard(
            selection: selection,
            courses: courses,
            cellReminders: cellReminders,
            exams: exams,
            courseNotes: courseNotes,
            occurrenceNotes: occurrenceNotes,
            displayName: shareDisplayName,
            includesWeekends: includesWeekends
        )
        .frame(width: 392)
        .padding(18)
        .background(
            LinearGradient(
                colors: [
                    AppTheme.background,
                    AppTheme.accentSoft.opacity(0.42),
                    AppTheme.background
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )

        let renderer = ImageRenderer(content: content)
        renderer.scale = LeafyImageCodec.displayScale

        guard let image = renderer.leafyPlatformImage else {
            shareErrorMessage = L10n.text("请稍后重试，或先截图保存当前卡片。", language: leafyLanguage)
            return
        }

        sharePreviewImage = image
    }
}

struct WeekScheduleCard: View {
    @Environment(\.leafyLanguage) private var leafyLanguage

    let selection: TimetableDaySelection
    let courses: [Course]
    let cellReminders: [TimetableCellReminder]
    let exams: [ExamArrangement]
    let courseNotes: [CourseNote]
    let occurrenceNotes: [CourseOccurrenceNote]
    @Binding var includesWeekends: Bool
    let shareAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(AppBrand.displayName) 本周视图")
                        .microCaption()
                        .foregroundStyle(AppTheme.accentEmphasis)
                    Text(weekTitle)
                        .title2()
                        .foregroundStyle(AppTheme.primaryText)
                    Text(weekRangeText)
                        .microCaption()
                        .foregroundStyle(AppTheme.secondaryText)
                }

                Spacer()

                Button(action: shareAction) {
                    TimetableShareIcon()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("分享本周课表")
            }

            Toggle(isOn: $includesWeekends) {
                Label("显示周末", systemImage: "calendar")
                    .leafyBody()
                    .foregroundStyle(AppTheme.primaryText)
            }
            .toggleStyle(.switch)
            .tint(AppTheme.accent)

            GeometryReader { proxy in
                let columnSpacing = WeeklyTimetableGrid.compactColumnSpacing
                let axisWidth = WeeklyTimetableGrid.compactAxisWidth
                let visibleDayCount = includesWeekends ? 7 : 5
                let dayWidth = WeeklyTimetableGrid.fittedDayWidth(
                    containerWidth: proxy.size.width,
                    axisWidth: axisWidth,
                    columnSpacing: columnSpacing,
                    visibleDayCount: visibleDayCount
                )

                WeeklyTimetableGrid(
                    selection: selection,
                    courses: courses,
                    cellReminders: cellReminders,
                    exams: exams,
                    courseNotes: courseNotes,
                    occurrenceNotes: occurrenceNotes,
                    dayWidth: dayWidth,
                    rowHeight: 50,
                    axisWidth: axisWidth,
                    headerHeight: 42,
                    includesWeekends: includesWeekends,
                    columnSpacing: columnSpacing,
                    textScale: 0.96
                )
            }
            .frame(height: WeeklyTimetableGrid.totalHeight(rowHeight: 50, headerHeight: 42, columnSpacing: WeeklyTimetableGrid.compactColumnSpacing))
        }
        .padding(18)
        .leafyCardStyle()
    }

    private var weekTitle: String {
        L10n.text("第 %d 周", language: leafyLanguage, selection.week)
    }

    private var weekRangeText: String {
        "\(shortDateText(for: 1)) - \(shortDateText(for: includesWeekends ? 7 : 5))"
    }

    private func shortDateText(for day: Int) -> String {
        let components = Calendar.current.dateComponents([.month, .day], from: date(for: day))
        return String(format: "%02d-%02d", components.month ?? 1, components.day ?? 1)
    }

    private func date(for day: Int) -> Date {
        let offset = (selection.week - 1) * 7 + (day - 1)
        return Calendar.current.date(byAdding: .day, value: offset, to: SemesterConfig.startOfSemesterDate) ?? selection.date
    }
}

struct WeekScheduleShareImageCard: View {
    @Environment(\.leafyLanguage) private var leafyLanguage

    let selection: TimetableDaySelection
    let courses: [Course]
    let cellReminders: [TimetableCellReminder]
    let exams: [ExamArrangement]
    let courseNotes: [CourseNote]
    let occurrenceNotes: [CourseOccurrenceNote]
    let displayName: String
    let includesWeekends: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(AppBrand.displayName) 本周视图")
                        .microCaption()
                        .foregroundStyle(AppTheme.accentEmphasis)
                    Text(L10n.text("第 %d 周", language: leafyLanguage, selection.week))
                        .title2()
                        .foregroundStyle(AppTheme.primaryText)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 4) {
                    Text(displayName)
                        .leafyHeadline()
                        .foregroundStyle(AppTheme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(L10n.text("的周课表", language: leafyLanguage))
                        .microCaption()
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }

            WeeklyTimetableGrid(
                selection: selection,
                courses: courses,
                cellReminders: cellReminders,
                exams: exams,
                courseNotes: courseNotes,
                occurrenceNotes: occurrenceNotes,
                dayWidth: WeeklyTimetableGrid.fittedDayWidth(
                    containerWidth: 356,
                    axisWidth: WeeklyTimetableGrid.compactAxisWidth,
                    columnSpacing: WeeklyTimetableGrid.compactColumnSpacing,
                    visibleDayCount: includesWeekends ? 7 : 5
                ),
                rowHeight: 58,
                axisWidth: WeeklyTimetableGrid.compactAxisWidth,
                headerHeight: 46,
                includesWeekends: includesWeekends,
                columnSpacing: WeeklyTimetableGrid.compactColumnSpacing,
                textScale: 1.12
            )

            HStack {
                Text(L10n.text("来自 %@", language: leafyLanguage, AppBrand.displayName))
                    .microCaption()
                    .foregroundStyle(AppTheme.tertiaryText)
                Spacer()
                Text(L10n.text("分享于 %@", language: leafyLanguage, DateFormatters.headerWithTime.string(from: Date())))
                    .microCaption()
                    .foregroundStyle(AppTheme.tertiaryText)
            }
        }
        .padding(18)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
                .stroke(AppTheme.separator, lineWidth: 1)
        )
    }
}

struct WeeklyTimetableGrid: View {
    @Environment(\.leafyLanguage) private var leafyLanguage
    @Environment(\.colorScheme) private var colorScheme

    let selection: TimetableDaySelection
    let courses: [Course]
    let cellReminders: [TimetableCellReminder]
    let exams: [ExamArrangement]
    let courseNotes: [CourseNote]
    let occurrenceNotes: [CourseOccurrenceNote]
    let dayWidth: CGFloat
    let rowHeight: CGFloat
    let axisWidth: CGFloat
    let headerHeight: CGFloat
    var includesWeekends: Bool = true
    var columnSpacing: CGFloat = 4
    var textScale: CGFloat = 1

    static let compactAxisWidth: CGFloat = 28
    static let compactColumnSpacing: CGFloat = 3

    static func fittedDayWidth(
        containerWidth: CGFloat,
        axisWidth: CGFloat,
        columnSpacing: CGFloat,
        visibleDayCount: Int
    ) -> CGFloat {
        let dayCount = max(visibleDayCount, 1)
        let spacingWidth = CGFloat(dayCount) * columnSpacing
        let rawWidth = (containerWidth - axisWidth - spacingWidth) / CGFloat(dayCount)
        let maximumWidth: CGFloat = dayCount >= 7 ? 48 : 62
        return min(max(rawWidth, 34), maximumWidth)
    }

    static func totalHeight(rowHeight: CGFloat, headerHeight: CGFloat, columnSpacing: CGFloat) -> CGFloat {
        headerHeight + columnSpacing + CGFloat(13) * rowHeight + CGFloat(12) * 2
    }

    private let totalPeriods = 13
    private let rowSpacing: CGFloat = 2
    private let cardInset: CGFloat = 2
    private let laneSpacing: CGFloat = 2

    private var days: [Int] { Array(1...(includesWeekends ? 7 : 5)) }

    private var visibleDays: Set<Int> {
        Set(days)
    }

    private var gridProjection: WeeklyTimetableProjection {
        WeeklyTimetableProjection.make(
            selection: selection,
            courses: courses,
            cellReminders: cellReminders,
            exams: exams,
            courseNotes: courseNotes,
            occurrenceNotes: occurrenceNotes,
            includesWeekends: includesWeekends
        )
    }

    private var bodyWidth: CGFloat {
        CGFloat(days.count) * dayWidth + CGFloat(days.count - 1) * columnSpacing
    }

    private var gridHeight: CGFloat {
        CGFloat(totalPeriods) * rowHeight + CGFloat(totalPeriods - 1) * rowSpacing
    }

    private var totalWidth: CGFloat {
        axisWidth + columnSpacing + bodyWidth
    }

    var body: some View {
        let projection = gridProjection

        VStack(alignment: .leading, spacing: columnSpacing) {
            HStack(alignment: .top, spacing: columnSpacing) {
                cornerHeader
                    .frame(width: axisWidth, height: headerHeight)

                HStack(alignment: .top, spacing: columnSpacing) {
                    ForEach(projection.days, id: \.self) { day in
                        dayHeader(day, projection: projection)
                            .frame(width: dayWidth, height: headerHeight)
                    }
                }
            }

            HStack(alignment: .top, spacing: columnSpacing) {
                periodAxis
                    .frame(width: axisWidth, height: gridHeight)

                ZStack(alignment: .topLeading) {
                    gridBackground

                    ForEach(projection.reminders) { reminder in
                        let spanHeight = reminderSpanHeight(reminder)
                        TimetableCellReminderBlockView(
                            reminder: reminder,
                            height: reminderHeight(reminder),
                            width: max(dayWidth - cardInset * 2, 1)
                        )
                        .position(
                            x: xPosition(day: reminder.dayOfWeek) + dayWidth * 0.5,
                            y: yPosition(period: reminder.displayStartPeriod) + spanHeight * 0.5
                        )
                    }

                    ForEach(projection.examProjections) { projection in
                        TimetableExamBlockView(
                            projection: projection,
                            height: examHeight,
                            width: max(dayWidth - cardInset * 2, 1)
                        )
                        .position(
                            x: xPosition(day: projection.dayOfWeek) + dayWidth * 0.5,
                            y: examYPosition(period: projection.period) + examHeight * 0.5
                        )
                        .zIndex(3)
                    }

                    ForEach(projection.days, id: \.self) { day in
                        ForEach(projection.layouts(for: day)) { layout in
                            let blockHeight = heightForCourse(layout.course)
                            let blockWidth = widthForLayout(layout)
                            let noteText = projection.note(for: layout.course)
                            CourseBlockView(
                                course: layout.course,
                                hasNote: noteText != nil,
                                noteText: noteText,
                                height: blockHeight,
                                width: blockWidth,
                                isCompact: true,
                                isTodayCourse: isToday(day)
                            )
                            .position(
                                x: xPosition(day: day) + xOffsetForLayout(layout) + blockWidth * 0.5,
                                y: yOffset(for: layout.course) + blockHeight * 0.5
                            )
                        }
                    }
                }
                .frame(width: bodyWidth, height: gridHeight, alignment: .topLeading)
            }
        }
        .frame(width: totalWidth, alignment: .leading)
    }

    private var weekCourses: [Course] {
        courses
            .filter { $0.weeks.contains(selection.week) }
            .sortedByStartPeriod()
    }

    private var weekReminders: [TimetableCellReminder] {
        cellReminders
            .filter { $0.week == selection.week && visibleDays.contains($0.dayOfWeek) }
            .sorted { lhs, rhs in
                if lhs.dayOfWeek != rhs.dayOfWeek { return lhs.dayOfWeek < rhs.dayOfWeek }
                return lhs.period < rhs.period
            }
    }

    private func reminderSpanHeight(_ reminder: TimetableCellReminder) -> CGFloat {
        let periodCount = max(reminder.displayEndPeriod - reminder.displayStartPeriod + 1, 1)
        return CGFloat(periodCount) * rowHeight + CGFloat(max(periodCount - 1, 0)) * rowSpacing
    }

    private func reminderHeight(_ reminder: TimetableCellReminder) -> CGFloat {
        max(reminderSpanHeight(reminder) - cardInset * 2, rowHeight * 0.72)
    }

    private var weekExamProjections: [TimetableExamProjection] {
        exams
            .compactMap(\.timetableProjection)
            .filter { $0.week == selection.week && visibleDays.contains($0.dayOfWeek) }
            .sorted { lhs, rhs in
                if lhs.dayOfWeek != rhs.dayOfWeek { return lhs.dayOfWeek < rhs.dayOfWeek }
                if lhs.period != rhs.period { return lhs.period < rhs.period }
                return lhs.startsAt < rhs.startsAt
            }
    }

    private var cellHeight: CGFloat {
        max(rowHeight - cardInset * 2, rowHeight * 0.72)
    }

    private var examHeight: CGFloat {
        min(max(rowHeight * 0.52, 20), rowHeight - cardInset * 2)
    }

    private var cornerHeader: some View {
        RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
            .fill(AppTheme.cardBackground)
            .overlay(
                Text("节次")
                    .font(.system(size: 10 * textScale, weight: .semibold))
                    .foregroundStyle(AppTheme.secondaryText)
            )
    }

    private func dayHeader(_ day: Int, projection: WeeklyTimetableProjection) -> some View {
        let hasExam = projection.hasExam(on: day)

        return VStack(spacing: 2) {
            Text(dayTitle(day))
                .font(.system(size: 12 * textScale, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(shortDateText(for: day))
                .font(.system(size: 10 * textScale, weight: .regular))
                .lineLimit(1)
            if hasExam {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 8 * textScale, weight: .semibold))
                    .foregroundStyle(isToday(day) ? AppTheme.textOnAccent : AppTheme.warning)
            }
        }
        .foregroundStyle(isToday(day) ? AppTheme.textOnAccent : (hasExam ? AppTheme.warning : AppTheme.primaryText))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                .fill(dayHeaderFill(isToday: isToday(day), hasExam: hasExam))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                .stroke(isToday(day) || hasExam ? Color.clear : AppTheme.separator, lineWidth: 1)
        )
    }

    private func dayHeaderFill(isToday: Bool, hasExam: Bool) -> Color {
        if isToday { return AppTheme.accent }
        if hasExam { return AppTheme.warning.opacity(colorScheme == .dark ? 0.26 : 0.20) }
        return AppTheme.cardBackground
    }

    private var periodAxis: some View {
        ZStack(alignment: .topLeading) {
            ForEach(1...totalPeriods, id: \.self) { period in
                Text("\(period)")
                    .font(.system(size: 12 * textScale, weight: .semibold))
                .foregroundStyle(AppTheme.secondaryText)
                .frame(width: axisWidth, height: rowHeight)
                .background(
                    RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                        .fill(AppTheme.cardBackground.opacity(0.52))
                )
                .position(x: axisWidth * 0.5, y: yPosition(period: period) + rowHeight * 0.5)
            }
        }
    }

    private var gridBackground: some View {
        ZStack(alignment: .topLeading) {
            ForEach(days, id: \.self) { day in
                ForEach(1...totalPeriods, id: \.self) { period in
                    RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                        .fill(backgroundFillColor(for: period))
                        .frame(width: dayWidth, height: rowHeight)
                        .position(
                            x: xPosition(day: day) + dayWidth * 0.5,
                            y: yPosition(period: period) + rowHeight * 0.5
                        )
                }
            }
        }
    }

    private func layoutsForDay(_ day: Int) -> [DayCourseLayout] {
        let dayCourses = weekCourses
            .filter { $0.dayOfWeek == day }
            .sortedByStartPeriod()
        guard !dayCourses.isEmpty else { return [] }

        var result: [DayCourseLayout] = []
        var cluster: [Course] = []
        var clusterMaxEnd = 0

        func flushCluster() {
            guard !cluster.isEmpty else { return }
            result.append(contentsOf: layoutsForCluster(cluster))
            cluster.removeAll()
            clusterMaxEnd = 0
        }

        for course in dayCourses {
            let start = course.duration.min() ?? 0
            let end = course.duration.max() ?? 0

            if cluster.isEmpty {
                cluster = [course]
                clusterMaxEnd = end
            } else if start <= clusterMaxEnd {
                cluster.append(course)
                clusterMaxEnd = max(clusterMaxEnd, end)
            } else {
                flushCluster()
                cluster = [course]
                clusterMaxEnd = end
            }
        }

        flushCluster()
        return result
    }

    private func layoutsForCluster(_ cluster: [Course]) -> [DayCourseLayout] {
        var laneEndings: [Int] = []
        var placements: [(Course, Int)] = []

        for course in cluster {
            let start = course.duration.min() ?? 0
            let end = course.duration.max() ?? 0

            if let reusableLane = laneEndings.firstIndex(where: { $0 < start }) {
                laneEndings[reusableLane] = end
                placements.append((course, reusableLane))
            } else {
                laneEndings.append(end)
                placements.append((course, laneEndings.count - 1))
            }
        }

        return placements.map { course, laneIndex in
            DayCourseLayout(course: course, laneIndex: laneIndex, laneCount: max(1, laneEndings.count))
        }
    }

    private func widthForLayout(_ layout: DayCourseLayout) -> CGFloat {
        let totalSpacing = CGFloat(max(layout.laneCount - 1, 0)) * laneSpacing
        let laneWidth = (dayWidth - totalSpacing - cardInset * 2) / CGFloat(layout.laneCount)
        return max(laneWidth, 1)
    }

    private func xOffsetForLayout(_ layout: DayCourseLayout) -> CGFloat {
        let laneWidth = widthForLayout(layout)
        return cardInset + CGFloat(layout.laneIndex) * (laneWidth + laneSpacing)
    }

    private func heightForCourse(_ course: Course) -> CGFloat {
        let count = max(course.duration.count, 1)
        let rawHeight = CGFloat(count) * rowHeight + CGFloat(count - 1) * rowSpacing - cardInset * 2
        return max(rawHeight, rowHeight * 0.7)
    }

    private func yOffset(for course: Course) -> CGFloat {
        guard let start = course.duration.min() else { return 0 }
        return yPosition(period: start) + cardInset
    }

    private func examYPosition(period: Int) -> CGFloat {
        yPosition(period: period) + cardInset
    }

    private func xPosition(day: Int) -> CGFloat {
        CGFloat(max(day - 1, 0)) * (dayWidth + columnSpacing)
    }

    private func yPosition(period: Int) -> CGFloat {
        CGFloat(max(period - 1, 0)) * (rowHeight + rowSpacing)
    }

    private func backgroundFillColor(for period: Int) -> Color {
        if period == 5 || period == 9 {
            return colorScheme == .dark ? AppTheme.accent.opacity(0.18) : AppTheme.accentSoft.opacity(0.38)
        }
        return AppTheme.cardBackground.opacity(0.36)
    }

    private func dayTitle(_ day: Int) -> String {
        leafyLanguage.weekdayTitle(for: day)
    }

    private func shortDateText(for day: Int) -> String {
        let components = Calendar.current.dateComponents([.month, .day], from: date(for: day))
        return String(format: "%02d-%02d", components.month ?? 1, components.day ?? 1)
    }

    private func isToday(_ day: Int) -> Bool {
        Calendar.current.isDateInToday(date(for: day))
    }

    private func date(for day: Int) -> Date {
        let offset = (selection.week - 1) * 7 + (day - 1)
        return Calendar.current.date(byAdding: .day, value: offset, to: SemesterConfig.startOfSemesterDate) ?? selection.date
    }
}

struct DayScheduleSummaryCard: View {
    @Environment(\.leafyLanguage) private var leafyLanguage

    let selection: TimetableDaySelection
    let courses: [Course]
    let exams: [ExamArrangement]
    let weatherText: String
    let lastSyncAt: Date?
    let lastFailureMessage: String?
    let shareAction: () -> Void

    private var dayCourses: [Course] {
        courses
            .filter { $0.weeks.contains(selection.week) && $0.dayOfWeek == selection.day }
            .sortedByStartPeriod()
    }

    private var dayExams: [ExamArrangement] {
        exams
            .filter { exam in
                guard let startsAt = exam.startsAt else { return false }
                return Calendar.current.isDate(startsAt, inSameDayAs: selection.date)
            }
            .sorted { ($0.startsAt ?? .distantFuture) < ($1.startsAt ?? .distantFuture) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Calendar.current.isDateInToday(selection.date) ? L10n.text("%@ 今日视图", language: leafyLanguage, AppBrand.displayName) : L10n.text("%@ 日程视图", language: leafyLanguage, AppBrand.displayName))
                        .microCaption()
                        .foregroundStyle(AppTheme.accentEmphasis)
                    Text(DateFormatters.header.string(from: selection.date))
                        .title2()
                        .foregroundStyle(AppTheme.primaryText)
                }

                Spacer()

                Button(action: shareAction) {
                    TimetableShareIcon()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("分享日程")
            }

            HStack(alignment: .center, spacing: 12) {
                LeafyIconBadge(systemName: "cloud.sun")

                VStack(alignment: .leading, spacing: 4) {
                    Text("现在天气")
                        .microCaption()
                        .foregroundStyle(AppTheme.secondaryText)
                    Text(weatherText)
                        .leafyHeadline()
                        .foregroundStyle(AppTheme.primaryText)
                }

                Spacer()
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text(dayCourses.isEmpty ? L10n.text("课程", language: leafyLanguage) : L10n.text("课程 %d 门", language: leafyLanguage, dayCourses.count))
                    .microCaption()
                    .foregroundStyle(AppTheme.secondaryText)

                if dayCourses.isEmpty {
                    Text("这一天没有课程安排。")
                        .leafyBody()
                        .foregroundStyle(AppTheme.secondaryText)
                } else {
                    ForEach(dayCourses) { course in
                        DayCourseListRow(course: course)
                    }
                }
            }

            if !dayExams.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.text("考试 %d 场", language: leafyLanguage, dayExams.count))
                        .microCaption()
                        .foregroundStyle(AppTheme.warning)

                    ForEach(dayExams) { exam in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(AppTheme.warning)
                                .frame(width: 22)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(exam.name)
                                    .leafyHeadline()
                                    .foregroundStyle(AppTheme.primaryText)
                                Text("\(exam.start)-\(exam.end)  \(exam.location)")
                                    .microCaption()
                                    .foregroundStyle(AppTheme.secondaryText)
                                    .lineLimit(2)
                            }

                            Spacer(minLength: 0)
                        }
                    }
                }
            }

            if let cacheText {
                Text(cacheText)
                    .microCaption()
                    .foregroundStyle(lastFailureMessage == nil ? AppTheme.tertiaryText : AppTheme.warning)
            }
        }
        .padding(18)
        .leafyCardStyle()
    }

    private var cacheText: String? {
        if let lastFailureMessage, !lastFailureMessage.isEmpty {
            return L10n.text("正在使用本地缓存，上次同步失败：%@", language: leafyLanguage, lastFailureMessage)
        }

        return L10n.text("分享于 %@", language: leafyLanguage, DateFormatters.headerWithTime.string(from: Date()))
    }

}

struct TimetableShareIcon: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(AppTheme.softFill)
                .frame(width: 34, height: 34)

            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 15, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(AppTheme.accentEmphasis)
                .frame(width: 20, height: 20, alignment: .center)
        }
        .frame(width: 34, height: 34)
        .contentShape(Circle())
    }
}

struct DayCourseListRow: View {
    let course: Course

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "book.closed")
                .foregroundStyle(AppTheme.accentEmphasis)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(course.displayCourseName)
                    .leafyHeadline()
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(2)
                Text("\(timeText(for: course))  \(course.locationText)")
                    .microCaption()
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
    }

    private func timeText(for course: Course) -> String {
        guard let startPeriod = course.duration.min(),
              let endPeriod = course.duration.max(),
              let startSlot = TimetablePeriodSchedule.slot(for: startPeriod),
              let endSlot = TimetablePeriodSchedule.slot(for: endPeriod)
        else {
            return course.durationTextForShare
        }

        return "\(startSlot.startText)-\(endSlot.endText)"
    }
}

struct DayScheduleImagePreviewSheet: View {
    let image: UIImage

    @Environment(\.dismiss) private var dismiss
    @State private var isSharing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.card) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
                        .shadow(color: Color.black.opacity(0.10), radius: 18, x: 0, y: 10)

                    Text("点击右上角分享，可发送到聊天、动态或保存到相册。")
                        .microCaption()
                        .foregroundStyle(AppTheme.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .padding(AppSpacing.page)
            }
            .background(LeafyPageBackground())
            .navigationTitle("分享预览")
            .leafyInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .leafyLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .leafyTrailing) {
                    Button("分享") {
                        isSharing = true
                    }
                    .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $isSharing) {
                ShareSheet(activityItems: [image])
            }
        }
    }
}

struct DayScheduleShareImageCard: View {
    @Environment(\.leafyLanguage) private var leafyLanguage

    let selection: TimetableDaySelection
    let courses: [Course]
    let weatherText: String
    let displayName: String

    private var dayCourses: [Course] {
        courses
            .filter { $0.weeks.contains(selection.week) && $0.dayOfWeek == selection.day }
            .sortedByStartPeriod()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(Calendar.current.isDateInToday(selection.date) ? L10n.text("%@ 今日视图", language: leafyLanguage, AppBrand.displayName) : L10n.text("%@ 日程视图", language: leafyLanguage, AppBrand.displayName))
                        .microCaption()
                        .foregroundStyle(AppTheme.accentEmphasis)
                    Text(DateFormatters.header.string(from: selection.date))
                        .title2()
                        .foregroundStyle(AppTheme.primaryText)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 4) {
                    Text(displayName)
                        .leafyHeadline()
                        .foregroundStyle(AppTheme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(L10n.text("的日程卡片", language: leafyLanguage))
                        .microCaption()
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }

            HStack(alignment: .center, spacing: 12) {
                LeafyIconBadge(systemName: "cloud.sun")

                VStack(alignment: .leading, spacing: 5) {
                    Text("现在天气")
                        .microCaption()
                        .foregroundStyle(AppTheme.secondaryText)

                    Text(weatherText)
                        .leafyHeadline()
                        .foregroundStyle(AppTheme.primaryText)
                        .lineLimit(2)
                }
            }

            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Text(dayCourses.isEmpty ? L10n.text("课程", language: leafyLanguage) : L10n.text("课程 %d 门", language: leafyLanguage, dayCourses.count))
                    .microCaption()
                    .foregroundStyle(AppTheme.secondaryText)

                if dayCourses.isEmpty {
                    Text("这一天没有课程安排。")
                        .leafyBody()
                        .foregroundStyle(AppTheme.secondaryText)
                } else {
                    ForEach(dayCourses) { course in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "book.closed")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.accentEmphasis)
                                .frame(width: 22)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(course.displayCourseName)
                                    .leafyHeadline()
                                    .foregroundStyle(AppTheme.primaryText)
                                    .lineLimit(2)
                                Text("\(timeText(for: course))  \(course.locationText)")
                                    .microCaption()
                                    .foregroundStyle(AppTheme.secondaryText)
                                    .lineLimit(2)
                            }

                            Spacer(minLength: 0)
                        }
                    }
                }
            }

            HStack {
                Text(L10n.text("来自 %@", language: leafyLanguage, AppBrand.displayName))
                    .microCaption()
                    .foregroundStyle(AppTheme.tertiaryText)
                Spacer()
                Text(L10n.text("分享于 %@", language: leafyLanguage, DateFormatters.headerWithTime.string(from: Date())))
                    .microCaption()
                    .foregroundStyle(AppTheme.tertiaryText)
            }
        }
        .padding(18)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
                .stroke(AppTheme.separator, lineWidth: 1)
        )
    }

    private func timeText(for course: Course) -> String {
        guard let startPeriod = course.duration.min(),
              let endPeriod = course.duration.max(),
              let startSlot = TimetablePeriodSchedule.slot(for: startPeriod),
              let endSlot = TimetablePeriodSchedule.slot(for: endPeriod)
        else {
            return course.durationTextForShare
        }

        return "\(startSlot.startText)-\(endSlot.endText)"
    }
}

struct DayScheduleSummary {
    let headline: String
    let primaryText: String
    let secondaryText: String
    let icon: String
    let tint: Color
    let exam: ExamArrangement?

    init(selection: TimetableDaySelection, courses: [Course], exams: [ExamArrangement], now: Date) {
        let isToday = Calendar.current.isDateInToday(selection.date)
        let dayExam = exams
            .sorted { ($0.startsAt ?? .distantFuture) < ($1.startsAt ?? .distantFuture) }
            .first { exam in
                guard let startsAt = exam.startsAt else { return false }
                return Calendar.current.isDate(startsAt, inSameDayAs: selection.date)
            }
        let fallbackExam = isToday ? exams.nextRelevantExam(from: now) : nil
        exam = dayExam ?? fallbackExam

        if isToday {
            headline = courses.isEmpty ? L10n.text("今日无课") : L10n.text("今日 %d 门课", courses.count)

            let activeCourse = courses.first { course in
                guard let start = TimetablePeriodSchedule.startDate(for: course, week: selection.week),
                      let end = TimetablePeriodSchedule.endDate(for: course, week: selection.week)
                else {
                    return false
                }
                return start <= now && now <= end
            }

            if let activeCourse,
               let end = TimetablePeriodSchedule.endDate(for: activeCourse, week: selection.week) {
                primaryText = L10n.text("正在上：%@", activeCourse.displayCourseName)
                secondaryText = L10n.text("%@ · 距离下课 %@", activeCourse.locationText, Self.relativeMinutes(from: now, to: end))
                icon = "clock.badge.checkmark"
                tint = AppTheme.accent
                return
            }

            let nextCourse = courses.first { course in
                guard let start = TimetablePeriodSchedule.startDate(for: course, week: selection.week) else { return false }
                return start > now
            }

            if let nextCourse,
               let start = TimetablePeriodSchedule.startDate(for: nextCourse, week: selection.week) {
                primaryText = L10n.text("下一节：%@", nextCourse.displayCourseName)
                secondaryText = L10n.text("%@ · 距离上课 %@", nextCourse.locationText, Self.relativeMinutes(from: now, to: start))
                icon = "calendar.badge.clock"
                tint = AppTheme.accent
            } else if courses.isEmpty {
                primaryText = exam == nil ? L10n.text("今天没有课程安排") : L10n.text("今天没有课程，注意考试安排")
                secondaryText = L10n.text("可以去发现页找自习室或查看考试与日程。")
                icon = "checkmark.seal"
                tint = AppTheme.accentSecondary
            } else {
                primaryText = L10n.text("今日课程已结束")
                secondaryText = L10n.text("可以分享今日课表，或切换周次查看后续安排。")
                icon = "moon"
                tint = AppTheme.accentSecondary
            }
        } else {
            headline = courses.isEmpty ? L10n.text("当天无课") : L10n.text("%d 门课", courses.count)
            if let firstCourse = courses.first {
                primaryText = L10n.text("第一节：%@", firstCourse.displayCourseName)
                secondaryText = "\(firstCourse.durationTextForShare) · \(firstCourse.locationText)"
                icon = "calendar"
                tint = AppTheme.accent
            } else {
                primaryText = exam == nil ? L10n.text("这一天没有课程安排") : L10n.text("这一天没有课程，注意考试安排")
                secondaryText = L10n.text("可继续查看其他日期或切换周次。")
                icon = "checkmark.seal"
                tint = AppTheme.accentSecondary
            }
        }
    }

    private static func relativeMinutes(from start: Date, to end: Date) -> String {
        let minutes = max(0, Int(ceil(end.timeIntervalSince(start) / 60)))
        if minutes < 60 { return L10n.text("%d 分钟", minutes) }
        return L10n.text("%d 小时 %d 分钟", minutes / 60, minutes % 60)
    }
}

enum DayScheduleShareBuilder {
    static func text(selection: TimetableDaySelection, courses: [Course], exams: [ExamArrangement]) -> String {
        let dayCourses = courses
            .filter { $0.weeks.contains(selection.week) && $0.dayOfWeek == selection.day }
            .sortedByStartPeriod()
        var lines = [L10n.text("%@ 日程", AppBrand.displayName), DateFormatters.header.string(from: selection.date)]

        if dayCourses.isEmpty {
            lines.append(L10n.text("当天无课"))
        } else {
            lines.append(contentsOf: dayCourses.map { course in
                "\(course.durationTextForShare) \(course.courseName) @ \(course.locationTextForShare)"
            })
        }

        let dayExams = exams
            .sorted { ($0.startsAt ?? .distantFuture) < ($1.startsAt ?? .distantFuture) }
            .filter { exam in
                guard let startsAt = exam.startsAt else { return false }
                return Calendar.current.isDate(startsAt, inSameDayAs: selection.date)
            }

        for exam in dayExams {
            lines.append(L10n.text("考试：%@ %@ %@ @ %@", exam.name, exam.date, exam.start, exam.location))
        }

        return lines.joined(separator: "\n")
    }
}

struct TodayScheduleSummaryCard: View {
    @Environment(\.leafyLanguage) private var leafyLanguage

    let courses: [Course]
    let exams: [ExamArrangement]
    let lastSyncAt: Date?
    let lastFailureMessage: String?
    let shareAction: () -> Void

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 60)) { context in
            let summary = TodayScheduleSummary(courses: courses, exams: exams, now: context.date)

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(DateFormatters.header.string(from: context.date))
                            .microCaption()
                            .foregroundStyle(AppTheme.secondaryText)
                        Text(summary.headline)
                            .title2()
                            .foregroundStyle(AppTheme.primaryText)
                    }

                    Spacer()

                    Button(action: shareAction) {
                        TimetableShareIcon()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.text("分享今日课表", language: leafyLanguage))
                }

                HStack(alignment: .top, spacing: 12) {
                    LeafyIconBadge(systemName: summary.icon, tint: summary.tint)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(summary.primaryText)
                            .leafyHeadline()
                            .foregroundStyle(AppTheme.primaryText)
                            .lineLimit(2)

                        Text(summary.secondaryText)
                            .leafyBody()
                            .foregroundStyle(AppTheme.secondaryText)
                            .lineLimit(2)
                    }

                    Spacer()
                }

                if let exam = summary.nextExam {
                    Divider()
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .foregroundStyle(AppTheme.accentEmphasis)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L10n.text("考试 %@", language: leafyLanguage, exam.name))
                                .leafyHeadline()
                            Text("\(exam.date) \(exam.start)  \(exam.location)")
                                .microCaption()
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                    }
                }

                if let cacheText {
                    Text(cacheText)
                        .microCaption()
                        .foregroundStyle(lastFailureMessage == nil ? AppTheme.tertiaryText : AppTheme.warning)
                }
            }
            .padding(18)
            .leafyCardStyle()
        }
    }

    private var cacheText: String? {
        if let lastFailureMessage, !lastFailureMessage.isEmpty {
            return L10n.text("正在使用本地缓存，上次同步失败：%@", language: leafyLanguage, lastFailureMessage)
        }

        return L10n.text("分享于 %@", language: leafyLanguage, DateFormatters.headerWithTime.string(from: Date()))
    }
}

struct TodayScheduleSummary {
    let headline: String
    let primaryText: String
    let secondaryText: String
    let icon: String
    let tint: Color
    let nextExam: ExamArrangement?

    init(courses: [Course], exams: [ExamArrangement], now: Date) {
        let schedule = SemesterConfig.weekAndDay(for: now)
        let todayCourses = courses
            .filter { $0.weeks.contains(schedule.week) && $0.dayOfWeek == schedule.day }
            .sortedByStartPeriod()
        let nextExam = exams.nextRelevantExam(from: now)
        self.nextExam = nextExam

        headline = todayCourses.isEmpty ? L10n.text("今日无课") : L10n.text("今日 %d 门课", todayCourses.count)

        let activeCourse = todayCourses.first { course in
            guard let start = TimetablePeriodSchedule.startDate(for: course, week: schedule.week),
                  let end = TimetablePeriodSchedule.endDate(for: course, week: schedule.week)
            else {
                return false
            }
            return start <= now && now <= end
        }

        if let activeCourse,
           let end = TimetablePeriodSchedule.endDate(for: activeCourse, week: schedule.week) {
            primaryText = L10n.text("正在上：%@", activeCourse.displayCourseName)
            secondaryText = L10n.text("%@ · 距离下课 %@", activeCourse.locationText, Self.relativeMinutes(from: now, to: end))
            icon = "clock.badge.checkmark"
            tint = AppTheme.accent
            return
        }

        let nextCourse = todayCourses.first { course in
            guard let start = TimetablePeriodSchedule.startDate(for: course, week: schedule.week) else { return false }
            return start > now
        }

        if let nextCourse,
           let start = TimetablePeriodSchedule.startDate(for: nextCourse, week: schedule.week) {
            primaryText = L10n.text("下一节：%@", nextCourse.displayCourseName)
            secondaryText = L10n.text("%@ · 距离上课 %@", nextCourse.locationText, Self.relativeMinutes(from: now, to: start))
            icon = "calendar.badge.clock"
            tint = AppTheme.accent
        } else if todayCourses.isEmpty {
            primaryText = nextExam == nil ? L10n.text("今天没有课程安排") : L10n.text("今天没有课程，注意考试安排")
            secondaryText = L10n.text("可以去发现页找自习室或查看考试与日程。")
            icon = "checkmark.seal"
            tint = AppTheme.accentSecondary
        } else {
            primaryText = L10n.text("今日课程已结束")
            secondaryText = L10n.text("可以分享今日课表，或切换周次查看后续安排。")
            icon = "moon"
            tint = AppTheme.accentSecondary
        }
    }

    private static func relativeMinutes(from start: Date, to end: Date) -> String {
        let minutes = max(0, Int(ceil(end.timeIntervalSince(start) / 60)))
        if minutes < 60 { return L10n.text("%d 分钟", minutes) }
        return L10n.text("%d 小时 %d 分钟", minutes / 60, minutes % 60)
    }
}

enum ClassPeriodSchedule {
    struct Slot {
        let period: Int
        let startHour: Int
        let startMinute: Int
        let endHour: Int
        let endMinute: Int
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
        Slot(period: 12, startHour: 20, startMinute: 10, endHour: 20, endMinute: 55)
    ]

    static func periodForFocus(containing date: Date) -> Slot? {
        let calendar = Calendar.current
        let minutes = calendar.component(.hour, from: date) * 60
            + calendar.component(.minute, from: date)

        return slots.first { slot in
            minutes <= slot.endHour * 60 + slot.endMinute
        } ?? slots.last
    }

    static func period(containing date: Date) -> Slot? {
        let calendar = Calendar.current
        let minutes = calendar.component(.hour, from: date) * 60
            + calendar.component(.minute, from: date)

        return slots.first { slot in
            let start = slot.startHour * 60 + slot.startMinute
            let end = slot.endHour * 60 + slot.endMinute
            return (start...end).contains(minutes)
        }
    }
}
