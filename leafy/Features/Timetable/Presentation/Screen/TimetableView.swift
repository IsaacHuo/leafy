import SwiftData
import SwiftSoup
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

private struct CourseNotePreview: Identifiable {
    let id = UUID()
    let courseName: String
    let note: String?

    var message: String {
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty
            ? "\(courseName) 暂无备注。"
            : trimmed
    }
}

private enum TimetableQuickAccessAction: Equatable, Sendable {
    case processTimetable
    case shareTimetable
    case emptyClassroom
    case addSchedule
    case exportTimetable
}

struct TimetableView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.leafyControlScale) private var leafyControlScale
    @Environment(\.leafyLanguage) private var leafyLanguage
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.leafyThemeColorPreference) private var themeColorPreference
    @Environment(\.leafyDependencies) private var dependencies
    @EnvironmentObject private var appNavigation: AppNavigationCoordinator
    @Query private var courses: [Course]
    @Query private var cellReminders: [TimetableCellReminder]
    @Query private var courseNotes: [CourseNote]
    @Query private var occurrenceNotes: [CourseOccurrenceNote]
    @Query private var courseReminderSettings: [CourseReminderSetting]

    @State private var networkManager = ActiveCampusContext.networkManager
    @State private var isFetching = false
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var reauthenticationRequest: SchoolReauthenticationRequest?
    @State private var selectedCourseContext: SelectedCourseContext?
    @State private var selectedCellReminderContext: TimetableCellReminderContext?
    @State private var selectedCustomScheduleEditor: CustomScheduleEditorPresentation?
    @State private var courseNotePreview: CourseNotePreview?
    @State private var isExportSheetPresented = false
    @State private var isTimetableProcessingPresented = false
    @State private var isQuickAccessPresented = false
    @State private var pendingQuickAccessAction: TimetableQuickAccessAction?
    @State private var currentWeek: Int = SemesterConfig.currentWeek()
    @State private var scrollToWeek: Int? = SemesterConfig.currentWeek()
    @State private var isAwayFromCurrentSchedule = false
    @State private var selectedDaySummary: TimetableDaySelection?
    @State private var lastSyncAt = TimetableCacheMetadata.lastSyncAt
    @State private var lastFailureMessage = TimetableCacheMetadata.lastFailureMessage
    @State private var isTimetableInteractivelyLaidOut = false
    @State private var timetableGridSnapshot: TimetableGridSnapshot?
    @State private var timetableGridSnapshotCache = TimetableGridSnapshotCache()
    @State private var timetableLayoutMetricsCache = TimetableLayoutMetricsCache()
    @State private var timetableDayMetadataCache = TimetableDayMetadataCache()
    @State private var timetableAgendaItemCache = TimetableAgendaItemCache()
    @State private var isWeatherAdvicePresented = false
    @State private var cachedTimetableWeather: TimetableWeatherSnapshot?
    @State private var customCountdownEvents = CustomScheduleStore.load()
    @State private var cachedExamArrangements = SchoolDataCache.loadExamSchedule()
    @State private var calendarEventSignature = AcademicCalendarEvents.displayEvents()
    @State private var timetableScheduleProjectionSnapshot = TimetableScheduleProjectionSnapshot.make(
        countdownEvents: CustomScheduleStore.load(),
        exams: SchoolDataCache.loadExamSchedule()
    )
    @State private var timetableBackgroundImage: UIImage?
    @State private var timetableBackgroundLoadTask: Task<Void, Never>?

    @AppStorage("hasSeenTimetableOnboarding") private var hasSeenTimetableOnboarding = false
    @AppStorage("timetableHidesWeekends") private var timetableHidesWeekends = false
    @AppStorage(TimetableBackgroundStore.isEnabledKey) private var timetableBackgroundIsEnabled = false
    @AppStorage(TimetableBackgroundStore.filenameKey) private var timetableBackgroundFilename = ""
    @AppStorage(TimetableBackgroundStore.displayModeKey) private var timetableBackgroundDisplayModeRaw = TimetableBackgroundDisplayMode.fill.rawValue
    @AppStorage(TimetableBackgroundStore.imageOpacityKey) private var timetableBackgroundImageOpacity = TimetableBackgroundStore.defaultImageOpacity
    @AppStorage(TimetableBackgroundStore.blurRadiusKey) private var timetableBackgroundBlurRadius = TimetableBackgroundStore.defaultBlurRadius
    @AppStorage(TimetableBackgroundStore.overlayOpacityKey) private var timetableBackgroundOverlayOpacity = TimetableBackgroundStore.defaultOverlayOpacity
    @AppStorage(TimetableBackgroundStore.courseCardOpacityKey) private var timetableBackgroundCourseCardOpacity = TimetableBackgroundStore.defaultCourseCardOpacity
    @AppStorage(TimetableBackgroundStore.lightPaletteKey) private var timetableBackgroundLightPalette = ""
    @AppStorage(TimetableBackgroundStore.darkPaletteKey) private var timetableBackgroundDarkPalette = ""

    private var totalWeeks: Int { SemesterConfig.supportedWeeks }
    private let totalClasses = 13
    private var overviewRowSpacing: CGFloat { 1.5 * leafyControlScale }
    private var overviewCardInset: CGFloat { 1.5 * leafyControlScale }
    private var overviewMinimumRowHeight: CGFloat { 26 * leafyControlScale }
    private var overviewBottomClearance: CGFloat { 16 * leafyControlScale }
    private var axisWidth: CGFloat { 34 * leafyControlScale }
    private var headerHeight: CGFloat { 52 * leafyControlScale }
    private var timetableHorizontalPadding: CGFloat { 4 * leafyControlScale }
    private var timetableDaySpacing: CGFloat { 5 * leafyControlScale }
    private var timetableWeekSpacing: CGFloat { 6 * leafyControlScale }
    private var allowsTimetableAgendaFallback: Bool {
#if os(macOS)
        true
#else
        UIDevice.current.userInterfaceIdiom == .pad
#endif
    }
    private var showsToolbarRefreshButton: Bool {
#if os(macOS)
        true
#else
        UIDevice.current.userInterfaceIdiom == .pad
#endif
    }

    private var isCustomCampus: Bool {
        ActiveCampusContext.identity?.isCustom == true
    }

    private var visibleDays: [Int] {
        timetableGridSnapshot?.visibleDays ?? (timetableHidesWeekends ? Array(1...5) : Array(1...7))
    }

    private var usesCustomTimetableBackground: Bool {
        timetableBackgroundIsEnabled && timetableBackgroundImage != nil
    }

    private var timetableBackgroundDisplayMode: TimetableBackgroundDisplayMode {
        TimetableBackgroundDisplayMode(rawValue: timetableBackgroundDisplayModeRaw) ?? .fill
    }

    private var timetableBackgroundCoursePalette: [Color]? {
        guard usesCustomTimetableBackground else { return nil }
        let rawPalette = colorScheme == .dark ? timetableBackgroundDarkPalette : timetableBackgroundLightPalette
        let colors = TimetableBackgroundStore.colors(from: rawPalette)
        if !colors.isEmpty { return colors }

        let fallbackHexes = colorScheme == .dark
            ? TimetableBackgroundPalette.fallbackDarkHexes
            : TimetableBackgroundPalette.fallbackLightHexes
        return fallbackHexes.compactMap { TimetableBackgroundStore.colors(from: $0).first }
    }

    private var timetableRenderInput: TimetableRenderInput {
        TimetableRenderInput(
            courses: courses,
            notes: courseNotes,
            occurrenceNotes: occurrenceNotes,
            cellReminders: cellReminders,
            hidesWeekends: timetableHidesWeekends
        )
    }

    var body: some View {
        rootAlerts
    }

    private var rootNavigation: some View {
        NavigationStack {
            VStack(spacing: AppSpacing.compact) {
                if !networkManager.hasCachedIdentity {
                    unauthenticatedState
                        .padding(.horizontal, AppSpacing.page)
                } else if isFetching && courses.isEmpty {
                    loadingState
                        .padding(.horizontal, AppSpacing.page)
                } else if courses.isEmpty {
                    VStack(spacing: 14) {
                        emptyState(
                            title: "暂无课表",
                            description: isCustomCampus
                                ? "添加课程或导入文件后显示。"
                                : "还没有本地课表缓存。连接校园网后在“我的”页重新拉取。"
                        )

                        if isCustomCampus {
                            Button {
                                isTimetableProcessingPresented = true
                            } label: {
                                Label("课表处理", systemImage: "slider.horizontal.3")
                                    .font(.headline)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(AppTheme.accent(for: themeColorPreference))
                        }
                    }
                    .padding(.horizontal, AppSpacing.page)
                } else {
                    timetableContent
                }
            }
            .padding(.top, AppSpacing.micro)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(timetablePageBackground)
            .tint(AppTheme.accent(for: themeColorPreference))
            .navigationTitle("")
            .leafyInlineNavigationTitle()
            .toolbar {
                leadingToolbarItems

                ToolbarItemGroup(placement: .leafyTrailing) {
                    if isAwayFromCurrentSchedule {
                        toolbarReturnButton
                            .transition(returnButtonTransition)
                    }
                    toolbarWeekMenu
                    if showsToolbarRefreshButton {
                        toolbarRefreshButton
                    }
                }
            }
            .navigationDestination(isPresented: $isTimetableProcessingPresented) {
                TimetableProcessingView()
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.86), value: isAwayFromCurrentSchedule)
        }
    }

    private var rootLifecycle: some View {
        rootBackgroundLifecycle
    }

    private var rootBaseLifecycle: some View {
        rootDataLifecycle
        .onChange(of: appNavigation.requestedTimetableCourseID) { _, requestedID in
            handleTimetableCourseDeepLink(requestedID)
        }
        .onReceive(NotificationCenter.default.publisher(for: .customCountdownEventsDidChange)) { _ in
            reloadCustomCountdownEvents()
        }
        .onReceive(NotificationCenter.default.publisher(for: .schoolExamScheduleDidChange)) { _ in
            reloadExamArrangements()
        }
        .onReceive(NotificationCenter.default.publisher(for: .schoolDataDidRefresh)) { notification in
            handleSchoolDataRefresh(notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: .semesterRuntimeConfigDidChange)) { _ in
            applySemesterRuntimeConfig(SemesterConfig.current)
        }
        .onReceive(NotificationCenter.default.publisher(for: .nationalCalendarRuntimeConfigDidChange)) { _ in
            handleNationalCalendarRuntimeConfigChange()
        }
    }

    private var rootPresentationLifecycle: some View {
        rootNavigation
        .task {
            await handleInitialTask()
            await maintainTimetableWeatherPreview()
        }
        .onAppear(perform: handleAppear)
        .onChange(of: scenePhase) { _, newPhase in
            handleScenePhaseChange(newPhase)
        }
        .onChange(of: currentWeek) { _, newValue in
            handleCurrentWeekChange(newValue)
        }
        .onChange(of: timetableHidesWeekends) { _, _ in
            handleWeekendVisibilityChange()
        }
    }

    private var rootDataLifecycle: some View {
        rootPresentationLifecycle
        .onChange(of: courses.count) { _, _ in
            handleCoursesCountChange()
        }
        .onChange(of: courseNotes.count) { _, _ in
            handleCourseNotesCountChange()
        }
        .onChange(of: occurrenceNotes.count) { _, _ in
            handleCourseNotesCountChange()
        }
        .onChange(of: courseReminderSettings.count) { _, _ in
            handleCourseReminderSettingsCountChange()
        }
        .onChange(of: cellReminders.count) { _, _ in
            handleCellRemindersCountChange()
        }
        .onChange(of: timetableRenderInput.signature) { _, _ in
            handleTimetableGridInputChange()
        }
    }

    private var rootBackgroundLifecycle: some View {
        rootBaseLifecycle
        .onChange(of: timetableBackgroundFilename) { _, _ in
            reloadTimetableBackgroundImage()
        }
        .onChange(of: timetableBackgroundIsEnabled) { _, _ in
            reloadTimetableBackgroundImage()
        }
        .onReceive(NotificationCenter.default.publisher(for: .timetableBackgroundSettingsDidChange)) { _ in
            reloadTimetableBackgroundImage()
        }
    }

    private var timetablePageBackground: some View {
        ZStack {
            LeafyPageBackground()

            if timetableBackgroundIsEnabled, let timetableBackgroundImage {
                TimetableBackgroundImageLayer(
                    image: timetableBackgroundImage,
                    displayMode: timetableBackgroundDisplayMode,
                    imageOpacity: timetableBackgroundImageOpacity,
                    blurRadius: timetableBackgroundBlurRadius,
                    overlayOpacity: timetableBackgroundOverlayOpacity
                )
            }
        }
    }

    private var rootSheets: some View {
        rootLifecycle
        .sheet(item: $selectedCourseContext) { context in
                CourseDetailSheet(context: context)
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $selectedCellReminderContext) { context in
            TimetableCellReminderSheet(context: context)
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $selectedCustomScheduleEditor, onDismiss: reloadCustomCountdownEvents) { presentation in
            CustomScheduleEditorSheet(presentation: presentation)
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $selectedDaySummary) { selection in
            DayScheduleSummarySheet(
                selection: selection,
                courses: courses,
                exams: cachedExamArrangements,
                lastSyncAt: lastSyncAt,
                lastFailureMessage: lastFailureMessage
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $isExportSheetPresented) {
            TimetableExportSheet(
                currentWeek: currentWeek,
                courses: courses,
                courseNotes: courseNotes,
                occurrenceNotes: occurrenceNotes,
                cellReminders: cellReminders,
                exams: cachedExamArrangements,
                lastSyncAt: lastSyncAt,
                lastFailureMessage: lastFailureMessage,
                includesWeekendsByDefault: !timetableHidesWeekends
            )
            .presentationDetents([.large])
        }
        .sheet(isPresented: $isWeatherAdvicePresented, onDismiss: {
            Task { await refreshTimetableWeatherPreview() }
        }) {
            TimetableWeatherAdviceSheet(
                currentWeek: currentWeek,
                courses: courses,
                cellReminders: cellReminders,
                exams: cachedExamArrangements,
                weatherPreview: $cachedTimetableWeather
            )
            .presentationDetents([.medium, .large])
        }
    }

    private var rootAlerts: some View {
        rootSheets
        .alert("提示", isPresented: $showAlert) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
        .alert("欢迎使用 \(AppBrand.displayName)", isPresented: onboardingAlertBinding) {
            Button("知道了", role: .cancel) {
                hasSeenTimetableOnboarding = true
            }
        } message: {
            Text(onboardingMessage)
        }
        .alert(item: $courseNotePreview) { preview in
            Alert(
                title: Text("课程备注"),
                message: Text(preview.message),
                dismissButton: .default(Text("知道了"))
            )
        }
        .schoolReauthenticationSheet(
            request: $reauthenticationRequest,
            networkManager: networkManager
        ) { _ in
            Task { await fetchAndParseTimetable(userInitiated: true) }
        }
    }

    private var onboardingAlertBinding: Binding<Bool> {
        Binding(
            get: { networkManager.hasCachedIdentity && isTimetableInteractivelyLaidOut && !hasSeenTimetableOnboarding },
            set: { if !$0 { hasSeenTimetableOnboarding = true } }
        )
    }

    private var onboardingMessage: String {
        if isCustomCampus {
            return "通用入口的课表、成绩和考试安排来自你手动导入的 CSV 文件；数据只保存在本机当前账号作用域内。"
        }
        return "课表、成绩和考试安排来自学校教务系统；课表和成绩缓存保存在本机，离线时仍可查看。社区资料和你主动发布的内容会保存到 \(AppBrand.displayName) 的社区服务。"
    }

    private func handleInitialTask() async {
        let semesterConfig = await SemesterConfig.refreshRemoteIfAvailable()
        await MainActor.run {
            applySemesterRuntimeConfig(semesterConfig)
        }
        await refreshTimetableWeatherPreview()
        syncTimetableGridSnapshot()
        syncReturnButtonVisibility()
    }

    private func handleAppear() {
        syncTimetableGridSnapshot()
        reloadTimetableBackgroundImage()
        reloadCustomCountdownEvents()
        reloadExamArrangements()
        syncReturnButtonVisibility()
        publishWidgetSnapshot()
        refreshScheduleReportNotifications()
    }

    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        guard newPhase == .active else { return }
        reloadExamArrangements()
        if !isWeatherAdvicePresented {
            Task { await refreshTimetableWeatherPreview() }
        }
        syncReturnButtonVisibility()
        publishWidgetSnapshot()
    }

    private func handleCurrentWeekChange(_ newValue: Int) {
        syncReturnButtonVisibility(for: newValue)
    }

    private func handleWeekendVisibilityChange() {
        syncTimetableGridSnapshot()
        scrollToWeek = currentWeek
    }

    private func handleCoursesCountChange() {
        syncTimetableGridSnapshot()
        if courses.isEmpty {
            isTimetableInteractivelyLaidOut = false
        }
        syncReturnButtonVisibility()
        publishWidgetSnapshot()
        refreshScheduleReportNotifications()
    }

    private func handleCourseNotesCountChange() {
        syncTimetableGridSnapshot()
        publishWidgetSnapshot()
    }

    private func handleCourseReminderSettingsCountChange() {
        publishWidgetSnapshot()
    }

    private func handleCellRemindersCountChange() {
        syncTimetableGridSnapshot()
        publishWidgetSnapshot()
        refreshScheduleReportNotifications()
    }

    private func handleTimetableGridInputChange() {
        syncTimetableGridSnapshot()
    }

    private func handleNationalCalendarRuntimeConfigChange() {
        calendarEventSignature = AcademicCalendarEvents.displayEvents()
        syncTimetableScheduleProjectionSnapshot()
        publishWidgetSnapshot()
        refreshScheduleReportNotifications()
    }

    private func handleSchoolDataRefresh(_ notification: Notification) {
        let event = notification.object as? SchoolDataRefreshEvent
        guard event?.contains(.timetable) == true || event?.contains(.exams) == true else { return }

        if event?.contains(.timetable) == true {
            lastSyncAt = TimetableCacheMetadata.lastSyncAt
            lastFailureMessage = TimetableCacheMetadata.lastFailureMessage
            syncTimetableGridSnapshot()
            syncReturnButtonVisibility()
        }
        if event?.contains(.exams) == true {
            reloadExamArrangements()
        }
        refreshScheduleReportNotifications()
        publishWidgetSnapshot()
    }

    private func reloadCustomCountdownEvents() {
        customCountdownEvents = CustomScheduleStore.load()
        syncTimetableScheduleProjectionSnapshot()
        refreshScheduleReportNotifications()
    }

    private func reloadExamArrangements() {
        cachedExamArrangements = SchoolDataCache.loadExamSchedule()
        syncTimetableScheduleProjectionSnapshot()
        refreshScheduleReportNotifications()
    }

    @MainActor
    private func refreshTimetableWeatherPreview() async {
        let weatherService = dependencies.timetableWeatherService
        guard weatherService.authorizationState() == .authorized else {
            cachedTimetableWeather = nil
            return
        }

        if let cached = weatherService.cachedWeather(maxAge: 30 * 60) {
            cachedTimetableWeather = cached
            return
        }

        cachedTimetableWeather = nil
        do {
            cachedTimetableWeather = try await weatherService.fetchCurrentWeather(
                requestsPermissionIfNeeded: false
            )
        } catch {
            cachedTimetableWeather = nil
        }
    }

    private func maintainTimetableWeatherPreview() async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(30 * 60))
            } catch {
                return
            }

            if !isWeatherAdvicePresented {
                await refreshTimetableWeatherPreview()
            }
        }
    }

    private func refreshScheduleReportNotifications() {
        Task { @MainActor in
            try? await ScheduleReportNotificationManager.refreshIfEnabled(modelContext: modelContext)
        }
    }

    @MainActor
    private func applySemesterRuntimeConfig(_ config: SemesterRuntimeConfig) {
        let week = SemesterConfig.currentWeek(config: config)
        currentWeek = week
        scrollToWeek = week
        calendarEventSignature = AcademicCalendarEvents.displayEvents()
        timetableGridSnapshot = nil
        syncTimetableGridSnapshot()
        syncTimetableScheduleProjectionSnapshot()
        syncReturnButtonVisibility(for: week)
        publishWidgetSnapshot()
    }

    private func reloadTimetableBackgroundImage() {
        timetableBackgroundLoadTask?.cancel()
        guard timetableBackgroundIsEnabled else {
            timetableBackgroundImage = nil
            return
        }
        let filename = timetableBackgroundFilename
        timetableBackgroundLoadTask = Task {
            let image = await TimetableBackgroundStore.image(filename: filename)
            guard !Task.isCancelled, filename == timetableBackgroundFilename else { return }
            timetableBackgroundImage = image
        }
    }

    private func handleTimetableCourseDeepLink(_ requestedID: UUID?) {
        guard let requestedID else { return }
        openCourseFromDeepLink(id: requestedID)
        appNavigation.requestedTimetableCourseID = nil
    }

    @ToolbarContentBuilder
    private var leadingToolbarItems: some ToolbarContent {
#if os(iOS)
        if #available(iOS 26.0, *) {
            ToolbarItem(placement: .leafyLeading) {
                quickAccessMenu
            }
            ToolbarSpacer(.fixed, placement: .leafyLeading)
            ToolbarItem(placement: .leafyLeading) {
                timetableWeatherButton
            }
        } else {
            ToolbarItem(placement: .leafyLeading) {
                HStack(spacing: 8 * leafyControlScale) {
                    quickAccessMenu
                    timetableWeatherButton
                }
            }
        }
#else
        ToolbarItem(placement: .leafyLeading) {
            HStack(spacing: 8 * leafyControlScale) {
                quickAccessMenu
                timetableWeatherButton
            }
        }
#endif
    }

    private var quickAccessMenu: some View {
        Button {
            isQuickAccessPresented.toggle()
        } label: {
            toolbarIconLabel(systemName: "slider.horizontal.3")
        }
        .popover(
            isPresented: $isQuickAccessPresented,
            attachmentAnchor: .point(.bottomLeading),
            arrowEdge: .top
        ) {
            quickAccessPopoverContent
                .presentationCompactAdaptation(.popover)
        }
        .accessibilityLabel("首页快捷入口")
    }

    private var quickAccessPopoverContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isCustomCampus {
                quickAccessPopoverButton(
                    "课表处理",
                    systemImage: "slider.horizontal.3",
                    action: .processTimetable
                )
            } else {
                quickAccessPopoverButton(
                    "共享课表",
                    systemImage: "person.2.fill",
                    action: .shareTimetable
                )
            }

            if !isCustomCampus {
                quickAccessPopoverButton(
                    "空闲教室",
                    systemImage: "building.2.crop.circle",
                    action: .emptyClassroom
                )
            }

            quickAccessPopoverButton(
                "添加日程",
                systemImage: "calendar.badge.plus",
                action: .addSchedule
            )

            quickAccessPopoverButton(
                "导出课表",
                systemImage: "square.and.arrow.up",
                action: .exportTimetable
            )
        }
        .fixedSize(horizontal: true, vertical: true)
    }

    private func quickAccessPopoverButton(
        _ title: String,
        systemImage: String,
        action: TimetableQuickAccessAction
    ) -> some View {
        Button {
            scheduleQuickAccessAction(action)
        } label: {
            HStack(spacing: 10 * leafyControlScale) {
                Image(systemName: systemImage)
                    .font(.system(size: 12 * leafyControlScale, weight: .semibold))
                    .foregroundStyle(AppTheme.accentEmphasis(for: themeColorPreference))
                    .frame(width: 22 * leafyControlScale)

                Text(title)
                    .font(.body)
                    .foregroundStyle(AppTheme.primaryText)
            }
            .padding(.horizontal, 18 * leafyControlScale)
            .padding(.vertical, 12 * leafyControlScale)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func scheduleQuickAccessAction(_ action: TimetableQuickAccessAction) {
        pendingQuickAccessAction = action
        isQuickAccessPresented = false

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            guard pendingQuickAccessAction == action else { return }
            pendingQuickAccessAction = nil
            guard !isQuickAccessPresented else { return }
            performQuickAccessAction(action)
        }
    }

    private func performQuickAccessAction(_ action: TimetableQuickAccessAction) {
        switch action {
        case .processTimetable:
            isTimetableProcessingPresented = true
        case .shareTimetable:
            appNavigation.openTimetableSharing()
        case .emptyClassroom:
            appNavigation.openAcademicRoute(.emptyClassroom)
        case .addSchedule:
            presentFreeScheduleSheet()
        case .exportTimetable:
            isExportSheetPresented = true
        }
    }

    @ViewBuilder
    private var timetableWeatherButton: some View {
        if let cachedTimetableWeather {
            Button {
                isWeatherAdvicePresented = true
            } label: {
                weatherTextLabel(cachedTimetableWeather.timetableCapsuleText)
            }
            .accessibilityLabel("天气建议，\(cachedTimetableWeather.timetableCapsuleText)")
        } else {
            Button {
                isWeatherAdvicePresented = true
            } label: {
                toolbarIconLabel(systemName: "cloud.sun")
            }
            .accessibilityLabel("天气建议")
        }
    }

    private func toolbarIconLabel(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 17 * leafyControlScale, weight: .semibold))
            .foregroundStyle(AppTheme.accentEmphasis(for: themeColorPreference))
    }

    private func weatherTextLabel(_ text: String) -> some View {
        Text(text)
            .font(.body)
            .foregroundStyle(AppTheme.accentEmphasis(for: themeColorPreference))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(1)
    }

    private func presentFreeScheduleSheet() {
        let week = currentWeek
        let day = defaultScheduleDay
        let occupiedPeriods = currentTimetableGridSnapshot().occupiedPeriods(day: day, week: week)
        let period = defaultSchedulePeriod(occupiedPeriods: occupiedPeriods)
        selectedCellReminderContext = TimetableCellReminderContext(
            week: week,
            day: day,
            period: period,
            date: dayMetadata(day: day, week: week).date,
            occupiedPeriods: occupiedPeriods,
            totalPeriods: totalClasses,
            reminder: nil,
            allowsDateSelection: true
        )
    }

    private var defaultScheduleDay: Int {
        let weekday = Calendar.current.component(.weekday, from: Date())
        return weekday == 1 ? 7 : weekday - 1
    }

    private func defaultSchedulePeriod(occupiedPeriods: Set<Int>) -> Int {
        let preferred = min(max(TimetablePeriodSchedule.defaultStudyPeriod(), 1), totalClasses)
        if !occupiedPeriods.contains(preferred) {
            return preferred
        }
        return (1...totalClasses).first { !occupiedPeriods.contains($0) } ?? preferred
    }

    private var toolbarReturnButton: some View {
        Button("回到") {
            returnToCurrentWeek()
        }
        .tint(AppTheme.accentEmphasis(for: themeColorPreference))
    }

    private var toolbarWeekMenu: some View {
        Menu {
            ForEach(1...totalWeeks, id: \.self) { week in
                Button(weekMenuTitle(week)) {
                    currentWeek = week
                    scrollToWeek = week
                    syncReturnButtonVisibility(for: week)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(weekTitle(currentWeek))
                Image(systemName: "chevron.down")
            }
            .foregroundStyle(AppTheme.accentEmphasis(for: themeColorPreference))
        }
    }

    private func weekTitle(_ week: Int) -> String {
        L10n.text("第 %d 周", language: leafyLanguage, week)
    }

    private func weekMenuTitle(_ week: Int) -> String {
        weekTitle(week) + (week == SemesterConfig.currentWeek() ? L10n.text(" (本周)", language: leafyLanguage) : "")
    }

    private func returnToCurrentWeek() {
        let week = SemesterConfig.currentWeek()
        currentWeek = week
        isAwayFromCurrentSchedule = false
        scrollToWeek = week
    }

    private var returnButtonTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing)
                .combined(with: .opacity)
                .combined(with: .scale(scale: 0.92)),
            removal: .opacity
                .combined(with: .scale(scale: 0.92))
        )
    }

    @ViewBuilder
    private var toolbarRefreshButton: some View {
        if isFetching {
            ProgressView()
        } else {
            Button {
                if isCustomCampus {
                    isTimetableProcessingPresented = true
                } else {
                    Task { await fetchAndParseTimetable(userInitiated: true) }
                }
            } label: {
                Image(systemName: isCustomCampus ? "slider.horizontal.3" : "arrow.clockwise")
            }
            .accessibilityLabel(isCustomCampus ? "课表处理" : "刷新")
        }
    }

    private var timetableContent: some View {
        VStack(spacing: AppSpacing.card) {
            GeometryReader { geometry in
                let gridSnapshot = currentTimetableGridSnapshot()
                let metrics = layoutMetrics(for: geometry.size, dayCount: gridSnapshot.visibleDays.count)

                Group {
                    switch metrics.mode {
                    case .weekGrid:
                        TimetableScrollContainer(
                            axisWidth: axisWidth,
                            headerHeight: headerHeight,
                            totalWeeks: totalWeeks,
                            weekStride: metrics.weekStride,
                            dayColumnWidth: metrics.dayColumnWidth,
                            rowHeight: metrics.rowHeight,
                            rowSpacing: metrics.rowSpacing,
                            allowsVerticalScroll: metrics.allowsVerticalScroll,
                            currentWeek: $currentWeek,
                            scrollToWeek: $scrollToWeek,
                            isAwayFromCurrentWeek: $isAwayFromCurrentSchedule,
                            containerID: "continuous-timetable",
                            onFirstInteractiveLayout: {
                                isTimetableInteractivelyLaidOut = true
                            },
                            corner: {
                                cornerHeader
                                    .frame(width: axisWidth, height: headerHeight)
                            },
                            header: {
                                ZStack(alignment: .topLeading) {
                                    ForEach(renderedTimetableWeeks, id: \.self) { week in
                                        HStack(alignment: .top, spacing: metrics.daySpacing) {
                                            ForEach(gridSnapshot.visibleDays, id: \.self) { day in
                                                dayHeader(metadata: dayMetadata(day: day, week: week))
                                                    .frame(width: metrics.dayColumnWidth, height: headerHeight)
                                            }
                                        }
                                        .offset(x: CGFloat(week - 1) * metrics.weekStride)
                                        .accessibilityHidden(week != currentWeek)
                                    }
                                }
                                .frame(width: timetableContentWidth(metrics: metrics), height: headerHeight, alignment: .topLeading)
                            },
                            axis: {
                                timeAxis(metrics: metrics)
                            },
                            body: {
                                ZStack(alignment: .topLeading) {
                                    ForEach(renderedTimetableWeeks, id: \.self) { week in
                                        HStack(alignment: .top, spacing: metrics.daySpacing) {
                                            ForEach(gridSnapshot.visibleDays, id: \.self) { day in
                                                dayColumnBody(
                                                    day: day,
                                                    week: week,
                                                    width: metrics.dayColumnWidth,
                                                    metrics: metrics,
                                                    gridSnapshot: gridSnapshot,
                                                    metadata: dayMetadata(day: day, week: week)
                                                )
                                            }
                                        }
                                        .offset(x: CGFloat(week - 1) * metrics.weekStride)
                                        .accessibilityHidden(week != currentWeek)
                                    }
                                }
                                .frame(
                                    width: timetableContentWidth(metrics: metrics),
                                    height: metrics.gridHeight,
                                    alignment: .topLeading
                                )
                            }
                        )
                        .frame(width: metrics.containerWidth, height: metrics.containerHeight, alignment: .topLeading)
                        .padding(.horizontal, metrics.horizontalPadding)
                        .transaction { transaction in
                            transaction.animation = nil
                        }

                    case .agendaList:
                        timetableAgendaList(gridSnapshot: gridSnapshot)
                            .onAppear {
                                isTimetableInteractivelyLaidOut = true
                                scrollToWeek = nil
                                syncReturnButtonVisibility(for: currentWeek)
                            }
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            }
        }
    }

    private func layoutMetrics(for size: CGSize, dayCount: Int) -> TimetableLayoutMetrics {
        timetableLayoutMetricsCache.metrics(
            size: size,
            dayCount: dayCount,
            totalClasses: totalClasses,
            axisWidth: axisWidth,
            headerHeight: headerHeight,
            horizontalPadding: timetableHorizontalPadding,
            daySpacing: timetableDaySpacing,
            weekSpacing: timetableWeekSpacing,
            rowSpacing: overviewRowSpacing,
            minimumRowHeight: overviewMinimumRowHeight,
            cardInset: overviewCardInset,
            laneSpacing: 2 * leafyControlScale,
            bottomClearance: overviewBottomClearance,
            controlScale: leafyControlScale,
            interPaneSpacing: AppSpacing.micro,
            allowsAgendaList: allowsTimetableAgendaFallback
        )
    }

    private var cornerHeader: some View {
        Text(monthString())
            .font(.system(size: 11.5 * leafyControlScale, weight: .semibold))
            .foregroundStyle(AppTheme.secondaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                    .fill(AppTheme.cardBackground.opacity(0.62))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                    .stroke(AppTheme.separator, lineWidth: 1)
            )
        .frame(width: axisWidth, height: headerHeight)
    }

    private func timeAxis(metrics: TimetableLayoutMetrics) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(1...totalClasses, id: \.self) { classIndex in
                let slot = TimetablePeriodSchedule.slot(for: classIndex)
                VStack(spacing: 0) {
                    if let startText = slot?.startText {
                        Text(startText)
                            .font(.system(size: 6.4 * leafyControlScale, weight: .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.68)
                    }
                    Text("\(classIndex)")
                        .font(.system(size: 15 * leafyControlScale, weight: .semibold))
                    if let endText = slot?.endText {
                        Text(endText)
                            .font(.system(size: 6.4 * leafyControlScale, weight: .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.68)
                    }
                }
                .foregroundStyle(AppTheme.secondaryText)
                .frame(width: axisWidth, height: metrics.rowHeight)
                .background(
                    RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                        .fill(AppTheme.cardBackground.opacity(0.52))
                )
                .position(
                    x: axisWidth * 0.5,
                    y: yPosition(forClass: classIndex, metrics: metrics) + metrics.rowHeight * 0.5
                )
            }
        }
        .frame(width: axisWidth, height: metrics.gridHeight, alignment: .topLeading)
    }

    private func dayColumnBody(
        day: Int,
        week: Int,
        width: CGFloat,
        metrics: TimetableLayoutMetrics,
        gridSnapshot: TimetableGridSnapshot,
        metadata: TimetableDayMetadata
    ) -> some View {
        let layouts = gridSnapshot.layouts(day: day, week: week)
        let occupiedPeriods = gridSnapshot.occupiedPeriods(day: day, week: week)
        let reminders = gridSnapshot.cellReminders(week: week, day: day)
        let reminderPeriods = Set(reminders.flatMap { Array($0.displayPeriodRange) })
        let countdowns = metadata.countdowns
        let exams = metadata.exams

        return ZStack(alignment: .topLeading) {
            timetableGridBackground(width: width, metrics: metrics)

            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture().onEnded { value in
                        guard let period = (1...totalClasses).first(where: { candidate in
                            let minY = yPosition(forClass: candidate, metrics: metrics)
                            return value.location.y >= minY && value.location.y <= minY + metrics.rowHeight
                        }),
                        !occupiedPeriods.contains(period),
                        !reminderPeriods.contains(period) else { return }

                        selectedCellReminderContext = TimetableCellReminderContext(
                            week: week,
                            day: day,
                            period: period,
                            date: metadata.date,
                            occupiedPeriods: occupiedPeriods,
                            totalPeriods: totalClasses,
                            reminder: nil
                        )
                    }
                )
                .accessibilityHidden(true)

            if let accessiblePeriod = (1...totalClasses).first(where: {
                !occupiedPeriods.contains($0) && !reminderPeriods.contains($0)
            }) {
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityElement()
                    .accessibilityLabel("\(metadata.dayTitle)添加日程")
                    .accessibilityHint("添加第 \(accessiblePeriod) 节日程")
                    .accessibilityAction {
                        selectedCellReminderContext = TimetableCellReminderContext(
                            week: week,
                            day: day,
                            period: accessiblePeriod,
                            date: metadata.date,
                            occupiedPeriods: occupiedPeriods,
                            totalPeriods: totalClasses,
                            reminder: nil
                        )
                    }
            }

            ForEach(reminders) { reminder in
                let blockHeight = cellReminderHeight(for: reminder, metrics: metrics)
                let blockWidth = max(width - metrics.cardInset * 2, 1)
                let spanHeight = cellReminderSpanHeight(for: reminder, metrics: metrics)
                TimetableCellReminderBlockView(
                    reminder: reminder,
                    height: blockHeight,
                    width: blockWidth
                )
                .position(
                    x: width * 0.5,
                    y: yPosition(forClass: reminder.displayStartPeriod, metrics: metrics) + spanHeight * 0.5
                )
                .zIndex(2)
                .onTapGesture {
                    selectedCellReminderContext = TimetableCellReminderContext(
                        week: week,
                        day: day,
                        period: reminder.displayStartPeriod,
                        date: metadata.date,
                        occupiedPeriods: occupiedPeriods,
                        totalPeriods: totalClasses,
                        reminder: reminder
                    )
                }
            }

            ForEach(layouts) { layout in
                let blockHeight = heightForCourse(layout.course, metrics: metrics)
                let blockWidth = widthForLayout(layout, availableWidth: width, metrics: metrics)
                let noteText = gridSnapshot.note(for: layout.course, week: week)

                CourseBlockView(
                    course: layout.course,
                    hasNote: noteText != nil,
                    noteText: noteText,
                    height: blockHeight,
                    width: blockWidth,
                    isCompact: true,
                    isTodayCourse: metadata.isToday,
                    backgroundPalette: timetableBackgroundCoursePalette,
                    courseCardOpacity: timetableBackgroundCourseCardOpacity,
                    showsContextMenu: false
                )
                .position(
                    x: xOffsetForLayout(layout, availableWidth: width, metrics: metrics) + blockWidth * 0.5,
                    y: yOffset(for: layout.course, metrics: metrics) + blockHeight * 0.5
                )
                .onTapGesture {
                    selectedCourseContext = SelectedCourseContext(
                        course: layout.course,
                        week: week,
                        day: day,
                        date: metadata.date
                    )
                }
                .onLongPressGesture {
                    courseNotePreview = CourseNotePreview(
                        courseName: layout.course.displayCourseName,
                        note: noteText
                    )
                }
            }

            ForEach(Array(countdowns.enumerated()), id: \.element.id) { index, countdown in
                let blockHeight = countdownBlockHeight(metrics: metrics)
                let blockWidth = max(width - metrics.cardInset * 2, 1)
                Button {
                    presentCustomScheduleEditor(for: countdown)
                } label: {
                    TimetableCountdownBlockView(
                        projection: countdown,
                        height: blockHeight,
                        width: blockWidth
                    )
                    .contentShape(
                        RoundedRectangle(cornerRadius: AppRadius.small * 0.68, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .position(
                    x: width * 0.5,
                    y: countdownYPosition(for: countdown.period, index: index, height: blockHeight, metrics: metrics)
                )
                .zIndex(3)
            }

            ForEach(Array(exams.enumerated()), id: \.element.id) { index, projection in
                let blockHeight = examBlockHeight(metrics: metrics)
                let blockWidth = max(width - metrics.cardInset * 2, 1)
                TimetableExamBlockView(
                    projection: projection,
                    height: blockHeight,
                    width: blockWidth
                )
                .position(
                    x: width * 0.5,
                    y: examYPosition(for: projection.period, index: index, height: blockHeight, metrics: metrics)
                )
                .zIndex(4)
                .onTapGesture {
                    selectedDaySummary = TimetableDaySelection(
                        week: week,
                        day: day,
                        date: metadata.date
                    )
                }
            }
        }
        .frame(width: width, height: metrics.gridHeight, alignment: .topLeading)
    }

    private func timetableAgendaList(gridSnapshot: TimetableGridSnapshot) -> some View {
        VStack(spacing: AppSpacing.compact) {
            timetableAgendaHeader

            ScrollView(showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: AppSpacing.compact) {
                    ForEach(gridSnapshot.visibleDays, id: \.self) { day in
                        timetableAgendaDaySection(day: day, gridSnapshot: gridSnapshot)
                    }
                }
                .padding(.horizontal, AppSpacing.page)
                .padding(.bottom, AppSpacing.page)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var timetableAgendaHeader: some View {
        HStack(spacing: AppSpacing.compact) {
            Button {
                moveAgendaWeek(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16 * leafyControlScale, weight: .semibold))
                    .frame(width: 40 * leafyControlScale, height: 40 * leafyControlScale)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("上一周")
            .disabled(currentWeek <= 1)

            VStack(spacing: 2 * leafyControlScale) {
                Text(weekTitle(currentWeek))
                    .font(.system(size: 17 * leafyControlScale, weight: .bold))
                    .foregroundStyle(AppTheme.primaryText)
                Text(agendaWeekRangeText)
                    .font(.system(size: 11 * leafyControlScale, weight: .medium))
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .frame(maxWidth: .infinity)

            Button {
                moveAgendaWeek(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 16 * leafyControlScale, weight: .semibold))
                    .frame(width: 40 * leafyControlScale, height: 40 * leafyControlScale)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("下一周")
            .disabled(currentWeek >= totalWeeks)
        }
        .padding(.horizontal, AppSpacing.page)
        .padding(.vertical, 8 * leafyControlScale)
        .background(AppTheme.cardBackground.opacity(0.82), in: RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
                .stroke(AppTheme.separator, lineWidth: 1)
        )
        .padding(.horizontal, AppSpacing.page)
    }

    private func timetableAgendaDaySection(day: Int, gridSnapshot: TimetableGridSnapshot) -> some View {
        let metadata = dayMetadata(day: day, week: currentWeek)
        let items = timetableAgendaItems(metadata: metadata, gridSnapshot: gridSnapshot)

        return VStack(alignment: .leading, spacing: 10 * leafyControlScale) {
            HStack(spacing: 8 * leafyControlScale) {
                VStack(alignment: .leading, spacing: 2 * leafyControlScale) {
                    Text(metadata.dayTitle)
                        .font(.system(size: 15 * leafyControlScale, weight: .bold))
                        .foregroundStyle(metadata.isToday ? AppTheme.accentEmphasis : AppTheme.primaryText)
                    Text(metadata.chineseDateText)
                        .font(.system(size: 11 * leafyControlScale, weight: .medium))
                        .foregroundStyle(AppTheme.secondaryText)
                }

                Spacer()

                if let event = metadata.event {
                    Text(event.title)
                        .font(.system(size: 11 * leafyControlScale, weight: .semibold))
                        .foregroundStyle(dayHeaderForeground(event: event, hasExam: false))
                        .lineLimit(1)
                }
            }

            if items.isEmpty {
                Text("当天没有课程安排")
                    .font(.system(size: 13 * leafyControlScale, weight: .medium))
                    .foregroundStyle(AppTheme.tertiaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4 * leafyControlScale)
            } else {
                VStack(spacing: 8 * leafyControlScale) {
                    ForEach(items) { item in
                        timetableAgendaRow(item)
                    }
                }
            }
        }
        .padding(14 * leafyControlScale)
        .background(AppTheme.cardBackground.opacity(0.92), in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                .stroke(AppTheme.separator, lineWidth: 1)
        )
    }

    private func timetableAgendaRow(_ item: TimetableAgendaItem) -> some View {
        Button {
            handleAgendaItemTap(item)
        } label: {
            HStack(alignment: .top, spacing: 10 * leafyControlScale) {
                VStack(spacing: 2 * leafyControlScale) {
                    Text(item.periodText)
                        .font(.system(size: 13 * leafyControlScale, weight: .bold))
                        .foregroundStyle(item.tint)
                        .lineLimit(1)
                    Text(item.timeText)
                        .font(.system(size: 9.5 * leafyControlScale, weight: .medium))
                        .foregroundStyle(AppTheme.tertiaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                .frame(width: 50 * leafyControlScale)

                VStack(alignment: .leading, spacing: 4 * leafyControlScale) {
                    Text(item.title)
                        .font(.system(size: 14.5 * leafyControlScale, weight: .semibold))
                        .foregroundStyle(AppTheme.primaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    if !item.detail.isEmpty {
                        Text(item.detail)
                            .font(.system(size: 12 * leafyControlScale, weight: .medium))
                            .foregroundStyle(AppTheme.secondaryText)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: item.systemImage)
                    .font(.system(size: 14 * leafyControlScale, weight: .semibold))
                    .foregroundStyle(item.tint)
                    .frame(width: 24 * leafyControlScale, height: 24 * leafyControlScale)
            }
            .padding(10 * leafyControlScale)
            .background(item.tint.opacity(colorScheme == .dark ? 0.18 : 0.11), in: RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                    .stroke(agendaTodayCourseStrokeColor(item), lineWidth: agendaTodayCourseStrokeWidth(item))
            )
            .shadow(
                color: agendaTodayCourseGlowColor(item),
                radius: agendaTodayCourseGlowRadius(item),
                y: 0
            )
            .contentShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func isTodayCourseAgendaItem(_ item: TimetableAgendaItem) -> Bool {
        guard case .course = item.kind else { return false }
        return Calendar.current.isDateInToday(item.date)
    }

    private func agendaTodayCourseStrokeColor(_ item: TimetableAgendaItem) -> Color {
        guard isTodayCourseAgendaItem(item) else { return .clear }
        return AppTheme.accentEmphasis(for: themeColorPreference).opacity(colorScheme == .dark ? 0.92 : 0.78)
    }

    private func agendaTodayCourseStrokeWidth(_ item: TimetableAgendaItem) -> CGFloat {
        guard isTodayCourseAgendaItem(item) else { return 0 }
        return max(1.5, 1.7 * leafyControlScale)
    }

    private func agendaTodayCourseGlowColor(_ item: TimetableAgendaItem) -> Color {
        guard isTodayCourseAgendaItem(item) else { return .clear }
        return AppTheme.accent(for: themeColorPreference).opacity(colorScheme == .dark ? 0.24 : 0.16)
    }

    private func agendaTodayCourseGlowRadius(_ item: TimetableAgendaItem) -> CGFloat {
        isTodayCourseAgendaItem(item) ? 4 * leafyControlScale : 0
    }

    private func timetableAgendaItems(
        metadata: TimetableDayMetadata,
        gridSnapshot: TimetableGridSnapshot
    ) -> [TimetableAgendaItem] {
        timetableAgendaItemCache.items(
            metadata: metadata,
            gridSnapshot: gridSnapshot,
            totalClasses: totalClasses
        )
    }

    private func handleAgendaItemTap(_ item: TimetableAgendaItem) {
        switch item.kind {
        case .course(let course):
            selectedCourseContext = SelectedCourseContext(
                course: course,
                week: item.week,
                day: item.day,
                date: item.date
            )
        case .cellReminder(let reminder, let period):
            selectedCellReminderContext = TimetableCellReminderContext(
                week: item.week,
                day: item.day,
                period: period,
                date: item.date,
                occupiedPeriods: currentTimetableGridSnapshot().occupiedPeriods(day: item.day, week: item.week),
                totalPeriods: totalClasses,
                reminder: reminder
            )
        case .countdown(let projection):
            presentCustomScheduleEditor(for: projection)
        case .exam:
            selectedDaySummary = TimetableDaySelection(
                week: item.week,
                day: item.day,
                date: item.date
            )
        }
    }

    private func presentCustomScheduleEditor(for projection: TimetableCountdownProjection) {
        guard let event = customCountdownEvents.first(where: { $0.id == projection.eventID }) else {
            alertMessage = "该日程已更新，请刷新课表后重试。"
            showAlert = true
            return
        }

        let context = TimetableCellReminderContext(
            week: projection.week,
            day: projection.dayOfWeek,
            period: projection.period,
            date: event.startsAt,
            occupiedPeriods: currentTimetableGridSnapshot().occupiedPeriods(
                day: projection.dayOfWeek,
                week: projection.week
            ),
            totalPeriods: totalClasses,
            reminder: nil,
            allowsDateSelection: true
        )
        selectedCustomScheduleEditor = .importantDate(
            event,
            defaultContext: context,
            allowsModeSelection: false
        )
    }

    private var agendaWeekRangeText: String {
        let start = dateFor(dayOfWeek: 1, in: currentWeek)
        let end = dateFor(dayOfWeek: 7, in: currentWeek)
        return "\(DateFormatters.chineseDay.string(from: start)) - \(DateFormatters.chineseDay.string(from: end))"
    }

    private func moveAgendaWeek(by delta: Int) {
        let nextWeek = min(max(currentWeek + delta, 1), totalWeeks)
        guard nextWeek != currentWeek else { return }
        currentWeek = nextWeek
        scrollToWeek = nextWeek
        syncReturnButtonVisibility(for: nextWeek)
    }

    private func cellReminderHeight(metrics: TimetableLayoutMetrics) -> CGFloat {
        max(metrics.rowHeight - metrics.cardInset * 2, metrics.rowHeight * 0.72)
    }

    private func cellReminderHeight(for reminder: TimetableCellReminder, metrics: TimetableLayoutMetrics) -> CGFloat {
        max(
            cellReminderSpanHeight(for: reminder, metrics: metrics) - metrics.cardInset * 2,
            metrics.rowHeight * 0.72
        )
    }

    private func cellReminderSpanHeight(for reminder: TimetableCellReminder, metrics: TimetableLayoutMetrics) -> CGFloat {
        let periodCount = max(reminder.displayEndPeriod - reminder.displayStartPeriod + 1, 1)
        return CGFloat(periodCount) * metrics.rowHeight + CGFloat(max(periodCount - 1, 0)) * metrics.rowSpacing
    }

    private func countdownBlockHeight(metrics: TimetableLayoutMetrics) -> CGFloat {
        min(max(metrics.rowHeight * 0.46, 18 * leafyControlScale), metrics.rowHeight - metrics.cardInset * 2)
    }

    private func examBlockHeight(metrics: TimetableLayoutMetrics) -> CGFloat {
        min(max(metrics.rowHeight * 0.52, 20 * leafyControlScale), metrics.rowHeight - metrics.cardInset * 2)
    }

    private func countdownYPosition(for period: Int, index: Int, height: CGFloat, metrics: TimetableLayoutMetrics) -> CGFloat {
        let base = yPosition(forClass: period, metrics: metrics) + metrics.rowHeight - metrics.cardInset - height * 0.5
        let stackedOffset = CGFloat(index % 2) * min(height * 0.36, 8 * leafyControlScale)
        return base - stackedOffset
    }

    private func examYPosition(for period: Int, index: Int, height: CGFloat, metrics: TimetableLayoutMetrics) -> CGFloat {
        let base = yPosition(forClass: period, metrics: metrics) + metrics.cardInset + height * 0.5
        let stackedOffset = CGFloat(index % 2) * min(height * 0.38, 8 * leafyControlScale)
        return base + stackedOffset
    }

    private func dayHeader(metadata: TimetableDayMetadata) -> some View {
        return VStack(spacing: 1) {
            Text(metadata.dayTitle)
                .font(.system(size: 14 * leafyControlScale, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .allowsTightening(true)
            Text(metadata.numericDateText)
                .font(.system(size: 11.5 * leafyControlScale, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .allowsTightening(true)
            if let event = metadata.event {
                Text(event.title)
                    .font(.system(size: 8.5 * leafyControlScale, weight: .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .allowsTightening(true)
            }
            if metadata.hasExam {
                Label("考试", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 8.5 * leafyControlScale, weight: .semibold))
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .foregroundStyle(dayHeaderTextForeground(for: metadata))
        .frame(maxWidth: .infinity, minHeight: headerHeight)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                .fill(dayHeaderFill(today: metadata.isToday, event: metadata.event, hasExam: metadata.hasExam))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                .stroke(metadata.isToday || metadata.event != nil || metadata.hasExam ? Color.clear : AppTheme.separator, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
    }

    private func dayHeaderFill(today: Bool, event: SchoolCalendarEvent?, hasExam: Bool) -> Color {
        if today { return AppTheme.accent }
        if hasExam { return AppTheme.warning.opacity(colorScheme == .dark ? 0.26 : 0.20) }
        guard let event else { return AppTheme.cardBackground }

        switch event.academicCategory {
        case .winterBreak:
            return Color.cyan.opacity(colorScheme == .dark ? 0.24 : 0.18)
        case .summerBreak:
            return Color.yellow.opacity(colorScheme == .dark ? 0.24 : 0.20)
        case .importantDate, .semesterEnd:
            return AppTheme.fill.opacity(0.82)
        case .publicHoliday, nil:
            break
        }

        switch event.kind {
        case .holiday:
            return colorScheme == .dark ? AppTheme.accent.opacity(0.26) : AppTheme.accentSoft.opacity(0.72)
        case .closure:
            return AppTheme.warning.opacity(0.24)
        case .solarTerm:
            return solarTermFill(for: event)
        }
    }

    private func dayHeaderForeground(event: SchoolCalendarEvent?, hasExam: Bool) -> Color {
        if hasExam { return AppTheme.warning }
        guard let event else { return AppTheme.primaryText }
        switch event.academicCategory {
        case .winterBreak:
            return Color.cyan.opacity(colorScheme == .dark ? 0.92 : 0.78)
        case .summerBreak:
            return Color.yellow.opacity(colorScheme == .dark ? 0.92 : 0.78)
        case .importantDate, .semesterEnd:
            return AppTheme.secondaryText
        case .publicHoliday, nil:
            break
        }
        switch event.kind {
        case .holiday:
            return AppTheme.accentEmphasis
        case .closure:
            return AppTheme.warning
        case .solarTerm:
            return solarTermForeground(for: event)
        }
    }

    private func dayHeaderTextForeground(for metadata: TimetableDayMetadata) -> Color {
        if metadata.isToday { return AppTheme.textOnAccent }
        if metadata.event != nil { return .black }
        if metadata.hasExam { return AppTheme.warning }
        return AppTheme.primaryText
    }

    private func solarTermFill(for event: SchoolCalendarEvent) -> Color {
        switch event.solarTermSeason {
        case .spring:
            return Color.green.opacity(colorScheme == .dark ? 0.22 : 0.18)
        case .summer:
            return Color.yellow.opacity(colorScheme == .dark ? 0.24 : 0.24)
        case .autumn:
            return Color.orange.opacity(colorScheme == .dark ? 0.24 : 0.20)
        case .winter:
            return Color.cyan.opacity(colorScheme == .dark ? 0.24 : 0.18)
        case nil:
            return AppTheme.fill.opacity(0.82)
        }
    }

    private func solarTermForeground(for event: SchoolCalendarEvent) -> Color {
        switch event.solarTermSeason {
        case .spring:
            return Color.green.opacity(colorScheme == .dark ? 0.92 : 0.78)
        case .summer:
            return Color.yellow.opacity(colorScheme == .dark ? 0.92 : 0.78)
        case .autumn:
            return Color.orange.opacity(colorScheme == .dark ? 0.92 : 0.82)
        case .winter:
            return Color.cyan.opacity(colorScheme == .dark ? 0.92 : 0.78)
        case nil:
            return AppTheme.secondaryText
        }
    }

    private func timetableGridBackground(width: CGFloat, metrics: TimetableLayoutMetrics) -> some View {
        Canvas { context, _ in
            for classIndex in 1...totalClasses {
                let isBreakBoundary = classIndex == 5 || classIndex == 9
                let rect = CGRect(
                    x: 0,
                    y: yPosition(forClass: classIndex, metrics: metrics),
                    width: width,
                    height: metrics.rowHeight
                )
                context.opacity = isBreakBoundary ? 1 : 0.72
                context.fill(
                    Path(roundedRect: rect, cornerRadius: AppRadius.small),
                    with: .color(backgroundFillColor(for: classIndex))
                )
            }
        }
        .frame(width: width, height: metrics.gridHeight, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    private var renderedTimetableWeeks: ClosedRange<Int> {
        1...totalWeeks
    }

    private func timetableContentWidth(metrics: TimetableLayoutMetrics) -> CGFloat {
        max(CGFloat(totalWeeks) * metrics.weekStride - metrics.weekSpacing, 1)
    }

    private func backgroundFillColor(for classIndex: Int) -> Color {
        if classIndex == 5 || classIndex == 9 {
            if usesCustomTimetableBackground {
                return colorScheme == .dark ? AppTheme.accent.opacity(0.22) : AppTheme.accentSoft.opacity(0.46)
            }
            return colorScheme == .dark ? AppTheme.accent.opacity(0.18) : AppTheme.accentSoft.opacity(0.38)
        }
        return AppTheme.cardBackground.opacity(usesCustomTimetableBackground ? 0.48 : 0.36)
    }

    private var loadingState: some View {
        VStack(spacing: 14) {
            ProgressView()
                .scaleEffect(1.1)
            Text("正在同步课表")
                .leafyBody()
                .foregroundStyle(AppTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var unauthenticatedState: some View {
        ContentUnavailableView(
            "需要重新登录",
            systemImage: "person.crop.circle.badge.exclamationmark",
            description: Text("当前教务登录态不可用，请先连接校园网，再回到登录页重新登录。")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func emptyState(title: String, description: String) -> some View {
        ContentUnavailableView(
            L10n.text(title, language: leafyLanguage),
            systemImage: "calendar",
            description: Text(L10n.text(description, language: leafyLanguage))
        )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
    }

    private func layoutsForDay(_ day: Int, week: Int) -> [DayCourseLayout] {
        currentTimetableGridSnapshot().layouts(day: day, week: week)
    }

    private func widthForLayout(_ layout: DayCourseLayout, availableWidth: CGFloat, metrics: TimetableLayoutMetrics) -> CGFloat {
        let totalSpacing = CGFloat(max(layout.laneCount - 1, 0)) * metrics.laneSpacing
        let laneWidth = (availableWidth - totalSpacing - metrics.cardInset * 2) / CGFloat(layout.laneCount)
        return max(laneWidth, 1)
    }

    private func xOffsetForLayout(_ layout: DayCourseLayout, availableWidth: CGFloat, metrics: TimetableLayoutMetrics) -> CGFloat {
        let laneWidth = widthForLayout(layout, availableWidth: availableWidth, metrics: metrics)
        return metrics.cardInset + CGFloat(layout.laneIndex) * (laneWidth + metrics.laneSpacing)
    }

    private func heightForCourse(_ course: Course, metrics: TimetableLayoutMetrics) -> CGFloat {
        let count = max(course.duration.count, 1)
        let rawHeight = CGFloat(count) * metrics.rowHeight + CGFloat(count - 1) * metrics.rowSpacing - metrics.cardInset * 2
        return max(rawHeight, metrics.rowHeight * 0.7)
    }

    private func yOffset(for course: Course, metrics: TimetableLayoutMetrics) -> CGFloat {
        guard let start = course.duration.min() else { return 0 }
        return yPosition(forClass: start, metrics: metrics) + metrics.cardInset
    }

    private func yPosition(forClass classIndex: Int, metrics: TimetableLayoutMetrics) -> CGFloat {
        CGFloat(max(classIndex - 1, 0)) * (metrics.rowHeight + metrics.rowSpacing)
    }

    private func syncReturnButtonVisibility(for visibleWeek: Int? = nil) {
        let week = visibleWeek ?? currentWeek
        isAwayFromCurrentSchedule = week != SemesterConfig.currentWeek()
    }

    private func dateFor(dayOfWeek: Int, in week: Int) -> Date {
        let calendar = Calendar.current
        let startOfSemester = SemesterConfig.startOfSemesterDate
        var comp = DateComponents()
        comp.day = (week - 1) * 7 + (dayOfWeek - 1)
        return calendar.date(byAdding: comp, to: startOfSemester) ?? Date()
    }

    private func monthString() -> String {
        let date = dateFor(dayOfWeek: 1, in: currentWeek)
        let month = Calendar.current.component(.month, from: date)
        return "\(month)月"
    }

    private func dayTitle(_ day: Int) -> String {
        leafyLanguage.weekdayTitle(for: day)
    }

    private func dayMetadata(day: Int, week: Int) -> TimetableDayMetadata {
        timetableDayMetadataCache.metadata(
            day: day,
            week: week,
            semesterStartDate: SemesterConfig.startOfSemesterDate,
            calendarEvents: calendarEventSignature,
            scheduleSnapshot: timetableScheduleProjectionSnapshot,
            language: leafyLanguage
        )
    }

    private func currentTimetableGridSnapshot() -> TimetableGridSnapshot {
        if let timetableGridSnapshot {
            return timetableGridSnapshot
        }

        return timetableGridSnapshotCache.snapshot(
            input: timetableRenderInput,
            totalWeeks: totalWeeks
        )
    }

    private func syncTimetableGridSnapshot() {
        let snapshot = timetableGridSnapshotCache.snapshot(
            input: timetableRenderInput,
            totalWeeks: totalWeeks
        )
        guard timetableGridSnapshot?.signature != snapshot.signature ||
              timetableGridSnapshot?.totalWeeks != snapshot.totalWeeks
        else { return }
        timetableGridSnapshot = snapshot
    }

    private func syncTimetableScheduleProjectionSnapshot() {
        timetableScheduleProjectionSnapshot = TimetableScheduleProjectionSnapshot.make(
            countdownEvents: customCountdownEvents,
            exams: cachedExamArrangements
        )
    }

    private func persistParserDebugHTML(_ html: String) -> String {
        let title: String = {
            guard let document = try? SwiftSoup.parse(html) else { return L10n.text("无标题", language: leafyLanguage) }
            return ((try? document.title()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }()

        let titlePart = title.isEmpty ? L10n.text("无标题", language: leafyLanguage) : title

        #if DEBUG
        let bodyPrefix: String = {
            guard let document = try? SwiftSoup.parse(html) else { return "" }
            let raw = ((try? document.body()?.text()) ?? "")
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\t", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return String(raw.prefix(100))
        }()

        let filename = "last_timetable_parser_input.html"
        if let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let directory = caches.appendingPathComponent("leafy-debug", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let fileURL = directory.appendingPathComponent(filename)
            try? html.write(to: fileURL, atomically: true, encoding: .utf8)
        }

        let bodyPart = bodyPrefix.isEmpty ? "" : L10n.text("，正文前缀：%@", language: leafyLanguage, bodyPrefix)
        return L10n.text("调试文件：%@，标题：%@%@", language: leafyLanguage, filename, titlePart, bodyPart)
        #else
        return L10n.text("页面标题：%@。请确认校园网连接，或重新登录后重试。", language: leafyLanguage, titlePart)
        #endif
    }

    private func fetchAndParseTimetable(userInitiated: Bool) async {
        guard !isFetching else { return }
        if isCustomCampus {
            await MainActor.run {
                if userInitiated {
                    isTimetableProcessingPresented = true
                }
            }
            return
        }
        if ReviewDemoMode.isEnabled {
            await MainActor.run {
                ReviewDemoDataSeeder.seed(using: modelContext)
                lastSyncAt = TimetableCacheMetadata.lastSyncAt
                lastFailureMessage = nil
                syncReturnButtonVisibility()
                publishWidgetSnapshot()
            }
            return
        }

        guard networkManager.isLoggedIn else {
            if userInitiated, networkManager.hasCachedIdentity {
                reauthenticationRequest = SchoolReauthenticationRequest(
                    context: .timetable(portal: networkManager.currentPortal)
                )
            } else {
                alertMessage = networkManager.hasCachedIdentity
                    ? L10n.text("本地身份已识别，但刷新课表需要连接校园网并重新建立教务登录态。", language: leafyLanguage)
                    : L10n.text("请先连接校园网登录教务系统。", language: leafyLanguage)
                showAlert = true
            }
            return
        }
        await MainActor.run { isFetching = true }
        let semesterConfig = await SemesterConfig.refreshRemoteIfAvailable(force: userInitiated)
        await MainActor.run {
            applySemesterRuntimeConfig(semesterConfig)
        }

        do {
            let refreshUseCase = TimetableRefreshUseCase(repository: dependencies.schoolTimetableRepository)
            let htmlData = try await refreshUseCase.fetchHTML()
            let parsedCourseRecords: [ParsedCourseRecord]

            do {
                parsedCourseRecords = try await TimetableRefreshUseCase.parseRecords(html: htmlData)
            } catch {
                let debugSummary = persistParserDebugHTML(htmlData)
                throw NSError(
                    domain: "leafy.timetable",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "\(error.localizedDescription)。\(debugSummary)"]
                )
            }

            await MainActor.run {
                let newCourses = parsedCourseRecords.map { $0.makeCourse() }
                let sharedCourses = newCourses.map(SharedTimetableCourse.init(course:))

                let adjustedWeek = TimetableRefreshUseCase.nearestAvailableWeek(
                    from: parsedCourseRecords,
                    preferredWeek: currentWeek
                )
                if let adjustedWeek {
                    currentWeek = adjustedWeek
                }

                for course in courses {
                    modelContext.delete(course)
                }

                for course in newCourses {
                    modelContext.insert(course)
                }

                try? modelContext.save()
                syncTimetableGridSnapshot()
                TimetableCacheMetadata.lastSyncAt = Date()
                TimetableCacheMetadata.lastFailureMessage = nil
                TimetableCacheMetadata.lastSyncedSemesterID = semesterConfig.semesterID
                AppStoreReviewCoordinator.recordSuccessfulSync(kind: .timetable, date: Date())
                SchoolDataRefreshNotifier.post(.timetable)
                Task {
                    await TimetableSharingService.shared.publishExistingSnapshotIfNeeded(courses: sharedCourses)
                }
                lastSyncAt = TimetableCacheMetadata.lastSyncAt
                lastFailureMessage = nil
                isFetching = false
                publishWidgetSnapshot()
                if let adjustedWeek {
                    Task { @MainActor in
                        scrollToWeek = adjustedWeek
                        syncReturnButtonVisibility(for: adjustedWeek)
                    }
                } else {
                    syncReturnButtonVisibility()
                }
            }
        } catch {
            await MainActor.run {
                isFetching = false
                TimetableCacheMetadata.lastFailureMessage = error.localizedDescription
                lastFailureMessage = error.localizedDescription
                publishWidgetSnapshot()
                if userInitiated, SchoolReauthentication.requiresReauthentication(error) {
                    reauthenticationRequest = SchoolReauthenticationRequest(
                        context: .timetable(portal: networkManager.currentPortal)
                    )
                } else {
                    alertMessage = courses.isEmpty
                        ? L10n.text("抓取课表失败：%@", language: leafyLanguage, error.localizedDescription)
                        : L10n.text("抓取课表失败，已继续显示本地缓存：%@", language: leafyLanguage, error.localizedDescription)
                    showAlert = true
                }
            }
        }
    }

    private func publishWidgetSnapshot() {
        LeafyWidgetSnapshotBuilder.publish(
            courses: courses,
            notes: courseNotes,
            occurrenceNotes: occurrenceNotes,
            reminders: courseReminderSettings,
            cellReminders: cellReminders,
            isAuthenticated: networkManager.hasCachedIdentity || ReviewDemoMode.isEnabled
        )
    }

    private func openCourseFromDeepLink(id: UUID) {
        guard let course = courses.first(where: { $0.id == id }) else {
            return
        }

        let preferredWeek = SemesterConfig.currentWeek()
        let targetWeek = course.weeks.contains(preferredWeek)
            ? preferredWeek
            : course.weeks.sorted().first ?? preferredWeek
        currentWeek = targetWeek
        scrollToWeek = targetWeek
        selectedCourseContext = SelectedCourseContext(
            course: course,
            week: targetWeek,
            day: course.dayOfWeek,
            date: dateFor(dayOfWeek: course.dayOfWeek, in: targetWeek)
        )
    }

}
