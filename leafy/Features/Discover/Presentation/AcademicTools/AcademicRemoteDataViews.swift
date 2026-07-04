import Combine
import QuickLook
import Supabase
import SwiftUI
import SwiftData
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct ExamScheduleView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var networkManager = ActiveCampusContext.networkManager
    @State private var exams: [ExamArrangement] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var reauthenticationRequest: SchoolReauthenticationRequest?
    @State private var isExamImportPresented = false
    @State private var editingExam: ExamEditorItem?
    @State private var operationAlert: LeafyOperationAlert?

    private var isCustomCampus: Bool {
        ActiveCampusContext.identity?.isCustom == true
    }

    var body: some View {
        AcademicDetailScrollContainer {
            AcademicDetailSectionHeader(title: "考试安排")

            if isLoading, exams.isEmpty {
                examStatusCard {
                    HStack(spacing: AppSpacing.compact) {
                        ProgressView()
                        Text("正在拉取考试安排")
                            .leafySubheadline()
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }

            if let errorMessage {
                examStatusCard {
                    Text(errorMessage)
                        .leafyBody()
                        .foregroundStyle(.red)
                }
            }

            if exams.isEmpty, !isLoading, errorMessage == nil {
                examStatusCard {
                    ContentUnavailableView {
                        Label("暂无考试安排", systemImage: "doc.text.magnifyingglass")
                    } description: {
                        Text(isCustomCampus ? "手动添加或导入考试后，会显示在考试安排和课表考试提示中。" : "连接校园网后可获取考试安排。")
                    } actions: {
                        if isCustomCampus {
                            Button {
                                editingExam = ExamEditorItem()
                            } label: {
                                Label("添加考试", systemImage: "plus")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .tint(AppTheme.accent)
                }
            }

            ForEach(exams) { exam in
                ExamArrangementCard(exam: exam) {
                    if isCustomCampus {
                        editingExam = ExamEditorItem(exam: exam)
                    }
                }
            }
        }
        .navigationTitle("考试安排")
        .leafyInlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .leafyTrailing) {
                if isCustomCampus {
                    Menu {
                        Button {
                            editingExam = ExamEditorItem()
                        } label: {
                            Label("添加考试", systemImage: "plus")
                        }

                        Button {
                            isExamImportPresented = true
                        } label: {
                            Label("导入 CSV", systemImage: "tray.and.arrow.down")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("添加考试")
                } else {
                    Button {
                        Task { await loadExams(userInitiated: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("刷新")
                }
            }
        }
        .sheet(item: $editingExam) { item in
            ExamEditorSheet(item: item) { exam in
                upsertExam(exam)
            } onDelete: { exam in
                deleteExam(exam)
            }
            .presentationDetents([.medium, .large])
        }
        .fileImporter(
            isPresented: $isExamImportPresented,
            allowedContentTypes: [.commaSeparatedText, .plainText, .text]
        ) { result in
            handleExamImport(result)
        }
        .task {
            exams = SchoolDataCache.loadExamSchedule()
            if !isCustomCampus {
                await loadExams(userInitiated: false)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .schoolDataDidRefresh)) { notification in
            let event = notification.object as? SchoolDataRefreshEvent
            guard event?.contains(.exams) == true else { return }
            exams = SchoolDataCache.loadExamSchedule()
                .sorted { ($0.startsAt ?? .distantFuture) < ($1.startsAt ?? .distantFuture) }
            errorMessage = nil
        }
        .schoolReauthenticationSheet(
            request: $reauthenticationRequest,
            networkManager: networkManager
        ) { _ in
            Task { await loadExams(userInitiated: true) }
        }
        .leafyOperationAlert($operationAlert)
    }

    private func examStatusCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppSpacing.card)
            .leafyCardStyle()
    }

    private func loadExams(userInitiated: Bool) async {
        guard !isLoading else { return }
        if isCustomCampus {
            await MainActor.run {
                editingExam = ExamEditorItem()
            }
            return
        }
        if ReviewDemoMode.isEnabled {
            ReviewDemoDataSeeder.refreshSchoolCaches()
            await MainActor.run {
                exams = SchoolDataCache.loadExamSchedule()
                errorMessage = nil
            }
            return
        }

        guard networkManager.isLoggedIn else {
            await MainActor.run {
                if userInitiated, networkManager.hasCachedIdentity {
                    reauthenticationRequest = SchoolReauthenticationRequest(context: .examSchedule)
                } else if exams.isEmpty {
                    errorMessage = networkManager.hasCachedIdentity
                        ? "本地身份已识别，但刷新考试安排需要连接校园网并重新建立教务登录态。"
                        : "请先连接校园网登录教务系统。"
                }
            }
            return
        }

        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        defer { Task { @MainActor in isLoading = false } }

        do {
            let html = try await networkManager.fetchExamSchedule()
            let parsed = try HTMLParser.parseExams(html: html)
                .sorted { ($0.startsAt ?? .distantFuture) < ($1.startsAt ?? .distantFuture) }
            await MainActor.run {
                exams = parsed
                SchoolDataCache.saveExamSchedule(parsed)
            }
        } catch {
            await MainActor.run {
                if userInitiated, SchoolReauthentication.requiresReauthentication(error) {
                    reauthenticationRequest = SchoolReauthenticationRequest(context: .examSchedule)
                } else {
                    errorMessage = "加载考试安排失败：\(error.localizedDescription)"
                }
                if exams.isEmpty {
                    exams = SchoolDataCache.loadExamSchedule()
                }
            }
        }
    }

    @MainActor
    private func handleExamImport(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let count = try CustomCampusImportService.importExams(from: url, modelContext: modelContext)
            exams = SchoolDataCache.loadExamSchedule()
                .sorted { ($0.startsAt ?? .distantFuture) < ($1.startsAt ?? .distantFuture) }
            errorMessage = nil
            operationAlert = .success(L10n.text("已导入 %d 条考试安排。", count))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func upsertExam(_ exam: ExamArrangement) {
        var updated = exams.filter { $0.id != exam.id }
        updated.append(exam)
        exams = updated.sorted { ($0.startsAt ?? .distantFuture) < ($1.startsAt ?? .distantFuture) }
        SchoolDataCache.saveExamSchedule(exams)
        errorMessage = nil
        operationAlert = .success(L10n.text("考试安排已保存。"))
    }

    @MainActor
    private func deleteExam(_ exam: ExamArrangement) {
        exams.removeAll { $0.id == exam.id }
        SchoolDataCache.saveExamSchedule(exams)
        operationAlert = .success(L10n.text("考试安排已删除。"))
    }
}

private struct ExamArrangementCard: View {
    @Environment(\.leafyControlScale) private var leafyControlScale
    @Environment(\.leafyThemeColorPreference) private var themeColorPreference

    let exam: ExamArrangement
    let onEdit: () -> Void

    var body: some View {
        Button(action: onEdit) {
            VStack(alignment: .leading, spacing: 14 * leafyControlScale) {
                HStack(alignment: .top, spacing: AppSpacing.compact) {
                    VStack(alignment: .leading, spacing: 6 * leafyControlScale) {
                        Text(exam.name)
                            .leafyTitle3()
                            .foregroundStyle(AppTheme.primaryText)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(exam.courseID.isEmpty ? "未填写课程编号" : exam.courseID)
                            .leafySubheadline()
                            .foregroundStyle(AppTheme.secondaryText)
                    }

                    Spacer(minLength: AppSpacing.micro)

                    Text(exam.isStarted ? "已开始" : "待开始")
                        .font(.system(size: 13 * leafyControlScale, weight: .semibold))
                        .foregroundStyle(statusTint)
                        .padding(.horizontal, 12 * leafyControlScale)
                        .padding(.vertical, 7 * leafyControlScale)
                        .background(statusTint.opacity(0.12), in: Capsule())
                }

                VStack(alignment: .leading, spacing: 10 * leafyControlScale) {
                    Label("\(exam.date) \(exam.start)-\(exam.end)", systemImage: "calendar")
                    Label(exam.location.isEmpty ? "未填写地点" : exam.location, systemImage: "mappin.and.ellipse")
                        .foregroundStyle(AppTheme.secondaryText)
                }
                .leafyBody()
                .labelStyle(.titleAndIcon)
                .symbolRenderingMode(.hierarchical)
                .tint(AppTheme.accent(for: themeColorPreference))
            }
        }
        .padding(AppSpacing.card)
        .leafyCardStyle()
        .buttonStyle(.plain)
    }

    private var statusTint: Color {
        exam.isStarted ? AppTheme.secondaryText : AppTheme.accent(for: themeColorPreference)
    }
}

private struct ExamEditorItem: Identifiable, Hashable {
    let id = UUID()
    let exam: ExamArrangement?

    init(exam: ExamArrangement? = nil) {
        self.exam = exam
    }
}

private struct ExamEditorSheet: View {
    let item: ExamEditorItem
    let onSave: (ExamArrangement) -> Void
    let onDelete: (ExamArrangement) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var courseID: String
    @State private var date: Date
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var location: String

    init(
        item: ExamEditorItem,
        onSave: @escaping (ExamArrangement) -> Void,
        onDelete: @escaping (ExamArrangement) -> Void
    ) {
        self.item = item
        self.onSave = onSave
        self.onDelete = onDelete
        let exam = item.exam
        let fallbackStart = Date()
        let fallbackEnd = Calendar.current.date(byAdding: .hour, value: 2, to: fallbackStart) ?? fallbackStart
        _name = State(initialValue: exam?.name ?? "")
        _courseID = State(initialValue: exam?.courseID ?? "")
        _date = State(initialValue: exam?.startsAt ?? fallbackStart)
        _startTime = State(initialValue: exam?.startsAt ?? fallbackStart)
        _endTime = State(initialValue: exam?.endsAt ?? fallbackEnd)
        _location = State(initialValue: exam?.location ?? "")
    }

    private var isSaveDisabled: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("考试名称", text: $name)
                    TextField("课程编号（可选）", text: $courseID)
                    TextField("地点", text: $location)
                }

                Section("时间") {
                    DatePicker("日期", selection: $date, displayedComponents: .date)
                    DatePicker("开始", selection: $startTime, displayedComponents: .hourAndMinute)
                    DatePicker("结束", selection: $endTime, displayedComponents: .hourAndMinute)
                }

                if let exam = item.exam {
                    Section {
                        Button("删除考试", role: .destructive) {
                            onDelete(exam)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(item.exam == nil ? "添加考试" : "编辑考试")
            .leafyInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(isSaveDisabled)
                }
            }
        }
    }

    private func save() {
        let calendar = Calendar.current
        let startComponents = calendar.dateComponents([.hour, .minute], from: startTime)
        let endComponents = calendar.dateComponents([.hour, .minute], from: endTime)
        let startDate = calendar.date(
            bySettingHour: startComponents.hour ?? 0,
            minute: startComponents.minute ?? 0,
            second: 0,
            of: date
        ) ?? date
        let endDate = calendar.date(
            bySettingHour: endComponents.hour ?? 0,
            minute: endComponents.minute ?? 0,
            second: 0,
            of: date
        ) ?? startDate
        let normalizedEndDate = endDate > startDate
            ? endDate
            : (calendar.date(byAdding: .hour, value: 2, to: startDate) ?? startDate)

        let exam = ExamArrangement(
            id: item.exam?.id ?? Self.newExamID(),
            courseID: courseID.trimmingCharacters(in: .whitespacesAndNewlines),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            date: DateFormatters.queryDate.string(from: startDate),
            start: DateFormatters.timeOnly.string(from: startDate),
            end: DateFormatters.timeOnly.string(from: normalizedEndDate),
            location: location.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        onSave(exam)
        dismiss()
    }

    private static func newExamID() -> Int {
        Int(Date().timeIntervalSince1970 * 1000) % Int(Int32.max)
    }
}

struct TeachingPlanView: View {
    @Environment(\.leafyControlScale) private var leafyControlScale
    @State private var networkManager = ActiveCampusContext.networkManager
    @State private var sections: [TeachingPlanSection] = SchoolDataCache.loadTeachingPlan()
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var collapsedTerms: Set<String> = []
    @State private var reauthenticationRequest: SchoolReauthenticationRequest?

    private var isCustomCampus: Bool {
        ActiveCampusContext.identity?.isCustom == true
    }

    var body: some View {
        AcademicDetailScrollContainer(spacing: AppSpacing.compact) {
            if isLoading {
                planStatusCard {
                    HStack(spacing: 10 * leafyControlScale) {
                        ProgressView()
                        Text("正在拉取教学计划")
                            .leafySubheadline()
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8 * leafyControlScale)
                }
            }

            if let errorMessage {
                planStatusCard {
                    Text(errorMessage)
                        .leafyBody()
                        .foregroundStyle(.red)
                }
            }

            if sections.isEmpty && !isLoading {
                planStatusCard {
                    ContentUnavailableView(
                        "暂无教学计划",
                        systemImage: "list.clipboard",
                        description: Text(isCustomCampus ? "通用入口暂需手动维护，第一版暂无导入入口。" : "连接校园网后可从教务系统同步。")
                    )
                }
            }

            ForEach(sections) { section in
                planSection(for: section)
            }
        }
        .navigationTitle("教学计划")
        .leafyInlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .leafyTrailing) {
                if !isCustomCampus {
                    Button {
                        Task { await loadPlan(force: true, userInitiated: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }
            }
        }
        .task {
            sections = SchoolDataCache.loadTeachingPlan()
            await loadPlan(force: false, userInitiated: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: .schoolDataDidRefresh)) { notification in
            let event = notification.object as? SchoolDataRefreshEvent
            guard event?.contains(.teachingPlan) == true else { return }
            sections = SchoolDataCache.loadTeachingPlan()
            errorMessage = nil
        }
        .schoolReauthenticationSheet(
            request: $reauthenticationRequest,
            networkManager: networkManager
        ) { _ in
            Task { await loadPlan(force: true, userInitiated: true) }
        }
    }

    private func planStatusCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppSpacing.card)
            .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func planSection(for section: TeachingPlanSection) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            termHeader(for: section)
                .padding(.horizontal, AppSpacing.card)
                .padding(.vertical, 14 * leafyControlScale)

            if !collapsedTerms.contains(section.term) {
                ForEach(Array(section.courses.enumerated()), id: \.element.id) { index, course in
                    if index > 0 {
                        Divider()
                            .padding(.leading, AppSpacing.card)
                    }

                    courseRow(course)
                        .padding(.horizontal, AppSpacing.card)
                        .padding(.vertical, 12 * leafyControlScale)
                }
            }
        }
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func courseRow(_ course: TeachingPlanCourse) -> some View {
        VStack(alignment: .leading, spacing: 8 * leafyControlScale) {
            HStack(alignment: .top, spacing: 12 * leafyControlScale) {
                VStack(alignment: .leading, spacing: 4 * leafyControlScale) {
                    Text(course.name)
                        .leafyHeadline()
                    Text(course.unit)
                        .microCaption()
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(String(format: "%.1f 学分", course.credit))
                    .leafySubheadline()
                    .fontWeight(.semibold)
            }

            HStack(spacing: 8 * leafyControlScale) {
                PlanBadge(text: course.type.isEmpty ? "未分类" : course.type)
                if !course.duration.isEmpty {
                    PlanBadge(text: course.duration)
                }
                if !course.exam.isEmpty {
                    PlanBadge(text: course.exam)
                }
            }
        }
    }

    private func termHeader(for section: TeachingPlanSection) -> some View {
        HStack {
            Text(section.term)
                .leafySubheadline()
            Spacer()
            Text(String(format: "%.1f 学分", section.totalCredits))
                .microCaption()
            Image(systemName: collapsedTerms.contains(section.term) ? "chevron.down" : "chevron.up")
                .foregroundColor(.secondary)
                .font(.system(size: 10 * leafyControlScale, weight: .semibold))
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.snappy) {
                if collapsedTerms.contains(section.term) {
                    collapsedTerms.remove(section.term)
                } else {
                    collapsedTerms.insert(section.term)
                }
            }
        }
    }

    private func loadPlan(force: Bool, userInitiated: Bool) async {
        guard !isLoading else { return }

        let cachedSections = SchoolDataCache.loadTeachingPlan()
        if ReviewDemoMode.isEnabled {
            ReviewDemoDataSeeder.refreshSchoolCaches()
            await MainActor.run {
                sections = SchoolDataCache.loadTeachingPlan()
                errorMessage = nil
            }
            return
        }

        if isCustomCampus {
            await MainActor.run {
                sections = cachedSections
                errorMessage = nil
            }
            return
        }

        if !force, !cachedSections.isEmpty {
            await MainActor.run {
                sections = cachedSections
                errorMessage = nil
            }
            return
        }

        guard networkManager.isLoggedIn else {
            await MainActor.run {
                sections = cachedSections
                if userInitiated, networkManager.hasCachedIdentity {
                    reauthenticationRequest = SchoolReauthenticationRequest(context: .teachingPlan)
                } else if force || sections.isEmpty {
                    errorMessage = networkManager.hasCachedIdentity
                        ? "本地身份已识别，但同步教学计划需要连接校园网并重新建立教务登录态。"
                        : "请先连接校园网登录教务系统。"
                }
            }
            return
        }

        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        defer { Task { @MainActor in isLoading = false } }

        do {
            let html = try await networkManager.fetchTeachingPlan()
            let parsed = try HTMLParser.parseTeachingPlan(html: html)
            await MainActor.run {
                sections = parsed
                SchoolDataCache.saveTeachingPlan(parsed)
            }
        } catch {
            await MainActor.run {
                sections = SchoolDataCache.loadTeachingPlan()
                if userInitiated, SchoolReauthentication.requiresReauthentication(error) {
                    reauthenticationRequest = SchoolReauthenticationRequest(context: .teachingPlan)
                } else if sections.isEmpty || force {
                    errorMessage = "加载教学计划失败：\(error.localizedDescription)"
                }
            }
        }
    }
}

private struct GraduationProgressSummaryView: View {
    let progress: GraduationCreditProgress
    let creditSummary: GradeCreditSummary?

    init(progress: GraduationCreditProgress, creditSummary: GradeCreditSummary? = nil) {
        self.progress = progress
        self.creditSummary = creditSummary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("毕业进度", systemImage: "graduationcap.fill")
                    .leafyHeadline()
                    .foregroundStyle(AppTheme.primaryText)
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(progress.hasRequirements ? "\(creditFormat(progress.totalRemainingCredits)) 学分待修" : "待同步")
                        .microCaption()
                        .foregroundStyle(progress.hasRequirements && progress.totalRemainingCredits > 0 ? AppTheme.warning : AppTheme.secondaryText)
                    Text(creditSummary?.hasCreditTotals == true ? "官方所得学分" : "成绩估算")
                        .microCaption()
                        .foregroundStyle(AppTheme.tertiaryText)
                }
            }

            if progress.hasRequirements {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("总学分")
                            .foregroundStyle(AppTheme.secondaryText)
                        Spacer()
                        Text("\(creditFormat(progress.totalCompletedCredits)) / \(creditFormat(progress.totalRequiredCredits))")
                            .foregroundStyle(AppTheme.primaryText)
                    }
                    .leafySubheadline()

                    ProgressView(value: progress.totalCompletionRatio ?? 0)
                        .tint(AppTheme.accent)
                }

                ForEach(progress.categories) { category in
                    categoryRow(category)
                }

                if let creditSummary, !creditSummary.publicElectiveBuckets.isEmpty {
                    publicElectiveDistribution(summary: creditSummary)
                }
            } else {
                Text("还没有培养方案缓存。连接校园网同步培养方案后，会按公选课、专选课和类别拆分毕业要求。")
                    .leafyBody()
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .padding(.vertical, 4)
    }

    private func categoryRow(_ category: GraduationCreditCategoryProgress) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: categoryIcon(category))
                .foregroundStyle(categoryIconColor(category))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                Text(category.category)
                    .leafySubheadline()
                    .foregroundStyle(AppTheme.primaryText)
                Text(categorySubtitle(category))
                    .microCaption()
                    .foregroundStyle(AppTheme.secondaryText)
            }

            Spacer()

            Text("\(creditFormat(category.completedCredits)) / \(creditFormat(category.requiredCredits))")
                .microCaption()
                .foregroundStyle(AppTheme.secondaryText)
        }
    }

    private func publicElectiveDistribution(summary: GradeCreditSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("公选课类别")
                .leafySubheadline()
                .foregroundStyle(AppTheme.primaryText)

            ForEach(summary.publicElectiveBuckets) { bucket in
                HStack {
                    Text(bucket.name)
                        .microCaption()
                        .foregroundStyle(AppTheme.secondaryText)
                    Spacer()
                    Text(creditFormat(bucket.credits))
                        .microCaption()
                        .foregroundStyle(bucket.credits > 0 ? AppTheme.primaryText : AppTheme.secondaryText)
                }
            }
        }
        .padding(.top, 2)
    }

    private func creditFormat(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private func categorySubtitle(_ category: GraduationCreditCategoryProgress) -> String {
        if category.kind == .publicElective || category.kind == .professionalElective {
            return category.isSatisfied
                ? "已满足"
                : "还差 \(creditFormat(category.remainingCredits)) 学分，约 \(category.estimatedRemainingCourses ?? 1) 门"
        }

        return "官方要求 \(creditFormat(category.requiredCredits)) 学分"
    }

    private func categoryIcon(_ category: GraduationCreditCategoryProgress) -> String {
        if category.kind == .publicElective || category.kind == .professionalElective {
            return category.isSatisfied ? "checkmark.circle.fill" : "circle.dashed"
        }
        return "info.circle"
    }

    private func categoryIconColor(_ category: GraduationCreditCategoryProgress) -> Color {
        if category.kind == .publicElective || category.kind == .professionalElective {
            return category.isSatisfied ? AppTheme.accent : AppTheme.warning
        }
        return AppTheme.secondaryText
    }
}

struct TrainingProgramView: View {
    @Environment(\.leafyControlScale) private var leafyControlScale
    @Query(sort: \Grade.term, order: .reverse) private var grades: [Grade]

    @State private var networkManager = ActiveCampusContext.networkManager
    @State private var document: TrainingProgramDocument? = SchoolDataCache.loadTrainingProgram()
    @State private var requirements: [GraduationCreditRequirement] = SchoolDataCache.loadGraduationRequirements()
    @State private var creditSummary: GradeCreditSummary? = SchoolDataCache.loadGradeCreditSummary()
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var reauthenticationRequest: SchoolReauthenticationRequest?

    private var isCustomCampus: Bool {
        ActiveCampusContext.identity?.isCustom == true
    }

    private var progress: GraduationCreditProgress {
        GraduationCreditProgressCalculator.calculate(
            requirements: requirements,
            grades: grades,
            creditSummary: creditSummary
        )
    }

    private var graduationProgressFootnote: String {
        if creditSummary?.hasCreditTotals == true {
            return "总学分和公选课分类优先使用成绩页同步的教务官方所得学分；补考或重修记录仍按有效课程口径去重。其他类别先展示官方要求，不做无法核验的本地归类。"
        }

        return "总学分按成绩页有效通过课程估算；补考或重修通过后只计一门，未通过记录不计入毕业进度。公选课、专选课按成绩页课程分类估算，其他类别先展示官方要求。"
    }

    var body: some View {
        AcademicDetailScrollContainer {
            if isLoading {
                AcademicDetailCard {
                    HStack(spacing: 10 * leafyControlScale) {
                        ProgressView()
                        Text("正在拉取培养方案")
                            .leafySubheadline()
                    }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8 * leafyControlScale)
                }
            }

            if let errorMessage {
                AcademicDetailCard {
                    Text(errorMessage)
                        .leafyBody()
                        .foregroundStyle(.red)
                }
            }

            if let document {
                AcademicDetailCard {
                    programHeader(document)
                }
            }

            if !requirements.isEmpty {
                AcademicDetailCard {
                    GraduationProgressSummaryView(progress: progress, creditSummary: creditSummary)
                }
                AcademicDetailFooterText(text: graduationProgressFootnote)

                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    AcademicDetailSectionHeader(title: "毕业学分要求")
                    AcademicDetailCard {
                        VStack(spacing: 0) {
                            ForEach(Array(requirements.enumerated()), id: \.element.id) { index, requirement in
                                if index > 0 {
                                    AcademicDetailDivider()
                                }
                                requirementRow(requirement)
                            }
                        }
                    }
                }
            }

            if let document, !document.sections.isEmpty {
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    AcademicDetailSectionHeader(title: "培养方案正文")
                    AcademicDetailCard {
                        VStack(spacing: 0) {
                            ForEach(Array(document.sections.enumerated()), id: \.element.id) { index, section in
                                if index > 0 {
                                    AcademicDetailDivider()
                                }
                                sectionRow(section)
                            }
                        }
                    }
                }
            }

            if document == nil && requirements.isEmpty && !isLoading {
                AcademicDetailCard {
                    ContentUnavailableView(
                        "暂无培养方案",
                        systemImage: "graduationcap",
                        description: Text(isCustomCampus ? "通用入口暂需手动维护，第一版暂无培养方案导入入口。" : "连接校园网并保持教务登录态后，可从强智专业培养方案页面同步。")
                    )
                }
            }
        }
        .navigationTitle("培养方案")
        .leafyInlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .leafyTrailing) {
                if !isCustomCampus {
                    Button {
                        Task { await loadProgram(force: true, userInitiated: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }
            }
        }
        .task {
            document = SchoolDataCache.loadTrainingProgram()
            requirements = document?.creditRequirements ?? SchoolDataCache.loadGraduationRequirements()
            creditSummary = SchoolDataCache.loadGradeCreditSummary()
            await loadProgram(force: false, userInitiated: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: .schoolDataDidRefresh)) { notification in
            let event = notification.object as? SchoolDataRefreshEvent
            guard event?.contains(.trainingProgram) == true || event?.contains(.gradeSupplemental) == true else { return }
            document = SchoolDataCache.loadTrainingProgram()
            requirements = document?.creditRequirements ?? SchoolDataCache.loadGraduationRequirements()
            creditSummary = SchoolDataCache.loadGradeCreditSummary()
            errorMessage = nil
        }
        .schoolReauthenticationSheet(
            request: $reauthenticationRequest,
            networkManager: networkManager
        ) { _ in
            Task { await loadProgram(force: true, userInitiated: true) }
        }
    }

    private func programHeader(_ document: TrainingProgramDocument) -> some View {
        VStack(alignment: .leading, spacing: 12 * leafyControlScale) {
            Label("专业培养方案", systemImage: "graduationcap.fill")
                .microCaption()
                .foregroundStyle(AppTheme.accentEmphasis)

            Text(document.title)
                .leafyTitle3()
                .foregroundStyle(AppTheme.primaryText)

            HStack(spacing: 8 * leafyControlScale) {
                PlanBadge(text: "\(requirements.count) 类学分要求")
                PlanBadge(text: "\(document.sections.count) 个正文部分")
            }
        }
        .padding(.vertical, 5 * leafyControlScale)
    }

    private func requirementRow(_ requirement: GraduationCreditRequirement) -> some View {
        HStack(alignment: .top, spacing: 12 * leafyControlScale) {
            Image(systemName: requirementIcon(requirement))
                .font(.system(size: 18 * leafyControlScale, weight: .semibold))
                .foregroundStyle(requirementTint(requirement))
                .frame(width: 24 * leafyControlScale)

            VStack(alignment: .leading, spacing: 5 * leafyControlScale) {
                Text(requirementTitle(requirement))
                    .leafyHeadline()
                    .foregroundStyle(AppTheme.primaryText)

                Text(requirementSubtitle(requirement))
                    .microCaption()
                    .foregroundStyle(AppTheme.secondaryText)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2 * leafyControlScale) {
                Text("\(creditFormat(requirement.requiredCredits))")
                    .leafyTitle3()
                    .foregroundStyle(AppTheme.primaryText)
                Text("学分")
                    .microCaption()
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .padding(.vertical, 6 * leafyControlScale)
    }

    private func sectionRow(_ section: TrainingProgramSection) -> some View {
        VStack(alignment: .leading, spacing: 8 * leafyControlScale) {
            Text(section.title)
                .leafyHeadline()
                .foregroundStyle(AppTheme.primaryText)

            if section.body.isEmpty {
                Text("该部分主要为表格内容，已在学分要求中整理。")
                    .microCaption()
                    .foregroundStyle(AppTheme.secondaryText)
            } else {
                Text(section.body)
                    .leafyBody()
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .padding(.vertical, 6 * leafyControlScale)
    }

    private func loadProgram(force: Bool, userInitiated: Bool) async {
        guard !isLoading else { return }

        let cachedDocument = SchoolDataCache.loadTrainingProgram()
        let cachedRequirements = cachedDocument?.creditRequirements ?? SchoolDataCache.loadGraduationRequirements()
        if ReviewDemoMode.isEnabled {
            ReviewDemoDataSeeder.refreshSchoolCaches()
            await MainActor.run {
                document = SchoolDataCache.loadTrainingProgram()
                requirements = document?.creditRequirements ?? SchoolDataCache.loadGraduationRequirements()
                creditSummary = SchoolDataCache.loadGradeCreditSummary()
                errorMessage = nil
            }
            return
        }

        if isCustomCampus {
            await MainActor.run {
                document = cachedDocument
                requirements = cachedRequirements
                errorMessage = nil
            }
            return
        }

        if !force, (cachedDocument != nil || !cachedRequirements.isEmpty) {
            await MainActor.run {
                document = cachedDocument
                requirements = cachedRequirements
                errorMessage = nil
            }
            return
        }

        guard networkManager.isLoggedIn else {
            await MainActor.run {
                document = cachedDocument
                requirements = cachedRequirements
                if userInitiated, networkManager.hasCachedIdentity {
                    reauthenticationRequest = SchoolReauthenticationRequest(context: .trainingProgram)
                } else if force || (document == nil && requirements.isEmpty) {
                    errorMessage = networkManager.hasCachedIdentity
                        ? "本地身份已识别，但同步培养方案需要连接校园网并重新建立教务登录态。"
                        : "请先连接校园网登录教务系统。"
                }
            }
            return
        }

        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        defer { Task { @MainActor in isLoading = false } }

        do {
            let html = try await networkManager.fetchGraduationRequirements()
            let parsed = try HTMLParser.parseTrainingProgram(html: html)
            await MainActor.run {
                document = parsed
                requirements = parsed.creditRequirements
                SchoolDataCache.saveTrainingProgram(parsed)
            }
        } catch {
            await MainActor.run {
                let fallbackDocument = SchoolDataCache.loadTrainingProgram()
                document = fallbackDocument
                requirements = fallbackDocument?.creditRequirements ?? SchoolDataCache.loadGraduationRequirements()
                if userInitiated, SchoolReauthentication.requiresReauthentication(error) {
                    reauthenticationRequest = SchoolReauthenticationRequest(context: .trainingProgram)
                } else if (document == nil && requirements.isEmpty) || force {
                    errorMessage = "加载培养方案失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func requirementTitle(_ requirement: GraduationCreditRequirement) -> String {
        if requirement.kind == .total {
            return "毕业总学分"
        }
        return requirement.displayCategory
    }

    private func requirementSubtitle(_ requirement: GraduationCreditRequirement) -> String {
        switch requirement.kind {
        case .total:
            return "已通过 \(creditFormat(progress.totalCompletedCredits)) / 要求 \(creditFormat(progress.totalRequiredCredits)) 学分"
        case .publicElective, .professionalElective:
            guard let categoryProgress = progress.categories.first(where: { $0.kind == requirement.kind }) else {
                return "\(requirement.category) · 官方要求"
            }
            if categoryProgress.isSatisfied {
                return "\(requirement.category) · 已满足"
            }
            return "\(requirement.category) · 还差 \(creditFormat(categoryProgress.remainingCredits)) 学分，约 \(categoryProgress.estimatedRemainingCourses ?? 1) 门"
        case .other:
            return "\(requirement.category) · 官方分类要求"
        }
    }

    private func requirementIcon(_ requirement: GraduationCreditRequirement) -> String {
        switch requirement.kind {
        case .total:
            return "sum"
        case .publicElective:
            return "sparkles"
        case .professionalElective:
            return "book.closed.fill"
        case .other:
            return "square.grid.2x2"
        }
    }

    private func requirementTint(_ requirement: GraduationCreditRequirement) -> Color {
        switch requirement.kind {
        case .total:
            return AppTheme.accent
        case .publicElective, .professionalElective:
            return AppTheme.warning
        case .other:
            return AppTheme.secondaryText
        }
    }

    private func creditFormat(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}

struct EmptyClassroomView: View {
    enum QueryMode: String, CaseIterable, Identifiable {
        case byRoom = "按教室查询"
        case byPeriod = "按节次查询"

        var id: String { rawValue }
    }

    @Environment(\.leafyLanguage) private var leafyLanguage
    @Environment(\.leafyDependencies) private var dependencies
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FavoriteClassroom.createdAt, order: .reverse) private var favoriteClassrooms: [FavoriteClassroom]

    @State private var networkManager = ActiveCampusContext.networkManager
    @State private var mode: QueryMode = .byRoom
    @State private var selectedDate = Date()
    @State private var startPeriod = min(max(TimetablePeriodSchedule.defaultStudyPeriod(), 1), 12)
    @State private var endPeriod = min(max(TimetablePeriodSchedule.defaultStudyPeriod(), 1), 12)
    @State private var buildingOptionID = ClassroomLookupCatalog.defaultBuildingOption.id
    @State private var selectedRoomID = ClassroomLookupCatalog.defaultBuildingOption.rooms.first?.id ?? ""
    @State private var rooms: [EmptyClassroom] = []
    @State private var usage: [ClassroomUsageSlot] = []
    @State private var expandedBuildingIDs: Set<String> = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var didAutoSubmit = false
    @State private var operationAlert: LeafyOperationAlert?
    @State private var reauthenticationRequest: SchoolReauthenticationRequest?

    private let autoSubmitInitialQuery: Bool
    private var safeStartPeriod: Int { min(max(startPeriod, 1), 12) }
    private var safeEndPeriodRange: ClosedRange<Int> { safeStartPeriod...12 }
    private var isCustomCampus: Bool { ActiveCampusContext.identity?.isCustom == true }

    init(
        initialMode: QueryMode = .byRoom,
        initialBuilding: String? = nil,
        initialRoom: String? = nil,
        autoSubmit: Bool = false
    ) {
        let resolvedBuildingOption = ClassroomLookupCatalog.option(containing: initialBuilding)
        let resolvedRoomOption = ClassroomLookupCatalog.roomOption(
            preferredBuilding: initialBuilding,
            preferredRoom: initialRoom,
            in: resolvedBuildingOption
        )
        _mode = State(initialValue: initialMode)
        _buildingOptionID = State(initialValue: resolvedBuildingOption.id)
        _selectedRoomID = State(initialValue: resolvedRoomOption.id)
        autoSubmitInitialQuery = autoSubmit
    }

    var body: some View {
        AcademicDetailScrollContainer {
            AcademicDetailCard {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: isCustomCampus ? "building.2" : "wifi")
                        .foregroundStyle(AppTheme.accentEmphasis)
                        .frame(width: 22, height: 22)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(isCustomCampus ? "暂无导入入口" : "需连接校园网")
                            .fontWeight(.semibold)
                            .foregroundStyle(AppTheme.primaryText)
                        Text(isCustomCampus ? "通用入口暂需手动维护，第一版不接学校空教室网络查询。" : "空教室查询来自学校教务系统，请连接校园网并保持教务登录态后再查询。")
                            .microCaption()
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }
                .padding(.vertical, 2)
            }

            AcademicDetailCard {
                if isCustomCampus {
                    ContentUnavailableView(
                        "暂无空教室数据",
                        systemImage: "building.2.crop.circle",
                        description: Text("通用入口暂需手动维护，第一版暂无导入入口。")
                    )
                } else {
                    VStack(alignment: .leading, spacing: AppSpacing.compact) {
                        Picker("查询方式", selection: $mode) {
                            ForEach(QueryMode.allCases) { item in
                                Text(item.rawValue).tag(item)
                            }
                        }
                        .pickerStyle(.segmented)

                        DatePicker("日期", selection: $selectedDate, displayedComponents: .date)

                        if mode == .byPeriod {
                            Picker("开始节次", selection: $startPeriod) {
                                ForEach(1...12, id: \.self) { period in
                                    Text(periodDisplayText(period)).tag(period)
                                }
                            }

                            Picker("结束节次", selection: $endPeriod) {
                                ForEach(safeEndPeriodRange, id: \.self) { period in
                                    Text(periodDisplayText(period)).tag(period)
                                }
                            }
                        } else {
                            Picker("教学楼", selection: building) {
                                ForEach(ClassroomLookupCatalog.buildingOptions) { item in
                                    Text(item.title).tag(item.id)
                                }
                            }
                            .onChange(of: buildingOptionID) { _, newValue in
                                selectedRoomID = ClassroomLookupCatalog.roomOption(
                                    preferredBuilding: nil,
                                    preferredRoom: nil,
                                    in: buildingOption(for: newValue)
                                ).id
                            }

                            Picker("教室", selection: room) {
                                ForEach(currentRoomOptions) { item in
                                    Text(item.title).tag(item.id)
                                }
                            }
                        }

                        Button {
                            Task { await submitQuery(userInitiated: true) }
                        } label: {
                            HStack {
                                Spacer()
                                if isLoading {
                                    ProgressView()
                                } else {
                                    Text("开始查询")
                                        .fontWeight(.semibold)
                                }
                                Spacer()
                            }
                        }
                        .disabled(isLoading)
                    }
                }
            }

            if !isCustomCampus, !visibleFavoriteClassrooms.isEmpty {
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    AcademicDetailSectionHeader(title: "常用教室")
                    AcademicDetailCard {
                        VStack(spacing: 0) {
                            ForEach(Array(visibleFavoriteClassrooms.enumerated()), id: \.element.id) { index, favorite in
                                if index > 0 {
                                    AcademicDetailDivider()
                                }
                                favoriteClassroomRow(favorite)
                            }
                        }
                    }
                }
            }

            if !isCustomCampus, let errorMessage {
                AcademicDetailCard {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }

            if !isCustomCampus, mode == .byPeriod {
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    AcademicDetailSectionHeader(title: "空闲教室")
                    if rooms.isEmpty && !isLoading {
                        AcademicDetailCard {
                            Text("当前条件下没有可用教室")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: AppSpacing.compact) {
                            ForEach(emptyClassroomGroups) { group in
                                emptyClassroomGroupCard(group)
                            }
                        }
                    }
                }
            } else if !isCustomCampus {
                AcademicDetailCard {
                    Button {
                        toggleFavorite(building: selectedRoom.building, room: selectedRoom.room)
                    } label: {
                        Label(
                            isFavorite(building: selectedRoom.building, room: selectedRoom.room)
                                ? "取消收藏 \(selectedRoomDisplayName)"
                                : "收藏 \(selectedRoomDisplayName)",
                            systemImage: isFavorite(building: selectedRoom.building, room: selectedRoom.room) ? "star.fill" : "star"
                        )
                    }
                }

                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    AcademicDetailSectionHeader(title: "占用情况")
                    AcademicDetailCard {
                        if usage.isEmpty && !isLoading {
                            Text("请先查询教室占用情况")
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 0) {
                                if hasUnknownUsageSlots {
                                    Text("部分节次教务返回无法确认，请以教务原页或现场为准。")
                                        .microCaption()
                                        .foregroundStyle(AppTheme.secondaryText)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.bottom, 8)
                                }
                                ForEach(Array(usage.enumerated()), id: \.element.id) { index, slot in
                                    if index > 0 {
                                        AcademicDetailDivider()
                                    }
                                    classroomUsageRow(slot)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("空闲教室")
        .leafyInlineNavigationTitle()
        .task {
            normalizePeriods()
            guard !isCustomCampus else { return }
            guard autoSubmitInitialQuery, !didAutoSubmit else { return }
            didAutoSubmit = true
            await submitQuery(userInitiated: true)
        }
        .onChange(of: startPeriod) { _, newValue in
            normalizePeriods(startingAt: newValue)
        }
        .schoolReauthenticationSheet(
            request: $reauthenticationRequest,
            networkManager: networkManager
        ) { _ in
            Task { await submitQuery(userInitiated: true) }
        }
        .leafyOperationAlert($operationAlert)
    }

    private func submitQuery(userInitiated: Bool) async {
        guard !isLoading else { return }
        guard !isCustomCampus else {
            errorMessage = nil
            return
        }
        await MainActor.run {
            isLoading = true
            errorMessage = nil
            rooms = []
            usage = []
        }
        defer { Task { @MainActor in isLoading = false } }

        let outcome = await dependencies.classroomLookupService.lookup(
            classroomLookupRequest,
            userInitiated: userInitiated
        )

        await MainActor.run {
            rooms = ClassroomLookupCatalog.filteredRooms(outcome.data.rooms)
            usage = outcome.data.usage
            expandedBuildingIDs = []
            errorMessage = outcome.errorMessage
            if outcome.requiresReauthentication {
                reauthenticationRequest = SchoolReauthenticationRequest(context: .emptyClassrooms)
            }
        }
    }

    private var classroomLookupRequest: ClassroomLookupRequest {
        switch mode {
        case .byPeriod:
            return ClassroomLookupRequest(date: selectedDate, startPeriod: startPeriod, endPeriod: endPeriod)
        case .byRoom:
            return ClassroomLookupRequest(date: selectedDate, building: selectedRoom.building, room: selectedRoom.room)
        }
    }

    private func isFavorite(building: String, room: String) -> Bool {
        favoriteClassrooms.contains { $0.building == building && $0.room == room }
    }

    private var emptyClassroomGroups: [EmptyClassroomBuildingGroup] {
        EmptyClassroomBuildingGroup.groups(from: rooms, displayBuilding: displayBuilding(for:))
    }

    private var visibleFavoriteClassrooms: [FavoriteClassroom] {
        favoriteClassrooms.filter { ClassroomLookupCatalog.contains(building: $0.building) }
    }

    private var hasUnknownUsageSlots: Bool {
        usage.contains { $0.status == .unknown }
    }

    private var building: Binding<String> {
        Binding(
            get: { buildingOptionID },
            set: { buildingOptionID = $0 }
        )
    }

    private var room: Binding<String> {
        Binding(
            get: { selectedRoomID },
            set: { selectedRoomID = $0 }
        )
    }

    private var selectedBuildingOption: ClassroomLookupBuildingOption {
        buildingOption(for: buildingOptionID)
    }

    private var currentRoomOptions: [ClassroomLookupRoomOption] {
        selectedBuildingOption.rooms
    }

    private var selectedRoom: ClassroomLookupRoomOption {
        currentRoomOptions.first { $0.id == selectedRoomID }
            ?? ClassroomLookupCatalog.roomOption(preferredBuilding: nil, preferredRoom: nil, in: selectedBuildingOption)
    }

    private var selectedRoomDisplayName: String {
        "\(displayBuilding(for: selectedRoom.building)) \(selectedRoom.room)"
    }

    private func buildingOption(for id: String) -> ClassroomLookupBuildingOption {
        ClassroomLookupCatalog.buildingOptions.first { $0.id == id } ?? ClassroomLookupCatalog.defaultBuildingOption
    }

    private func displayBuilding(for building: String) -> String {
        ClassroomLookupCatalog.displayBuilding(for: building)
    }

    private func normalizePeriods(startingAt proposedStart: Int? = nil) {
        let normalizedStart = min(max(proposedStart ?? startPeriod, 1), 12)
        if startPeriod != normalizedStart {
            startPeriod = normalizedStart
        }
        endPeriod = min(max(endPeriod, normalizedStart), 12)
    }

    private func favoriteClassroomRow(_ favorite: FavoriteClassroom) -> some View {
        HStack {
            Button {
                let option = ClassroomLookupCatalog.option(containing: favorite.building)
                let roomOption = ClassroomLookupCatalog.roomOption(
                    preferredBuilding: favorite.building,
                    preferredRoom: favorite.room,
                    in: option
                )
                buildingOptionID = option.id
                selectedRoomID = roomOption.id
                mode = .byRoom
            } label: {
                Label("\(displayBuilding(for: favorite.building)) \(favorite.room)", systemImage: "star.fill")
                    .foregroundStyle(AppTheme.primaryText)
            }
            .buttonStyle(.plain)

            Spacer()

            Button(role: .destructive) {
                removeFavorite(favorite)
            } label: {
                Image(systemName: "star.slash")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.danger)
                    .frame(width: 34, height: 34)
                    .background(AppTheme.danger.opacity(0.1), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("取消收藏")
        }
        .padding(.vertical, 6)
    }

    private func emptyClassroomGroupCard(_ group: EmptyClassroomBuildingGroup) -> some View {
        DisclosureGroup(isExpanded: binding(for: group.id)) {
            VStack(spacing: 0) {
                ForEach(Array(group.rooms.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        AcademicDetailDivider()
                    }
                    emptyClassroomRow(item)
                }
            }
            .padding(.top, AppSpacing.compact)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.building)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(AppTheme.primaryText)
                    Text(group.countText)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Spacer()
            }
        }
        .tint(AppTheme.accentEmphasis)
        .padding(AppSpacing.card)
        .leafyCardStyle()
    }

    private func binding(for buildingID: String) -> Binding<Bool> {
        Binding(
            get: { expandedBuildingIDs.contains(buildingID) },
            set: { isExpanded in
                if isExpanded {
                    expandedBuildingIDs.insert(buildingID)
                } else {
                    expandedBuildingIDs.remove(buildingID)
                }
            }
        )
    }

    private func emptyClassroomRow(_ item: EmptyClassroom) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.room)
                    .font(.system(size: 23, weight: .bold))
                    .foregroundStyle(AppTheme.primaryText)
                Text(displayBuilding(for: item.building))
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                toggleFavorite(building: item.building, room: item.room)
            } label: {
                Image(systemName: isFavorite(building: item.building, room: item.room) ? "star.fill" : "star")
                    .foregroundStyle(AppTheme.accentEmphasis)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
    }

    private func classroomUsageRow(_ slot: ClassroomUsageSlot) -> some View {
        HStack {
            Text(periodDisplayText(slot.period))
            Spacer()
            Text(usageStatusText(slot.status))
                .fontWeight(.semibold)
                .foregroundStyle(usageStatusColor(slot.status))
        }
        .padding(.vertical, 6)
    }

    private func usageStatusText(_ status: ClassroomUsageStatus) -> String {
        switch status {
        case .available:
            return "空闲"
        case .occupied:
            return "占用"
        case .unknown:
            return "待确认"
        }
    }

    private func usageStatusColor(_ status: ClassroomUsageStatus) -> Color {
        switch status {
        case .available:
            return AppTheme.accent
        case .occupied:
            return AppTheme.warning
        case .unknown:
            return AppTheme.secondaryText
        }
    }

    private func periodDisplayText(_ period: Int) -> String {
        guard let slot = TimetablePeriodSchedule.slot(for: period) else {
            return "第 \(period) 节"
        }
        return "第 \(period) 节 \(slot.startText)-\(slot.endText)"
    }

    private func removeFavorite(_ favorite: FavoriteClassroom) {
        modelContext.delete(favorite)
        try? modelContext.save()
        operationAlert = .success(L10n.text("已取消收藏！", language: leafyLanguage))
    }

    private func toggleFavorite(building: String, room: String) {
        if let existing = favoriteClassrooms.first(where: { $0.building == building && $0.room == room }) {
            modelContext.delete(existing)
            operationAlert = .success(L10n.text("已取消收藏！", language: leafyLanguage))
        } else {
            modelContext.insert(FavoriteClassroom(building: building, room: room))
            operationAlert = .success(L10n.text("已添加收藏！", language: leafyLanguage))
        }
        try? modelContext.save()
    }

}
