import Charts
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct GradesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.leafyControlScale) private var leafyControlScale
    @Environment(\.leafyLanguage) private var leafyLanguage
    @Query(sort: \Grade.term, order: .reverse) private var grades: [Grade]

    let openAnalytics: (() -> Void)?

    @State private var isFetching = false
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var reauthenticationRequest: SchoolReauthenticationRequest?
    @State private var networkManager = ActiveCampusContext.networkManager
    @State private var collapsedTerms: Set<String> = []
    @State private var creditSummary: GradeCreditSummary? = SchoolDataCache.loadGradeCreditSummary()
    @State private var gradePresentationSnapshot = GradePresentationSnapshot.empty
    @State private var gradePresentationSignature = GradePresentationSignature()
    @State private var isGradeImportPresented = false
    @State private var isGradeImportGuidePresented = false

    init(openAnalytics: (() -> Void)? = nil) {
        self.openAnalytics = openAnalytics
    }

    private var isCustomCampus: Bool {
        ActiveCampusContext.identity?.isCustom == true
    }

    var body: some View {
        AcademicDetailScrollContainer {
            if grades.isEmpty && !isFetching {
                emptyGradesCard
            } else {
                Button {
                    openAnalytics?()
                } label: {
                    AcademicDetailCard {
                        GradeAnalyticsCard(analytics: gradePresentationSnapshot.analytics)
                    }
                }
                .buttonStyle(.plain)
                .disabled(openAnalytics == nil)
                .accessibilityLabel("查看成绩分析详情")
                .accessibilityHint("打开 GPA、分数分布和课程影响分析")
                AcademicDetailFooterText(text: gpaFooterText)

                ForEach(gradePresentationSnapshot.sortedTerms, id: \.self) { term in
                    termSection(term: term, grades: gradePresentationSnapshot.groupedGrades[term] ?? [])
                }
            }
        }
        .refreshable {
            await runPrimaryGradeAction()
        }
        .navigationTitle("成绩")
        .leafyInlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .leafyTrailing) {
                if isFetching {
                    ProgressView()
                } else {
                    Button {
                        Task { await runPrimaryGradeAction() }
                    } label: {
                        Image(systemName: isCustomCampus ? "tray.and.arrow.down" : "arrow.triangle.2.circlepath")
                    }
                    .accessibilityLabel(isCustomCampus ? "导入" : "刷新")
                }
            }
        }
        .fileImporter(
            isPresented: $isGradeImportPresented,
            allowedContentTypes: [.commaSeparatedText, .plainText, .text]
        ) { result in
            handleGradeImport(result)
        }
        .sheet(isPresented: $isGradeImportGuidePresented) {
            GradeCSVImportGuideSheet {
                isGradeImportGuidePresented = false
                isGradeImportPresented = true
            }
            .presentationDetents([.medium, .large])
        }
        .alert("提示", isPresented: $showAlert) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
        .schoolReauthenticationSheet(
            request: $reauthenticationRequest,
            networkManager: networkManager
        ) { _ in
            Task { await fetchGrades(userInitiated: true) }
        }
        .onAppear {
            creditSummary = SchoolDataCache.loadGradeCreditSummary()
            refreshGradePresentationIfNeeded()
            if grades.isEmpty, networkManager.isLoggedIn, !isCustomCampus {
                Task { await fetchGrades(userInitiated: false) }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .schoolDataDidRefresh)) { notification in
            let event = notification.object as? SchoolDataRefreshEvent
            guard event?.contains(.grades) == true || event?.contains(.gradeSupplemental) == true else { return }
            creditSummary = SchoolDataCache.loadGradeCreditSummary()
            refreshGradePresentationIfNeeded()
        }
        .onChange(of: GradePresentationSignature(grades: grades, creditSummary: creditSummary)) { _, _ in
            refreshGradePresentationIfNeeded()
        }
        .onChange(of: creditSummary) { _, _ in
            refreshGradePresentationIfNeeded()
        }
    }

    private func refreshGradePresentationIfNeeded() {
        let signature = GradePresentationSignature(grades: grades, creditSummary: creditSummary)
        guard signature != gradePresentationSignature else { return }
        gradePresentationSignature = signature
        gradePresentationSnapshot = GradePresentationSnapshot.make(grades: grades, creditSummary: creditSummary)
    }

    private var emptyGradesCard: some View {
        AcademicDetailCard {
            ContentUnavailableView {
                Label("暂无成绩缓存", systemImage: "list.bullet.rectangle.portrait")
            } description: {
                Text(isCustomCampus ? "可以从教务系统导出表格后按模板整理；也可以先只使用课表和考试功能。" : "连接校园网后可获取最新成绩。")
            } actions: {
                Button {
                    Task { await runPrimaryGradeAction() }
                } label: {
                    Label(isCustomCampus ? "查看导入模板" : "获取最新成绩", systemImage: isCustomCampus ? "doc.text.magnifyingglass" : "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.borderedProminent)
            }
            .tint(AppTheme.accent)
            .padding(.vertical, AppSpacing.page)
        }
    }

    private func termSection(term: String, grades: [Grade]) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            Button {
                withAnimation(.snappy) {
                    if collapsedTerms.contains(term) {
                        collapsedTerms.remove(term)
                    } else {
                        collapsedTerms.insert(term)
                    }
                }
            } label: {
                HStack {
                    Text(term)
                        .leafySubheadline()
                    Spacer()
                    Image(systemName: collapsedTerms.contains(term) ? "chevron.down" : "chevron.up")
                        .foregroundColor(.secondary)
                        .font(.system(size: 10 * leafyControlScale, weight: .semibold))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !collapsedTerms.contains(term) {
                AcademicDetailCard {
                    VStack(spacing: 0) {
                        ForEach(Array(grades.enumerated()), id: \.element.id) { index, grade in
                            if index > 0 {
                                AcademicDetailDivider()
                            }
                            gradeRow(grade)
                        }
                    }
                }
            }
        }
    }

    private var gpaFooterText: String {
        if gradePresentationSnapshot.analytics.officialGPA != nil {
            return L10n.text("GPA 使用学校官方数据。分数段、通过率和课程影响为 %@ 基于成绩明细整理。", language: leafyLanguage, AppBrand.displayName)
        }
        return L10n.text("当前页面未解析到学校官方 GPA，因此 GPA 暂不显示。", language: leafyLanguage)
    }

    private func gradeRow(_ grade: Grade) -> some View {
        HStack(alignment: .center, spacing: 12 * leafyControlScale) {
            VStack(alignment: .leading, spacing: 4 * leafyControlScale) {
                Text(grade.courseName)
                    .leafyHeadline()
                    .foregroundColor(.primary)

                HStack(spacing: 8 * leafyControlScale) {
                    GradeBadge(text: grade.type.isEmpty ? "未分类" : grade.type)
                    Text(L10n.text("%@ 学分", language: leafyLanguage, grade.credit))
                        .microCaption()
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Text(grade.score)
                .leafyTitle3()
                .foregroundColor(scoreColor(grade.score))
        }
        .padding(.vertical, 4 * leafyControlScale)
    }

    private func fetchGrades(userInitiated: Bool) async {
        guard !isFetching else { return }
        if isCustomCampus {
            await MainActor.run {
                isGradeImportPresented = true
            }
            return
        }
        if ReviewDemoMode.isEnabled {
            await MainActor.run {
                ReviewDemoDataSeeder.seed(using: modelContext)
                creditSummary = SchoolDataCache.loadGradeCreditSummary()
                alertMessage = L10n.text("已刷新演示成绩数据。", language: leafyLanguage)
                showAlert = true
            }
            return
        }

        if userInitiated,
           let request = await SchoolReauthentication.preflightRequest(
               networkManager: networkManager,
               context: .grades
           ) {
            await MainActor.run {
                reauthenticationRequest = request
            }
            return
        }

        guard networkManager.isLoggedIn else {
            if userInitiated, networkManager.hasCachedIdentity {
                reauthenticationRequest = SchoolReauthenticationRequest(context: .grades)
            } else {
                alertMessage = networkManager.hasCachedIdentity
                    ? L10n.text("本地身份已识别，但刷新成绩需要连接校园网并重新建立教务登录态。", language: leafyLanguage)
                    : L10n.text("请先连接校园网登录教务系统。", language: leafyLanguage)
                showAlert = true
            }
            return
        }
        await MainActor.run { isFetching = true }

        do {
            let htmlData = try await networkManager.fetchGrades()
            let newGrades = try HTMLParser.parseGrades(html: htmlData)
            let newRankings = (try? HTMLParser.parseGradeRankings(html: htmlData)) ?? []
            let parsedCreditSummary = try? HTMLParser.parseGradeCreditSummary(html: htmlData)

            await MainActor.run {
                if !newGrades.isEmpty {
                    for grade in grades {
                        modelContext.delete(grade)
                    }
                    for grade in newGrades {
                        modelContext.insert(grade)
                    }
                    try? modelContext.save()
                    SchoolDataCache.markGradeDetailsSynced()
                    SchoolDataRefreshNotifier.post(.grades)
                    if !newRankings.isEmpty {
                        SchoolDataCache.saveGradeRankings(newRankings)
                    }
                    if let parsedCreditSummary {
                        creditSummary = parsedCreditSummary
                        SchoolDataCache.saveGradeCreditSummary(parsedCreditSummary)
                    }
                } else {
                    alertMessage = L10n.text("未解析到任何成绩数据", language: leafyLanguage)
                    showAlert = true
                }
                isFetching = false
            }
        } catch {
            await MainActor.run {
                isFetching = false
                if userInitiated, SchoolReauthentication.shouldPromptForUserInitiatedAccess(error) {
                    reauthenticationRequest = SchoolReauthenticationRequest(context: .grades)
                } else {
                    alertMessage = L10n.text("抓取成绩失败：%@", language: leafyLanguage, error.localizedDescription)
                    showAlert = true
                }
            }
        }
    }

    @MainActor
    private func runPrimaryGradeAction() async {
        if isCustomCampus {
            isGradeImportGuidePresented = true
        } else {
            await fetchGrades(userInitiated: true)
        }
    }

    @MainActor
    private func handleGradeImport(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let count = try CustomCampusImportService.importGrades(
                from: url,
                existingGrades: grades,
                modelContext: modelContext
            )
            creditSummary = SchoolDataCache.loadGradeCreditSummary()
            refreshGradePresentationIfNeeded()
            alertMessage = L10n.text("已导入 %d 条成绩。", language: leafyLanguage, count)
            showAlert = true
        } catch {
            alertMessage = error.localizedDescription
            showAlert = true
        }
    }

    private func scoreColor(_ score: String) -> Color {
        if let value = Double(score) {
            if value < 60 { return .red }
            if value >= 90 { return AppTheme.accent }
        }
        if score.contains("不及格") { return .red }
        if score.contains("优秀") { return AppTheme.accent }
        return .primary
    }
}

private struct GradeAnalyticsCard: View {
    @Environment(\.leafyLanguage) private var leafyLanguage

    let analytics: GradeAnalytics

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("成绩分析", systemImage: "chart.line.uptrend.xyaxis")
                    .leafyHeadline()
                    .foregroundStyle(AppTheme.primaryText)
                Spacer()
                HStack(spacing: 4) {
                    Text("点击查看详情")
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                }
                .microCaption()
                .foregroundStyle(AppTheme.accentEmphasis)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(AppTheme.softFill, in: Capsule())
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
                analyticsItem(
                    title: "GPA",
                    value: analytics.displayGPA.map(format) ?? "--",
                    subtitle: analytics.gpaSourceText
                )
                analyticsItem(
                    title: "加权均分",
                    value: analytics.displayWeightedAverage.map(format) ?? "--",
                    subtitle: analytics.weightedAverageSourceText
                )
                analyticsItem(title: "总学分", value: format(analytics.totalCredits), subtitle: "有效课程")
                analyticsItem(title: "风险课程", value: "\(analytics.riskCourseCount)", subtitle: "未通过", isRisk: analytics.riskCourseCount > 0)
            }
        }
        .padding(.vertical, 4)
    }

    private func analyticsItem(title: String, value: String, subtitle: String, isRisk: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.text(title, language: leafyLanguage))
                .microCaption()
                .foregroundStyle(AppTheme.secondaryText)
            Text(value)
                .leafyTitle3()
                .foregroundStyle(isRisk ? AppTheme.danger : AppTheme.primaryText)
            Text(L10n.text(subtitle, language: leafyLanguage))
                .microCaption()
                .foregroundStyle(AppTheme.tertiaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppTheme.fill, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
    }

    private func format(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}

private enum GradeCourseSort: String, CaseIterable, Identifiable {
    case term = "学期"
    case score = "分数"
    case impact = "影响"

    var id: String { rawValue }
}

private struct GradeCSVShareItem: Identifiable {
    let url: URL

    var id: URL { url }
}

private struct GradeCSVImportGuideSheet: View {
    let onImport: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.card) {
                    AcademicDetailCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("成绩 CSV 模板", systemImage: "doc.text.magnifyingglass")
                                .leafyHeadline()
                            Text("通用学校不会连接教务系统。你可以从学校系统导出成绩表，再按下面字段整理后导入；导入会替换当前成绩缓存。")
                                .leafyBody()
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                    }

                    AcademicDetailCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("CSV 字段")
                                .leafyHeadline()
                            Text(CustomCampusCSVParser.gradeColumns.joined(separator: ", "))
                                .font(.system(.footnote, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(AppTheme.fill, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
                            Text("term 可写学期，credit 和 score 按学校原表填写；type 可写必修、选修、通识等分类。")
                                .microCaption()
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                    }

                    AcademicDetailCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("示例")
                                .leafyHeadline()
                            Text(Self.sampleCSV)
                                .font(.system(.footnote, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(AppTheme.fill, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
                        }
                    }
                }
                .padding(AppSpacing.page)
            }
            .background(LeafyPageBackground())
            .navigationTitle("导入成绩")
            .leafyInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("选择文件") {
                        onImport()
                    }
                }
            }
        }
    }

    private static let sampleCSV = """
term,courseName,credit,score,type
2025-2026-1,大学英语,2.0,88,必修
"""
}

struct GradeAnalyticsDetailView: View {
    @Environment(\.leafyLanguage) private var leafyLanguage
    @Query(sort: \Grade.term, order: .reverse) private var grades: [Grade]

    @State private var rankings: [GradeRankingRecord] = SchoolDataCache.loadGradeRankings()
    @State private var rankingMessage = L10n.text("正在查询官方排名")
    @State private var isLoadingRankings = false
    @State private var creditSummary: GradeCreditSummary? = SchoolDataCache.loadGradeCreditSummary()
    @State private var networkManager = ActiveCampusContext.networkManager
    @State private var courseSort: GradeCourseSort = .term
    @State private var sharePreviewImage: UIImage?
    @State private var csvShareItem: GradeCSVShareItem?
    @State private var exportErrorMessage: String?
    @State private var presentationSnapshot = GradePresentationSnapshot.empty
    @State private var presentationSignature = GradePresentationSignature()

    private var displayedAnalytics: GradeAnalytics { presentationSnapshot.analytics }
    private var isCustomCampus: Bool { ActiveCampusContext.identity?.isCustom == true }

    var body: some View {
        AcademicDetailScrollContainer {
            GradeOverviewCard(
                analytics: displayedAnalytics,
                gradeCountingNote: gradeCountingNote,
                summaryText: summaryText
            )

            GradeDetailCard(title: "成绩趋势", systemImage: "chart.xyaxis.line", subtitle: "按有效课程口径计算") {
                GradeTermTrendChart(termSummaries: displayedAnalytics.termSummaries)
                GradeScoreDistributionChart(analytics: displayedAnalytics)
            }

            GradeDetailCard(title: "官方排名", systemImage: "chart.bar.xaxis", subtitle: "来自教务系统官方页面") {
                if isLoadingRankings && rankings.isEmpty {
                    HStack {
                        ProgressView()
                        Text("正在查询强智官方排名")
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                } else if rankings.isEmpty {
                    Text(rankingMessage)
                        .foregroundStyle(AppTheme.secondaryText)
                } else {
                    RankingAnalysisCard(analytics: displayedAnalytics, rankings: rankings)
                    if !periodRankings.isEmpty {
                        RankingTrendChart(rankings: periodRankings)
                    }
                    if !overallRankings.isEmpty {
                        rankingRecordGroup(title: "总排名", records: overallRankings)
                    }
                    ForEach(groupedPeriodRankings) { group in
                        rankingRecordGroup(title: group.range, records: group.records)
                    }
                }
            }

            GradeDetailCard(title: "课程结构", systemImage: "square.grid.2x2", subtitle: "学分、分数段和课程类型") {
                GradeCreditStructureChart(analytics: displayedAnalytics)
                GradeCourseExplorerCard(
                    analytics: displayedAnalytics,
                    sort: $courseSort
                )
            }

            GradeDetailCard(title: "统计口径", systemImage: "info.circle", subtitle: "GPA 只使用官方值") {
                Text(methodologyText)
                    .leafyBody()
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .navigationTitle("成绩详情")
        .leafyInlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .leafyTrailing) {
                Menu {
                    Button {
                        generateSharePreview()
                    } label: {
                        Label("导出概览图片", systemImage: "photo")
                    }
                    Button {
                        exportCSV()
                    } label: {
                        Label("导出 CSV 表格", systemImage: "tablecells")
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(grades.isEmpty)
            }
        }
        .sheet(isPresented: Binding(
            get: { sharePreviewImage != nil },
            set: { if !$0 { sharePreviewImage = nil } }
        )) {
            if let sharePreviewImage {
                GradeShareImagePreviewSheet(image: sharePreviewImage)
            }
        }
        .sheet(item: $csvShareItem) { item in
            ShareSheet(activityItems: [item.url])
        }
        .alert("无法导出", isPresented: Binding(
            get: { exportErrorMessage != nil },
            set: { if !$0 { exportErrorMessage = nil } }
        )) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(exportErrorMessage ?? "")
        }
        .task {
            await loadSupplementalData()
        }
        .onAppear(perform: refreshPresentationSnapshotIfNeeded)
        .onReceive(NotificationCenter.default.publisher(for: .schoolDataDidRefresh)) { notification in
            let event = notification.object as? SchoolDataRefreshEvent
            guard event?.contains(.grades) == true || event?.contains(.gradeSupplemental) == true else { return }
            rankings = SchoolDataCache.loadGradeRankings()
            creditSummary = SchoolDataCache.loadGradeCreditSummary()
            refreshPresentationSnapshotIfNeeded()
        }
        .onChange(of: GradePresentationSignature(grades: grades, creditSummary: creditSummary)) { _, _ in
            refreshPresentationSnapshotIfNeeded()
        }
    }

    private var gradeCountingNote: String {
        if displayedAnalytics.rawRecordCount != displayedAnalytics.effectiveCourseCount {
            return L10n.text(
                "统计已按课程去重：原始成绩 %d 条，归并为 %d 门有效课程；成绩单列表仍保留期考、补考和重修记录。",
                language: leafyLanguage,
                displayedAnalytics.rawRecordCount,
                displayedAnalytics.effectiveCourseCount
            )
        }

        return L10n.text("统计按有效课程计算；成绩单列表仍保留期考、补考和重修记录。", language: leafyLanguage)
    }

    private var summaryText: String {
        let averageText = displayedAnalytics.displayWeightedAverage.map(format) ?? L10n.text("暂无", language: leafyLanguage)
        let gpaText = displayedAnalytics.displayGPA.map(format) ?? L10n.text("未获取", language: leafyLanguage)
        let riskText = displayedAnalytics.riskCourseCount == 0 ? L10n.text("目前没有未通过课程", language: leafyLanguage) : L10n.text("有 %d 门未通过课程", language: leafyLanguage, displayedAnalytics.riskCourseCount)
        let trendText = displayedAnalytics.termSummaries.count <= 1 ? L10n.text("当前成绩学期较少，趋势判断需要继续积累数据", language: leafyLanguage) : L10n.text("已形成 %d 个学期的趋势记录", language: leafyLanguage, displayedAnalytics.termSummaries.count)
        return L10n.text("当前%@均分 %@，官方 GPA %@，已通过学分 %@，%@。%@。建议优先关注低分和高学分课程。", language: leafyLanguage, displayedAnalytics.weightedAverageSourceText, averageText, gpaText, format(displayedAnalytics.passedCredits), riskText, trendText)
    }

    private var methodologyText: String {
        let officialText = displayedAnalytics.officialGPA == nil
            ? L10n.text("当前缓存没有解析到学校官方 GPA，因此 GPA 暂不展示。", language: leafyLanguage)
            : L10n.text("页面已解析到学校官方 GPA，GPA 展示只使用官方值。", language: leafyLanguage)
        return officialText + L10n.text(" 其他统计按有效课程计算：同名同学分课程会合并，补考或重修优先取已通过且分数最高记录；优秀、良好、中等等明确等级会映射为可解释的分值，通过制成绩只计通过与学分，不计入分数统计。", language: leafyLanguage)
    }

    private var overallRankings: [GradeRankingRecord] {
        rankings
            .filter(\.isOverall)
            .sorted(by: rankingRecordSort)
    }

    private var periodRankings: [GradeRankingRecord] {
        rankings
            .filter(\.isPeriodRecord)
            .sorted(by: rankingRecordSort)
    }

    private var groupedPeriodRankings: [RankingRecordGroup] {
        Dictionary(grouping: periodRankings, by: \.rankingRange)
            .map { range, records in
                RankingRecordGroup(
                    range: range,
                    records: records.sorted(by: rankingRecordSort)
                )
            }
            .sorted { lhs, rhs in
                let leftPriority = rankingRangePriority(lhs.range)
                let rightPriority = rankingRangePriority(rhs.range)
                if leftPriority != rightPriority {
                    return leftPriority < rightPriority
                }
                return lhs.range.localizedCompare(rhs.range) == .orderedAscending
            }
    }

    private func rankingRangePriority(_ range: String) -> Int {
        if range.contains("班") { return 0 }
        if range.contains("专业") { return 1 }
        if range.contains("年级") { return 2 }
        if range.contains("学院") { return 3 }
        return 4
    }

    private func rankingRecordSort(_ lhs: GradeRankingRecord, _ rhs: GradeRankingRecord) -> Bool {
        if lhs.term != rhs.term {
            return lhs.term > rhs.term
        }
        if let leftPercentile = lhs.percentile,
           let rightPercentile = rhs.percentile,
           leftPercentile != rightPercentile {
            return leftPercentile < rightPercentile
        }
        return (lhs.rank ?? Int.max) < (rhs.rank ?? Int.max)
    }

    private func rankingRecordGroup(title: String, records: [GradeRankingRecord]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.text(title, language: leafyLanguage))
                .microCaption()
                .fontWeight(.semibold)
                .foregroundStyle(AppTheme.accentEmphasis)

            ForEach(records) { record in
                rankingRecordRow(record)
            }
        }
        .padding(.vertical, 4)
    }

    private func rankingRecordRow(_ record: GradeRankingRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.metricText.isEmpty ? L10n.text("官方排名明细", language: leafyLanguage) : record.metricText)
                        .leafyHeadline()
                    Text(record.term)
                        .microCaption()
                        .foregroundStyle(AppTheme.secondaryText)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(record.displayRank)
                        .leafyTitle3()
                        .foregroundStyle(AppTheme.primaryText)
                    Text(record.displayPercentile)
                        .microCaption()
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }

            if let percentile = record.percentile {
                Text(rankingBandText(percentile))
                    .microCaption()
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .padding(10)
        .background(AppTheme.fill, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
    }

    private func rankingBandText(_ percentile: Double) -> String {
        switch percentile {
        case ..<0.1:
            return L10n.text("处在前 10%，优势明显", language: leafyLanguage)
        case ..<0.3:
            return L10n.text("处在前 30%，整体表现靠前", language: leafyLanguage)
        case ..<0.5:
            return L10n.text("处在前半段，继续拉开差距", language: leafyLanguage)
        default:
            return L10n.text("仍有提升空间，优先处理高学分和低分课程", language: leafyLanguage)
        }
    }

    @MainActor
    private func generateSharePreview() {
        let content = GradeSummaryShareCard(analytics: displayedAnalytics)
        .frame(width: 390)
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
            exportErrorMessage = L10n.text("请稍后重试，或先截图保存当前页面。", language: leafyLanguage)
            return
        }

        sharePreviewImage = image
    }

    private func exportCSV() {
        do {
            let url = try GradeExportBuilder.makeCSVFile(grades: grades)
            csvShareItem = GradeCSVShareItem(url: url)
        } catch {
            exportErrorMessage = error.localizedDescription
        }
    }

    private func format(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private func loadSupplementalData() async {
        rankings = SchoolDataCache.loadGradeRankings()
        creditSummary = SchoolDataCache.loadGradeCreditSummary()
        refreshPresentationSnapshotIfNeeded()

        guard !isCustomCampus else {
            rankingMessage = L10n.text("通用入口暂无官方排名导入入口。", language: leafyLanguage)
            return
        }

        guard networkManager.isLoggedIn else {
            if rankings.isEmpty {
                rankingMessage = L10n.text("教务暂未开放成绩排名，或需要连接校园网后重新登录查询。", language: leafyLanguage)
            }
            return
        }

        await loadRankings()
    }

    private func loadRankings() async {
        guard !isLoadingRankings else { return }
        if ReviewDemoMode.isEnabled {
            await MainActor.run {
                ReviewDemoDataSeeder.refreshSchoolCaches()
                rankings = SchoolDataCache.loadGradeRankings()
                creditSummary = SchoolDataCache.loadGradeCreditSummary()
                rankingMessage = ""
                isLoadingRankings = false
            }
            return
        }

        await MainActor.run {
            isLoadingRankings = true
            rankingMessage = L10n.text("正在查询官方排名", language: leafyLanguage)
        }

        do {
            let html = try await networkManager.fetchGradeRankings()
            let parsed = try HTMLParser.parseGradeRankings(html: html)
            let parsedCreditSummary = try? HTMLParser.parseGradeCreditSummary(html: html)
            await MainActor.run {
                rankings = parsed
                SchoolDataCache.saveGradeRankings(parsed)
                if let parsedCreditSummary {
                    creditSummary = parsedCreditSummary
                    SchoolDataCache.saveGradeCreditSummary(parsedCreditSummary)
                }
                refreshPresentationSnapshotIfNeeded()
                rankingMessage = parsed.isEmpty ? L10n.text("教务暂未开放成绩排名。", language: leafyLanguage) : ""
                isLoadingRankings = false
            }
        } catch {
            await MainActor.run {
                rankingMessage = error.localizedDescription.isEmpty ? L10n.text("教务暂未开放成绩排名。", language: leafyLanguage) : error.localizedDescription
                isLoadingRankings = false
            }
        }
    }

    private func refreshPresentationSnapshotIfNeeded() {
        let signature = GradePresentationSignature(grades: grades, creditSummary: creditSummary)
        guard signature != presentationSignature else { return }
        presentationSignature = signature
        presentationSnapshot = GradePresentationSnapshot.make(grades: grades, creditSummary: creditSummary)
    }
}

private struct GradeOverviewCard: View {
    @Environment(\.leafyLanguage) private var leafyLanguage

    let analytics: GradeAnalytics
    let gradeCountingNote: String
    let summaryText: String

    var body: some View {
        GradeDetailCard(title: "概览", systemImage: "chart.line.uptrend.xyaxis", subtitle: gradeCountingNote) {
            ViewThatFits(in: .horizontal) {
                metricGrid(columnCount: 3)
                metricGrid(columnCount: 2)
            }

            if let officialCreditPoint = analytics.officialCreditPoint {
                HStack {
                    Label("官方学分积", systemImage: "number")
                        .foregroundStyle(AppTheme.secondaryText)
                    Spacer()
                    Text(format(officialCreditPoint))
                        .foregroundStyle(AppTheme.primaryText)
                }
                .leafySubheadline()
                .padding(10)
                .background(AppTheme.fill, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
            }

            Text(summaryText)
                .leafyBody()
                .foregroundStyle(AppTheme.secondaryText)
        }
    }

    private func metricGrid(columnCount: Int) -> some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: columnCount),
            spacing: 10
        ) {
            GradeMetricTile(title: "GPA", value: analytics.displayGPA.map(format) ?? "--", subtitle: analytics.gpaSourceText)
            GradeMetricTile(title: "均分", value: analytics.displayWeightedAverage.map(format) ?? "--", subtitle: analytics.weightedAverageSourceText)
            GradeMetricTile(title: "通过率", value: analytics.passRate.map(percent) ?? "--", subtitle: "\(analytics.effectiveCourseCount) 门有效课")
            GradeMetricTile(title: "学分", value: creditFormat(analytics.totalCredits), subtitle: "\(creditFormat(analytics.passedCredits)) 已通过")
            GradeMetricTile(title: "中位数", value: analytics.medianScore.map(format) ?? "--", subtitle: "基础统计")
            GradeMetricTile(title: "标准差", value: analytics.standardDeviation.map(format) ?? "--", subtitle: "分数离散度")
        }
    }

    private func format(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private func creditFormat(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private func percent(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }
}

private struct GradeDetailCard<Content: View>: View {
    let title: String
    let systemImage: String
    let subtitle: String?
    @ViewBuilder let content: () -> Content

    init(title: String, systemImage: String, subtitle: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.subtitle = subtitle
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                LeafyIconBadge(systemName: systemImage)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .leafyHeadline()
                        .foregroundStyle(AppTheme.primaryText)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .microCaption()
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }
                Spacer()
            }
            content()
        }
        .padding(16)
        .leafyCardStyle()
    }
}

private struct GradeMetricTile: View {
    @Environment(\.leafyLanguage) private var leafyLanguage

    let title: String
    let value: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.text(title, language: leafyLanguage))
                .microCaption()
                .foregroundStyle(AppTheme.secondaryText)
            Text(value)
                .leafyTitle3()
                .foregroundStyle(AppTheme.primaryText)
            Text(L10n.text(subtitle, language: leafyLanguage))
                .microCaption()
                .foregroundStyle(AppTheme.tertiaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppTheme.fill, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(L10n.text(title, language: leafyLanguage)) \(value)，\(L10n.text(subtitle, language: leafyLanguage))")
    }
}

private struct GradeTermTrendChart: View {
    let termSummaries: [GradeAnalytics.TermSummary]

    private var chronologicalTerms: [GradeAnalytics.TermSummary] {
        termSummaries.sorted { $0.term < $1.term }
    }

    private var drawableTerms: [GradeAnalytics.TermSummary] {
        chronologicalTerms.filter { $0.weightedAverage != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if drawableTerms.count <= 1 {
                Text("当前只有 1 个学期的成绩，暂时无法形成趋势。")
                    .foregroundStyle(AppTheme.secondaryText)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("加权均分")
                        .microCaption()
                        .foregroundStyle(AppTheme.secondaryText)
                    Text(summaryText)
                        .microCaption()
                        .foregroundStyle(AppTheme.tertiaryText)

                    Chart(drawableTerms) { term in
                        if let average = term.weightedAverage {
                            LineMark(x: .value("学期", term.term), y: .value("均分", average))
                                .foregroundStyle(AppTheme.accent)
                                .interpolationMethod(.catmullRom)
                            PointMark(x: .value("学期", term.term), y: .value("均分", average))
                                .foregroundStyle(AppTheme.accent)
                                .annotation(position: .top) {
                                    Text(String(format: "%.0f", average))
                                        .microCaption()
                                        .foregroundStyle(AppTheme.secondaryText)
                                }
                        }
                    }
                    .chartYScale(domain: 0...100)
                    .chartYAxis {
                        AxisMarks(position: .leading, values: [60, 70, 80, 90, 100]) { _ in
                            AxisGridLine()
                                .foregroundStyle(AppTheme.separator)
                            AxisTick()
                            AxisValueLabel()
                        }
                    }
                    .chartXAxis {
                        AxisMarks { _ in
                            AxisValueLabel()
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                    }
                    .frame(height: 150)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("加权均分趋势")
                    .accessibilityValue(summaryText)
                }

                Text("学校官方 GPA 当前只按总览展示，未解析到学期拆分时不绘制 GPA 趋势。")
                    .microCaption()
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
    }

    private var summaryText: String {
        guard let first = drawableTerms.first,
              let last = drawableTerms.last,
              let firstAverage = first.weightedAverage,
              let lastAverage = last.weightedAverage
        else {
            return "暂未形成可分析趋势。"
        }

        let delta = lastAverage - firstAverage
        let direction = delta >= 0 ? "上升" : "下降"
        return "\(first.term) 到 \(last.term) 均分\(direction) \(String(format: "%.1f", abs(delta))) 分。"
    }
}

private struct GradeScoreDistributionChart: View {
    let analytics: GradeAnalytics

    private var visibleBuckets: [GradeAnalytics.ScoreDistributionBucket] {
        analytics.scoreDistribution.filter { $0.count > 0 }
    }

    private var summaryText: String {
        guard let mostCommon = visibleBuckets.max(by: { $0.count < $1.count }) else {
            return "暂无分数段数据。"
        }
        let riskCount = analytics.riskCourseCount
        if riskCount > 0 {
            return "最多课程集中在 \(mostCommon.range)，另有 \(riskCount) 门未通过课程。"
        }
        return "最多课程集中在 \(mostCommon.range)，当前没有未通过课程。"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("分数段分布")
                .leafySubheadline()
                .foregroundStyle(AppTheme.primaryText)

            if visibleBuckets.isEmpty {
                GradeChartUnavailableText("暂无可绘制的分数段数据。")
            } else {
                Text(summaryText)
                    .microCaption()
                    .foregroundStyle(AppTheme.tertiaryText)

                Chart(analytics.scoreDistribution) { bucket in
                    BarMark(
                        x: .value("分数段", bucket.range),
                        y: .value("课程数", bucket.count)
                    )
                    .foregroundStyle(bucket.range == "<60" ? AppTheme.danger : AppTheme.accent)
                    .annotation(position: .top) {
                        if bucket.count > 0 {
                            Text("\(bucket.count)")
                                .microCaption()
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine()
                            .foregroundStyle(AppTheme.separator)
                        AxisTick()
                        AxisValueLabel()
                    }
                }
                .frame(height: 170)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("分数段分布")
                .accessibilityValue(summaryText)
            }
        }
    }
}

private struct GradeCreditStructureChart: View {
    let analytics: GradeAnalytics

    private var sortedCategories: [GradeAnalytics.CategorySummary] {
        analytics.categorySummaries.sorted { $0.credits > $1.credits }
    }

    private var summaryText: String {
        guard let leading = sortedCategories.first else {
            return "暂无课程类型学分数据。"
        }
        return "\(leading.name) 学分最多，共 \(String(format: "%.1f", leading.credits)) 学分。"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("课程类型学分")
                .leafySubheadline()
                .foregroundStyle(AppTheme.primaryText)

            if sortedCategories.isEmpty {
                GradeChartUnavailableText("暂无可分析的课程类型。")
            } else {
                Text(summaryText)
                    .microCaption()
                    .foregroundStyle(AppTheme.tertiaryText)

                Chart(sortedCategories) { category in
                    BarMark(
                        x: .value("学分", category.credits),
                        y: .value("类别", category.name)
                    )
                    .foregroundStyle(AppTheme.accent)
                    .annotation(position: .trailing) {
                        Text(String(format: "%.1f", category.credits))
                            .microCaption()
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }
                .chartXAxis {
                    AxisMarks { _ in
                        AxisGridLine()
                            .foregroundStyle(AppTheme.separator)
                        AxisTick()
                        AxisValueLabel()
                    }
                }
                .frame(height: max(CGFloat(sortedCategories.count) * 38, 132))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("课程类型学分")
                .accessibilityValue(summaryText)
            }
        }
    }
}

private struct GradeCourseExplorerCard: View {
    @Environment(\.leafyLanguage) private var leafyLanguage

    let analytics: GradeAnalytics
    @Binding var sort: GradeCourseSort

    private var sortedCourses: [GradeAnalytics.CoursePerformance] {
        switch sort {
        case .term:
            return analytics.courses.sorted {
                if $0.term != $1.term { return $0.term > $1.term }
                return scoreDescending($0, $1)
            }
        case .score:
            return analytics.courses.sorted(by: scoreDescending)
        case .impact:
            return analytics.highImpactCourses
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    courseListTitle
                    Spacer()
                    sortPicker
                }

                VStack(alignment: .leading, spacing: 8) {
                    courseListTitle
                    sortPicker
                }
            }

            ForEach(sortedCourses) { course in
                GradeCourseAnalysisRow(course: course)
            }
        }
    }

    private var courseListTitle: some View {
        Text("课程明细")
            .leafySubheadline()
            .foregroundStyle(AppTheme.primaryText)
    }

    private var sortPicker: some View {
        Picker("排序", selection: $sort) {
            ForEach(GradeCourseSort.allCases) { item in
                Text(item.rawValue).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 180)
    }
}

private struct GradeCourseAnalysisRow: View {
    let course: GradeAnalytics.CoursePerformance

    var body: some View {
        ViewThatFits(in: .horizontal) {
            horizontalLayout
            verticalLayout
        }
        .padding(10)
        .background(AppTheme.fill, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(course.name)，成绩 \(course.rawScore)，\(String(format: "%.1f", course.credit)) 学分，\(course.term)")
    }

    private var horizontalLayout: some View {
        HStack(alignment: .top, spacing: 12) {
            courseText

            Spacer(minLength: 10)

            scoreText
        }
    }

    private var verticalLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            courseText
            scoreText
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var courseText: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(course.name)
                .leafyHeadline()
                .foregroundStyle(AppTheme.primaryText)
                .lineLimit(3)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    courseBadges
                }
                VStack(alignment: .leading, spacing: 4) {
                    courseBadges
                }
            }
        }
    }

    @ViewBuilder
    private var courseBadges: some View {
        GradeBadge(text: course.type)
        if course.attemptCount > 1 {
            GradeBadge(text: "\(course.attemptCount) 次记录")
        }
        Text(course.term)
            .microCaption()
            .foregroundStyle(AppTheme.secondaryText)
    }

    private var scoreText: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(course.rawScore)
                .leafyTitle3()
                .foregroundStyle(course.isPassed ? AppTheme.primaryText : AppTheme.danger)
            Text("\(String(format: "%.1f", course.credit)) 学分")
                .microCaption()
                .foregroundStyle(AppTheme.secondaryText)
        }
    }
}

private func scoreDescending(_ lhs: GradeAnalytics.CoursePerformance, _ rhs: GradeAnalytics.CoursePerformance) -> Bool {
    switch (lhs.score, rhs.score) {
    case let (leftScore?, rightScore?):
        if leftScore != rightScore { return leftScore > rightScore }
    case (_?, nil):
        return true
    case (nil, _?):
        return false
    case (nil, nil):
        break
    }
    if lhs.term != rhs.term {
        return lhs.term > rhs.term
    }
    return lhs.name.localizedCompare(rhs.name) == .orderedAscending
}

private struct GradeChartUnavailableText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .leafyBody()
            .foregroundStyle(AppTheme.secondaryText)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .padding(12)
            .background(AppTheme.fill, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
    }
}

private struct RankingRecordGroup: Identifiable {
    let range: String
    let records: [GradeRankingRecord]

    var id: String { range }
}

private struct RankingTrendChart: View {
    let rankings: [GradeRankingRecord]

    private var points: [GradeRankingRecord] {
        rankings
            .filter { $0.rank != nil }
            .sorted { lhs, rhs in
                if lhs.term != rhs.term {
                    return lhs.term < rhs.term
                }
                return lhs.rankingRange.localizedCompare(rhs.rankingRange) == .orderedAscending
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("排名趋势")
                .leafySubheadline()
                .foregroundStyle(AppTheme.primaryText)

            if points.count < 2 {
                Text("学期段排名记录较少，暂时无法形成折线趋势。")
                    .microCaption()
                    .foregroundStyle(AppTheme.secondaryText)
            } else {
                Chart(points) { record in
                    if let rank = record.rank {
                        LineMark(
                            x: .value("学年", record.term),
                            y: .value("名次", -rank)
                        )
                        .foregroundStyle(by: .value("范围", record.rankingRange))
                        .interpolationMethod(.catmullRom)

                        PointMark(
                            x: .value("学年", record.term),
                            y: .value("名次", -rank)
                        )
                        .foregroundStyle(by: .value("范围", record.rankingRange))
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel {
                            if let negativeRank = value.as(Int.self) {
                                Text("\(-negativeRank)")
                            }
                        }
                    }
                }
                .chartLegend(position: .bottom, alignment: .leading)
                .frame(height: 180)
            }
        }
    }
}

private struct RankingAnalysisCard: View {
    @Environment(\.leafyLanguage) private var leafyLanguage

    let analytics: GradeAnalytics
    let rankings: [GradeRankingRecord]

    private var candidateRankings: [GradeRankingRecord] {
        let overall = rankings.filter(\.isOverall)
        return overall.isEmpty ? rankings : overall
    }

    private var bestRecord: GradeRankingRecord? {
        candidateRankings.min { lhs, rhs in
            switch (lhs.percentile, rhs.percentile) {
            case let (left?, right?):
                if left != right { return left < right }
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                break
            }
            return (lhs.rank ?? Int.max) < (rhs.rank ?? Int.max)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Label("排名分析", systemImage: "chart.bar.xaxis")
                        .leafyHeadline()
                        .foregroundStyle(AppTheme.primaryText)
                    Text(summaryText)
                        .microCaption()
                        .foregroundStyle(AppTheme.secondaryText)
                }

                Spacer()

                if let bestRecord {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(bestRecord.displayRank)
                            .leafyTitle3()
                            .foregroundStyle(AppTheme.accentEmphasis)
                        Text(bestRecord.displayPercentile)
                            .microCaption()
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }
            }

            if let bestRecord {
                HStack(spacing: 10) {
                    rankingMetric("范围", bestRecord.rankingRange)
                    rankingMetric("指标", bestRecord.metricText.isEmpty ? "官方成绩" : bestRecord.metricText)
                }
            }

            Text(actionText)
                .leafyBody()
                .foregroundStyle(AppTheme.primaryText)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.softFill, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
        }
    }

    private func rankingMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(L10n.text(title, language: leafyLanguage))
                .microCaption()
                .foregroundStyle(AppTheme.secondaryText)
            Text(value)
                .leafySubheadline()
                .foregroundStyle(AppTheme.primaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(AppTheme.fill, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
    }

    private var summaryText: String {
        guard let bestRecord else {
            return L10n.text("暂无可分析的官方排名。", language: leafyLanguage)
        }

        let rangeText = bestRecord.rankingRange
        let percentileText = bestRecord.percentile.map(rankingBandText) ?? L10n.text("已取得官方名次", language: leafyLanguage)
        return L10n.text("%@ %@，%@。", language: leafyLanguage, rangeText, bestRecord.displayRank, percentileText)
    }

    private var actionText: String {
        let averageText = analytics.displayWeightedAverage.map { String(format: "%.2f", $0) } ?? "--"
        let gpaText = analytics.displayGPA.map { String(format: "%.2f", $0) } ?? "未获取"
        let riskText = analytics.riskCourseCount > 0
            ? L10n.text("还有 %d 门风险课程需要优先处理", language: leafyLanguage, analytics.riskCourseCount)
            : L10n.text("目前没有未通过课程", language: leafyLanguage)
        let impactCourse = analytics.highImpactCourses.first

        if let impactCourse {
            return L10n.text("结合均分 %@、官方 GPA %@ 和已通过学分，下一步最值得关注的是 %@：它有 %.1f 学分，对排名和整体成绩牵引更明显；%@。", language: leafyLanguage, averageText, gpaText, impactCourse.name, impactCourse.credit, riskText)
        }

        return L10n.text("结合均分 %@、官方 GPA %@ 和已通过学分，建议继续稳定高学分课程表现；%@。", language: leafyLanguage, averageText, gpaText, riskText)
    }

    private func rankingBandText(_ percentile: Double) -> String {
        switch percentile {
        case ..<0.1:
            return L10n.text("处在前 10%，优势明显", language: leafyLanguage)
        case ..<0.3:
            return L10n.text("处在前 30%，整体靠前", language: leafyLanguage)
        case ..<0.5:
            return L10n.text("处在前半段，继续拉开差距", language: leafyLanguage)
        default:
            return L10n.text("仍有提升空间", language: leafyLanguage)
        }
    }
}

private struct GradeSummaryShareCard: View {
    let analytics: GradeAnalytics

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(AppBrand.displayName) 成绩概览")
                        .font(.system(size: 22, weight: .semibold))
                    Text(Date(), format: .dateTime.year().month().day())
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Spacer()
                Image(systemName: "leaf.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
                shareMetric("GPA", analytics.displayGPA.map(format) ?? "--", analytics.gpaSourceText)
                shareMetric("均分", analytics.displayWeightedAverage.map(format) ?? "--", analytics.weightedAverageSourceText)
                shareMetric("学分", creditFormat(analytics.totalCredits), "\(creditFormat(analytics.passedCredits)) 已通过")
                shareMetric("通过率", analytics.passRate.map(percent) ?? "--", "\(analytics.effectiveCourseCount) 门有效课")
            }

            Text("GPA 只使用学校官方数据；没有解析到官方值时不展示 GPA。")
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.secondaryText)
        }
        .padding(18)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
    }

    private func shareMetric(_ title: String, _ value: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.secondaryText)
            Text(value)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(AppTheme.primaryText)
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundStyle(AppTheme.tertiaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppTheme.fill, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
    }

    private func format(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private func creditFormat(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private func percent(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }
}

private struct GradeShareImagePreviewSheet: View {
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

private struct GradeBadge: View {
    @Environment(\.leafyControlScale) private var leafyControlScale
    @Environment(\.leafyLanguage) private var leafyLanguage

    let text: String

    var body: some View {
        Text(L10n.text(text, language: leafyLanguage))
            .microCaption()
            .padding(.horizontal, 6 * leafyControlScale)
            .padding(.vertical, 2 * leafyControlScale)
            .background(AppTheme.softFill, in: Capsule())
    }
}

#Preview {
    NavigationStack {
        GradesView()
    }
}
