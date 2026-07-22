import Combine
import QuickLook
import Supabase
import SwiftUI
import os
import SwiftData
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

private enum RatingSectionMode: String, CaseIterable, Identifiable {
    case teachers = "老师"
    case courses = "课程"
    case dishes = "菜品"

    var id: String { rawValue }
}

struct RatingSectionContainerView: View {
    @ObservedObject private var sessionManager = CommunitySessionManager.shared
    @Binding var selectedTeacher: TeacherRatingSummary?
    @Binding var selectedCourse: CourseRatingSummary?
    @Binding var selectedDish: DishRatingSummary?
    let teacherRefreshID: UUID
    let courseRefreshID: UUID
    let dishRefreshID: UUID

    @State private var mode: RatingSectionMode = .teachers
    @State private var workspace = RatingCatalogWorkspace()

    private var shouldShowRatingSections: Bool {
        if ActiveCampusContext.descriptor.id == .bjfu && ActiveCampusContext.identity?.isCustom != true {
            return true
        }
        return sessionManager.hasApprovedCommunityAccess
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.card) {
            if shouldShowRatingSections {
                Picker("评教评课评菜", selection: $mode) {
                    ForEach(RatingSectionMode.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)

                ZStack(alignment: .topLeading) {
                    TeacherSectionView(
                        selectedTeacher: $selectedTeacher,
                        refreshID: teacherRefreshID,
                        isActive: mode == .teachers,
                        lifecycleStore: workspace.teachers
                    )
                    .opacity(mode == .teachers ? 1 : 0)
                    .allowsHitTesting(mode == .teachers)
                    .accessibilityHidden(mode != .teachers)

                    CourseSectionView(
                        selectedCourse: $selectedCourse,
                        refreshID: courseRefreshID,
                        isActive: mode == .courses,
                        lifecycleStore: workspace.courses
                    )
                    .opacity(mode == .courses ? 1 : 0)
                    .allowsHitTesting(mode == .courses)
                    .accessibilityHidden(mode != .courses)

                    DishSectionView(
                        selectedDish: $selectedDish,
                        refreshID: dishRefreshID,
                        isActive: mode == .dishes,
                        lifecycleStore: workspace.dishes
                    )
                    .opacity(mode == .dishes ? 1 : 0)
                    .allowsHitTesting(mode == .dishes)
                    .accessibilityHidden(mode != .dishes)
                }
                .animation(.easeInOut(duration: 0.18), value: mode)
            } else {
                RatingCommunityAccessStatusCard(
                    status: sessionManager.communityAccessStatus,
                    profile: sessionManager.profile
                )
            }
        }
        .task {
            CommunitySessionManager.shared.startBootstrapIfNeeded()
            await CommunitySessionManager.shared.restoreProfileIfPossible()
        }
    }
}

private struct RatingCommunityAccessStatusCard: View {
    let status: CommunityAccessStatus
    let profile: CommunityProfile?

    private var title: String {
        switch status {
        case .pending:
            return "学校申请正在审核中"
        case .rejected:
            return "学校申请未通过"
        case .approved:
            return "正在进入学校社区"
        case .general:
            return "当前为通用模式"
        }
    }

    private var detail: String {
        switch status {
        case .pending:
            let school = profile?.communitySchoolName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return school.isEmpty
                ? "审核通过后会开放对应学校的评教、评课和评菜。"
                : "\(school) 的申请审核通过后，会开放对应学校的评教、评课和评菜。"
        case .rejected:
            return "您申请的学校不通过，您现在是处于通用的模式下，社区功能暂不开放。"
        case .approved:
            return "评教、评课和评菜会按学校社区分别展示。"
        case .general:
            return "评教、评课和评菜属于学校社区能力，请先在社区页提交学校申请。"
        }
    }

    var body: some View {
        AcademicDetailCard {
            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                ContentUnavailableView(
                    title,
                    systemImage: "star.bubble",
                    description: Text(detail)
                )

                if status == .rejected,
                   let reason = profile?.communityRejectionReason?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !reason.isEmpty {
                    Text(reason)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

nonisolated private struct CampusDiningLocation: Identifiable, Hashable, Sendable {
    let canteen: String
    let floor: String
    let name: String

    var id: String { fullName }
    var fullName: String { "\(canteen) · \(floor) · \(name)" }
    var displayName: String { "\(floor) · \(name)" }

    static let east = "东区食堂"
    static let west = "西区食堂"
    static let canteens = [east, west]

    static let all: [CampusDiningLocation] = [
        CampusDiningLocation(canteen: east, floor: "一层", name: "学一食堂"),
        CampusDiningLocation(canteen: east, floor: "一层", name: "学三食堂"),
        CampusDiningLocation(canteen: east, floor: "一层", name: "烘焙坊"),
        CampusDiningLocation(canteen: east, floor: "二层", name: "教工餐厅"),
        CampusDiningLocation(canteen: east, floor: "二层", name: "学四食堂"),
        CampusDiningLocation(canteen: east, floor: "三层", name: "楸木园餐厅"),
        CampusDiningLocation(canteen: east, floor: "三层", name: "林园餐厅"),
        CampusDiningLocation(canteen: west, floor: "B1层", name: "小食光餐厅"),
        CampusDiningLocation(canteen: west, floor: "一层", name: "学二食堂"),
        CampusDiningLocation(canteen: west, floor: "二层", name: "齐芳阁餐厅"),
        CampusDiningLocation(canteen: west, floor: "三层", name: "林汇园餐厅")
    ]

    static func locations(for canteen: String) -> [CampusDiningLocation] {
        all.filter { $0.canteen == canteen }
    }

    static func location(for fullName: String) -> CampusDiningLocation? {
        all.first { $0.fullName == fullName }
    }

    static func displayName(for fullName: String) -> String? {
        location(for: fullName)?.displayName
    }
}

private struct CommunitySectionView: View {
    @Binding var selectedPost: CommunityMockPost?

    private let posts = CommunityMockPost.samples

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.card) {
            LeafySectionTitle("社区", subtitle: "当前阶段使用 Mock 数据，验证信息架构、帖子流与详情交互。")

            ForEach(posts) { post in
                Button {
                    selectedPost = post
                } label: {
                    CommunityPostCard(post: post)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct TeacherSectionView: View {
    @Environment(\.leafyDependencies) private var dependencies

    @Binding var selectedTeacher: TeacherRatingSummary?
    let refreshID: UUID
    let isActive: Bool
    let lifecycleStore: RatingCatalogSectionStore

    private let pageSize = 50

    @State private var search = ""
    @State private var selectedUnit: String?
    @State private var selectedStars: Int?
    @State private var isFilterExpanded = false
    @State private var teachers: [TeacherRatingSummary] = []
    @State private var filteredTeachers: [TeacherRatingSummary] = []
    @State private var availableUnits: [String] = []
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var canLoadMore = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?
    @State private var suggestionSheet: CatalogSuggestionSheetContext?

    private var hasActiveFilters: Bool {
        selectedUnit != nil || selectedStars != nil || !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Group {
            if isActive {
                VStack(alignment: .leading, spacing: AppSpacing.card) {
                    HStack(alignment: .top, spacing: 12) {
                        LeafySectionTitle("评教", subtitle: "按老师打星评分，结果只统计星级。")
                        Spacer(minLength: 8)
                        CatalogSuggestionPromptButton(title: "缺老师", systemName: "person.badge.plus") {
                            openTeacherSuggestion()
                        }
                    }

                    TeacherFilterToolbar(
                        search: $search,
                        selectedUnit: $selectedUnit,
                        selectedStars: $selectedStars,
                        isExpanded: $isFilterExpanded,
                        availableUnits: availableUnits,
                        hasActiveFilters: hasActiveFilters,
                        clearFilters: clearFilters
                    )

                    teacherContent
                }
            } else {
                Color.clear.frame(height: 0)
            }
        }
        .task(id: isActive) {
            guard isActive, lifecycleStore.beginInitialLoad() else { return }
            await loadTeachers(reset: true)
        }
        .onChange(of: search) { _, _ in
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                await loadTeachers(reset: true)
            }
        }
        .onChange(of: refreshID) { _, _ in
            scheduleTeacherLoad(reset: true)
        }
        .onChange(of: selectedUnit) { _, _ in
            updateDerivedTeacherState()
        }
        .onChange(of: selectedStars) { _, _ in
            updateDerivedTeacherState()
        }
        .onDisappear {
            searchTask?.cancel()
        }
        .sheet(item: $suggestionSheet) { context in
            CatalogSuggestionSheet(context: context)
                .presentationDetents([.medium, .large])
        }
    }

    @ViewBuilder
    private var teacherContent: some View {
        if isLoading && teachers.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
        } else if let errorMessage, teachers.isEmpty {
            TeacherSectionMessageCard(
                title: "评教加载失败",
                message: errorMessage,
                actionTitle: "重试",
                action: { scheduleTeacherLoad(reset: true) }
            )
        } else if teachers.isEmpty {
            TeacherSectionMessageCard(
                title: emptyTeacherTitle,
                message: emptyTeacherMessage,
                actionTitle: "提交缺失老师",
                action: openTeacherSuggestion
            )
        } else if filteredTeachers.isEmpty {
            if hasActiveFilters {
                TeacherSectionMessageCard(
                    title: "没有匹配的老师",
                    message: "换一个学院、星级或关键词再试。",
                    actionTitle: "提交缺失老师",
                    action: openTeacherSuggestion
                )
            } else {
                TeacherSectionMessageCard(
                    title: "没有匹配的老师",
                    message: "换一个学院、星级或关键词再试。",
                    actionTitle: "提交缺失老师",
                    action: openTeacherSuggestion
                )
            }
        } else {
            if let errorMessage {
                Text(errorMessage)
                    .leafyBody()
                    .foregroundStyle(AppTheme.danger)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
            }

            ForEach(filteredTeachers) { summary in
                Button {
                    selectedTeacher = summary
                } label: {
                    TeacherCard(summary: summary)
                }
                .buttonStyle(.plain)
            }

            if canLoadMore {
                RatingLoadMoreButton(isLoading: isLoadingMore) {
                    scheduleTeacherLoad(reset: false)
                }
            }
        }
    }

    private var emptyTeacherTitle: String {
        search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "还没有教师名录" : "没有找到老师"
    }

    private var emptyTeacherMessage: String {
        search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "先在 Supabase 的 teachers 表导入 name,unit CSV，导入后这里会显示真实老师列表。"
            : "换一个姓名或学院关键词再试。"
    }

    @MainActor
    private func loadTeachers(reset: Bool) async {
        let signpostState = LeafyPerformanceSignposter.ratings.beginInterval("teachers-load")
        defer { LeafyPerformanceSignposter.ratings.endInterval("teachers-load", signpostState) }

        if reset {
            isLoading = true
        } else {
            guard !isLoadingMore, canLoadMore else { return }
            isLoadingMore = true
        }
        defer {
            if reset {
                isLoading = false
            } else {
                isLoadingMore = false
            }
        }

        if ReviewDemoMode.isEnabled {
            let demoTeachers = ReviewDemoDataSeeder.teacherSummaries(search: search)
            teachers = reset ? demoTeachers : teachers
            canLoadMore = false
            errorMessage = nil
            updateDerivedTeacherState()
            return
        }

        do {
            try await dependencies.communityRepository.ensureAnonymousSession()
            let fetchedTeachers = try await dependencies.communityRepository.fetchTeacherRatingSummaries(
                search: search,
                limit: pageSize,
                offset: reset ? 0 : teachers.count
            )
            if reset {
                teachers = fetchedTeachers
            } else {
                let existingIDs = Set(teachers.map(\.id))
                teachers.append(contentsOf: fetchedTeachers.filter { !existingIDs.contains($0.id) })
            }
            canLoadMore = fetchedTeachers.count == pageSize
            errorMessage = nil
        } catch {
            if reset {
                teachers = []
                canLoadMore = false
            }
            errorMessage = error.localizedDescription
        }
        updateDerivedTeacherState()
    }

    private func clearFilters() {
        searchTask?.cancel()
        search = ""
        selectedUnit = nil
        selectedStars = nil
        scheduleTeacherLoad(reset: true)
    }

    private func openTeacherSuggestion() {
        suggestionSheet = CatalogSuggestionSheetContext(
            type: .teacher,
            initialName: search.trimmingCharacters(in: .whitespacesAndNewlines),
            initialCategory: nil,
            initialLocation: nil
        )
    }

    private func scheduleTeacherLoad(reset: Bool) {
        searchTask?.cancel()
        searchTask = Task {
            await loadTeachers(reset: reset)
        }
    }

    private func updateDerivedTeacherState() {
        filteredTeachers = teachers.filter { summary in
            let teacher = summary.teacher
            if let selectedUnit, teacher.unit != selectedUnit {
                return false
            }
            if let selectedStars, teacher.ratingStarBucket != selectedStars {
                return false
            }
            return true
        }

        availableUnits = Array(
            Set(
                teachers
                    .map { $0.teacher.unit.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        )
        .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}

private struct CourseSectionView: View {
    @Environment(\.leafyDependencies) private var dependencies

    @Binding var selectedCourse: CourseRatingSummary?
    let refreshID: UUID
    let isActive: Bool
    let lifecycleStore: RatingCatalogSectionStore

    private let pageSize = 50

    @State private var search = ""
    @State private var selectedCategory: String?
    @State private var selectedStars: Int?
    @State private var isFilterExpanded = false
    @State private var courses: [CourseRatingSummary] = []
    @State private var filteredCourses: [CourseRatingSummary] = []
    @State private var availableCategories: [String] = []
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var canLoadMore = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?
    @State private var suggestionSheet: CatalogSuggestionSheetContext?

    private var hasActiveFilters: Bool {
        selectedCategory != nil || selectedStars != nil || !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Group {
            if isActive {
                VStack(alignment: .leading, spacing: AppSpacing.card) {
                    HStack(alignment: .top, spacing: 12) {
                        LeafySectionTitle("评课", subtitle: "公选课课程库由后台维护，每个账号对每门课保留一条星级评分。")
                        Spacer(minLength: 8)
                        CatalogSuggestionPromptButton(title: "缺课程", systemName: "plus.circle.fill") {
                            openCourseSuggestion()
                        }
                    }

                    CourseFilterToolbar(
                        search: $search,
                        selectedCategory: $selectedCategory,
                        selectedStars: $selectedStars,
                        isExpanded: $isFilterExpanded,
                        availableCategories: availableCategories,
                        hasActiveFilters: hasActiveFilters,
                        clearFilters: clearFilters
                    )

                    courseContent
                }
            } else {
                Color.clear.frame(height: 0)
            }
        }
        .task(id: isActive) {
            guard isActive, lifecycleStore.beginInitialLoad() else { return }
            await loadCourses(reset: true)
        }
        .onChange(of: search) { _, _ in
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                await loadCourses(reset: true)
            }
        }
        .onChange(of: selectedCategory) { _, _ in
            scheduleCourseLoad(reset: true)
        }
        .onChange(of: selectedStars) { _, _ in
            updateDerivedCourseState()
        }
        .onChange(of: refreshID) { _, _ in
            scheduleCourseLoad(reset: true)
        }
        .onDisappear {
            searchTask?.cancel()
        }
        .sheet(item: $suggestionSheet) { context in
            CatalogSuggestionSheet(context: context)
                .presentationDetents([.medium, .large])
        }
    }

    @ViewBuilder
    private var courseContent: some View {
        if isLoading && courses.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
        } else if let errorMessage, courses.isEmpty {
            TeacherSectionMessageCard(
                title: "评课加载失败",
                message: errorMessage,
                actionTitle: "重试",
                action: { scheduleCourseLoad(reset: true) }
            )
        } else if courses.isEmpty {
            TeacherSectionMessageCard(
                title: emptyCourseTitle,
                message: emptyCourseMessage,
                actionTitle: "提交缺失课程",
                action: openCourseSuggestion
            )
        } else if filteredCourses.isEmpty {
            if hasActiveFilters {
                TeacherSectionMessageCard(
                    title: "没有匹配的课程",
                    message: "换一个分类、星级或关键词再试。",
                    actionTitle: "提交缺失课程",
                    action: openCourseSuggestion
                )
            } else {
                TeacherSectionMessageCard(
                    title: "没有匹配的课程",
                    message: "换一个分类、星级或关键词再试。",
                    actionTitle: "提交缺失课程",
                    action: openCourseSuggestion
                )
            }
        } else {
            if let errorMessage {
                Text(errorMessage)
                    .leafyBody()
                    .foregroundStyle(AppTheme.danger)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
            }

            ForEach(filteredCourses) { summary in
                Button {
                    selectedCourse = summary
                } label: {
                    CourseCard(summary: summary)
                }
                .buttonStyle(.plain)
            }

            if canLoadMore {
                RatingLoadMoreButton(isLoading: isLoadingMore) {
                    scheduleCourseLoad(reset: false)
                }
            }
        }
    }

    private var emptyCourseTitle: String {
        search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedCategory == nil
            ? "还没有课程库"
            : "没有找到课程"
    }

    private var emptyCourseMessage: String {
        search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedCategory == nil
            ? "先在 Supabase 的 course_catalog 表导入 name,unit,category,credit CSV，导入后这里会显示公选课列表。"
            : "换一个课程名、开课单位或分类关键词再试。"
    }

    @MainActor
    private func loadCourses(reset: Bool) async {
        let signpostState = LeafyPerformanceSignposter.ratings.beginInterval("courses-load")
        defer { LeafyPerformanceSignposter.ratings.endInterval("courses-load", signpostState) }

        if reset {
            isLoading = true
        } else {
            guard !isLoadingMore, canLoadMore else { return }
            isLoadingMore = true
        }
        defer {
            if reset {
                isLoading = false
            } else {
                isLoadingMore = false
            }
        }

        if ReviewDemoMode.isEnabled {
            let demoCourses = ReviewDemoDataSeeder.courseRatingSummaries(
                search: search,
                category: selectedCategory,
                limit: pageSize,
                offset: reset ? 0 : courses.count
            )
            if reset {
                courses = demoCourses
            } else {
                let existingIDs = Set(courses.map(\.id))
                courses.append(contentsOf: demoCourses.filter { !existingIDs.contains($0.id) })
            }
            canLoadMore = demoCourses.count == pageSize
            errorMessage = nil
            updateDerivedCourseState()
            return
        }

        do {
            try await dependencies.communityRepository.ensureAnonymousSession()
            let fetchedCourses = try await dependencies.communityRepository.fetchCourseRatingSummaries(
                search: search,
                category: selectedCategory,
                limit: pageSize,
                offset: reset ? 0 : courses.count
            )
            if reset {
                courses = fetchedCourses
            } else {
                let existingIDs = Set(courses.map(\.id))
                courses.append(contentsOf: fetchedCourses.filter { !existingIDs.contains($0.id) })
            }
            canLoadMore = fetchedCourses.count == pageSize
            errorMessage = nil
        } catch {
            if reset {
                courses = []
                canLoadMore = false
            }
            errorMessage = error.localizedDescription
        }
        updateDerivedCourseState()
    }

    private func clearFilters() {
        searchTask?.cancel()
        search = ""
        selectedCategory = nil
        selectedStars = nil
        scheduleCourseLoad(reset: true)
    }

    private func openCourseSuggestion() {
        suggestionSheet = CatalogSuggestionSheetContext(
            type: .course,
            initialName: search.trimmingCharacters(in: .whitespacesAndNewlines),
            initialCategory: selectedCategory,
            initialLocation: nil
        )
    }

    private func scheduleCourseLoad(reset: Bool) {
        searchTask?.cancel()
        searchTask = Task {
            await loadCourses(reset: reset)
        }
    }

    private func updateDerivedCourseState() {
        filteredCourses = courses.filter { summary in
            let course = summary.course
            if let selectedStars, course.ratingStarBucket != selectedStars {
                return false
            }
            return true
        }

        let loadedCategories = Array(
            Set(
                courses
                    .map { $0.course.category.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        )
        .sorted { $0.localizedStandardCompare($1) == .orderedAscending }

        if selectedCategory == nil || !loadedCategories.isEmpty {
            availableCategories = loadedCategories
        }
    }
}

private struct DishSectionView: View {
    @Environment(\.leafyDependencies) private var dependencies

    @Binding var selectedDish: DishRatingSummary?
    let refreshID: UUID
    let isActive: Bool
    let lifecycleStore: RatingCatalogSectionStore

    private let pageSize = 50

    @State private var search = ""
    @State private var selectedCanteen: String?
    @State private var selectedLocation: String?
    @State private var selectedStars: Int?
    @State private var isFilterExpanded = false
    @State private var dishes: [DishRatingSummary] = []
    @State private var filteredDishes: [DishRatingSummary] = []
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var canLoadMore = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?
    @State private var suggestionSheet: CatalogSuggestionSheetContext?

    private var hasActiveFilters: Bool {
        selectedCanteen != nil ||
        selectedLocation != nil ||
        selectedStars != nil ||
        !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Group {
            if isActive {
                VStack(alignment: .leading, spacing: AppSpacing.card) {
                    HStack(alignment: .top, spacing: 12) {
                        LeafySectionTitle("评菜", subtitle: "按食堂和餐厅筛选菜品，每个账号对每道菜保留一条星级评分。")
                        Spacer(minLength: 8)
                        CatalogSuggestionPromptButton(title: "缺菜品", systemName: "fork.knife.circle.fill") {
                            openDishSuggestion()
                        }
                    }

                    DishFilterToolbar(
                        search: $search,
                        selectedCanteen: $selectedCanteen,
                        selectedLocation: $selectedLocation,
                        selectedStars: $selectedStars,
                        isExpanded: $isFilterExpanded,
                        hasActiveFilters: hasActiveFilters,
                        clearFilters: clearFilters
                    )

                    dishContent
                }
            } else {
                Color.clear.frame(height: 0)
            }
        }
        .task(id: isActive) {
            guard isActive, lifecycleStore.beginInitialLoad() else { return }
            await loadDishes(reset: true)
        }
        .onChange(of: search) { _, _ in
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                await loadDishes(reset: true)
            }
        }
        .onChange(of: selectedCanteen) { _, canteen in
            if let currentLocation = selectedLocation,
               let canteen,
               !CampusDiningLocation.locations(for: canteen).contains(where: { $0.fullName == currentLocation }) {
                selectedLocation = nil
            }
            scheduleDishLoad(reset: true)
        }
        .onChange(of: selectedLocation) { _, _ in
            scheduleDishLoad(reset: true)
        }
        .onChange(of: selectedStars) { _, _ in
            updateDerivedDishState()
        }
        .onChange(of: refreshID) { _, _ in
            scheduleDishLoad(reset: true)
        }
        .onDisappear {
            searchTask?.cancel()
        }
        .sheet(item: $suggestionSheet) { context in
            CatalogSuggestionSheet(context: context)
                .presentationDetents([.medium, .large])
        }
    }

    @ViewBuilder
    private var dishContent: some View {
        if isLoading && dishes.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
        } else if let errorMessage, dishes.isEmpty {
            TeacherSectionMessageCard(
                title: "评菜加载失败",
                message: errorMessage,
                actionTitle: "重试",
                action: { scheduleDishLoad(reset: true) }
            )
        } else if dishes.isEmpty {
            TeacherSectionMessageCard(
                title: emptyDishTitle,
                message: emptyDishMessage,
                actionTitle: "提交缺失菜品",
                action: openDishSuggestion
            )
        } else if filteredDishes.isEmpty {
            TeacherSectionMessageCard(
                title: "没有匹配的菜品",
                message: "换一个食堂、地点、星级或菜名关键词再试。提交新菜名前，也可以先搜索确认是否已经有人提交过。",
                actionTitle: "提交缺失菜品",
                action: openDishSuggestion
            )
        } else {
            if let errorMessage {
                Text(errorMessage)
                    .leafyBody()
                    .foregroundStyle(AppTheme.danger)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
            }

            ForEach(filteredDishes) { summary in
                Button {
                    selectedDish = summary
                } label: {
                    DishCard(summary: summary)
                }
                .buttonStyle(.plain)
            }

            if canLoadMore {
                RatingLoadMoreButton(isLoading: isLoadingMore) {
                    scheduleDishLoad(reset: false)
                }
            }
        }
    }

    private var emptyDishTitle: String {
        search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        selectedCanteen == nil &&
        selectedLocation == nil
            ? "还没有菜品库"
            : "没有找到菜品"
    }

    private var emptyDishMessage: String {
        search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        selectedCanteen == nil &&
        selectedLocation == nil
            ? "先提交常吃菜品，审核通过后这里会显示可评分的菜品列表。"
            : "提交新菜名前，建议先换个关键词或地点确认是否已经有人提交过。"
    }

    @MainActor
    private func loadDishes(reset: Bool) async {
        let signpostState = LeafyPerformanceSignposter.ratings.beginInterval("dishes-load")
        defer { LeafyPerformanceSignposter.ratings.endInterval("dishes-load", signpostState) }

        if reset {
            isLoading = true
        } else {
            guard !isLoadingMore, canLoadMore else { return }
            isLoadingMore = true
        }
        defer {
            if reset {
                isLoading = false
            } else {
                isLoadingMore = false
            }
        }

        if ReviewDemoMode.isEnabled {
            let demoDishes = ReviewDemoDataSeeder.dishRatingSummaries(
                search: search,
                canteen: selectedCanteen,
                location: selectedLocation,
                limit: pageSize,
                offset: reset ? 0 : dishes.count
            )
            if reset {
                dishes = demoDishes
            } else {
                let existingIDs = Set(dishes.map(\.id))
                dishes.append(contentsOf: demoDishes.filter { !existingIDs.contains($0.id) })
            }
            canLoadMore = demoDishes.count == pageSize
            errorMessage = nil
            updateDerivedDishState()
            return
        }

        do {
            try await dependencies.communityRepository.ensureAnonymousSession()
            let fetchedDishes = try await dependencies.communityRepository.fetchDishRatingSummaries(
                search: search,
                canteen: selectedCanteen,
                location: selectedLocation,
                limit: pageSize,
                offset: reset ? 0 : dishes.count
            )
            if reset {
                dishes = fetchedDishes
            } else {
                let existingIDs = Set(dishes.map(\.id))
                dishes.append(contentsOf: fetchedDishes.filter { !existingIDs.contains($0.id) })
            }
            canLoadMore = fetchedDishes.count == pageSize
            errorMessage = nil
        } catch {
            if reset {
                dishes = []
                canLoadMore = false
            }
            errorMessage = error.localizedDescription
        }
        updateDerivedDishState()
    }

    private func clearFilters() {
        searchTask?.cancel()
        search = ""
        selectedCanteen = nil
        selectedLocation = nil
        selectedStars = nil
        scheduleDishLoad(reset: true)
    }

    private func openDishSuggestion() {
        suggestionSheet = CatalogSuggestionSheetContext(
            type: .dish,
            initialName: search.trimmingCharacters(in: .whitespacesAndNewlines),
            initialCategory: nil,
            initialLocation: selectedLocation
        )
    }

    private func scheduleDishLoad(reset: Bool) {
        searchTask?.cancel()
        searchTask = Task {
            await loadDishes(reset: reset)
        }
    }

    private func updateDerivedDishState() {
        filteredDishes = dishes.filter { summary in
            let dish = summary.dish
            if let selectedStars, dish.ratingStarBucket != selectedStars {
                return false
            }
            return true
        }
    }
}

private struct TeacherFilterToolbar: View {
    @Environment(\.leafyControlScale) private var leafyControlScale
    @Environment(\.leafyThemeColorPreference) private var themeColorPreference

    @Binding var search: String
    @Binding var selectedUnit: String?
    @Binding var selectedStars: Int?
    @Binding var isExpanded: Bool

    let availableUnits: [String]
    let hasActiveFilters: Bool
    let clearFilters: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            searchControl
                .animation(.snappy, value: isExpanded)

            ScrollView(.horizontal, showsIndicators: false) {
                filterMenus
                    .padding(.horizontal, 1)
            }
            .leafyTransparentHorizontalScrollRail()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var searchControl: some View {
        if isExpanded {
            searchField
                .transition(.move(edge: .leading).combined(with: .opacity))
        } else {
            collapsedButton
                .transition(.scale.combined(with: .opacity))
        }
    }

    private var collapsedButton: some View {
        Button {
            isExpanded = true
        } label: {
            Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "magnifyingglass")
                .font(.system(size: 15 * leafyControlScale, weight: .semibold))
                .foregroundStyle(AppTheme.accentEmphasis(for: themeColorPreference))
                .frame(width: 40 * leafyControlScale, height: 40 * leafyControlScale)
                .leafyGlassSurface(in: Circle(), isInteractive: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("筛选教师")
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppTheme.secondaryText)

            TextField("搜索教师或学院", text: $search)
                .leafyDisableAutocapitalization()
                .autocorrectionDisabled()
                .leafyBody()

            Button {
                if search.isEmpty {
                    isExpanded = false
                } else {
                    search = ""
                }
            } label: {
                Image(systemName: search.isEmpty ? "chevron.up.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(AppTheme.tertiaryText)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(search.isEmpty ? "收起筛选" : "清空搜索")
        }
        .padding(.horizontal, 12)
        .frame(width: 220 * leafyControlScale, height: 40 * leafyControlScale)
        .leafyGlassSurface(
            in: Capsule(),
            fallbackFill: AppTheme.cardElevated.opacity(0.96),
            isInteractive: true
        )
    }

    private var filterMenus: some View {
        HStack(spacing: 10) {
            Menu {
                Button("全部学院") {
                    selectedUnit = nil
                }
                ForEach(availableUnits, id: \.self) { unit in
                    Button {
                        selectedUnit = unit
                    } label: {
                        Label(unit, systemImage: selectedUnit == unit ? "checkmark.circle.fill" : "circle")
                    }
                }
            } label: {
                filterChip(
                    title: selectedUnit ?? "学院",
                    systemName: "building.columns",
                    isSelected: selectedUnit != nil
                )
            }

            Menu {
                Button("全部星级") {
                    selectedStars = nil
                }
                ForEach((1...5).reversed(), id: \.self) { stars in
                    Button {
                        selectedStars = stars
                    } label: {
                        Label("\(stars) 星", systemImage: selectedStars == stars ? "star.fill" : "star")
                    }
                }
            } label: {
                filterChip(
                    title: selectedStars.map { "\($0) 星" } ?? "星级",
                    systemName: "star",
                    isSelected: selectedStars != nil
                )
            }

            if hasActiveFilters {
                Button(action: clearFilters) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 14 * leafyControlScale, weight: .semibold))
                        .foregroundStyle(AppTheme.accentEmphasis(for: themeColorPreference))
                        .frame(width: 36 * leafyControlScale, height: 36 * leafyControlScale)
                        .leafyGlassSurface(in: Circle(), isInteractive: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除筛选")
            }
        }
    }

    private func filterChip(title: String, systemName: String, isSelected: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemName)
                .font(.system(size: 12 * leafyControlScale, weight: .semibold))
            Text(title)
                .leafySubheadline()
                .lineLimit(1)
        }
        .foregroundStyle(isSelected ? AppTheme.textOnAccent(for: themeColorPreference) : AppTheme.primaryText)
        .padding(.horizontal, 12 * leafyControlScale)
        .frame(height: 36 * leafyControlScale)
        .leafyCapsuleChipSurface(isSelected: isSelected)
    }
}

private struct CourseFilterToolbar: View {
    @Environment(\.leafyControlScale) private var leafyControlScale
    @Environment(\.leafyThemeColorPreference) private var themeColorPreference

    @Binding var search: String
    @Binding var selectedCategory: String?
    @Binding var selectedStars: Int?
    @Binding var isExpanded: Bool

    let availableCategories: [String]
    let hasActiveFilters: Bool
    let clearFilters: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            searchControl
                .animation(.snappy, value: isExpanded)

            ScrollView(.horizontal, showsIndicators: false) {
                filterMenus
                    .padding(.horizontal, 1)
            }
            .leafyTransparentHorizontalScrollRail()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var searchControl: some View {
        if isExpanded {
            searchField
                .transition(.move(edge: .leading).combined(with: .opacity))
        } else {
            collapsedButton
                .transition(.scale.combined(with: .opacity))
        }
    }

    private var collapsedButton: some View {
        Button {
            isExpanded = true
        } label: {
            Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "magnifyingglass")
                .font(.system(size: 15 * leafyControlScale, weight: .semibold))
                .foregroundStyle(AppTheme.accentEmphasis(for: themeColorPreference))
                .frame(width: 40 * leafyControlScale, height: 40 * leafyControlScale)
                .leafyGlassSurface(in: Circle(), isInteractive: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("筛选课程")
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppTheme.secondaryText)

            TextField("搜索课程或单位", text: $search)
                .leafyDisableAutocapitalization()
                .autocorrectionDisabled()
                .leafyBody()

            Button {
                if search.isEmpty {
                    isExpanded = false
                } else {
                    search = ""
                }
            } label: {
                Image(systemName: search.isEmpty ? "chevron.up.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(AppTheme.tertiaryText)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(search.isEmpty ? "收起筛选" : "清空搜索")
        }
        .padding(.horizontal, 12)
        .frame(width: 220 * leafyControlScale, height: 40 * leafyControlScale)
        .leafyGlassSurface(
            in: Capsule(),
            fallbackFill: AppTheme.cardElevated.opacity(0.96),
            isInteractive: true
        )
    }

    private var filterMenus: some View {
        HStack(spacing: 10) {
            Menu {
                Button("全部分类") {
                    selectedCategory = nil
                }
                ForEach(availableCategories, id: \.self) { category in
                    Button {
                        selectedCategory = category
                    } label: {
                        Label(category, systemImage: selectedCategory == category ? "checkmark.circle.fill" : "circle")
                    }
                }
            } label: {
                filterChip(
                    title: selectedCategory ?? "分类",
                    systemName: "tag",
                    isSelected: selectedCategory != nil
                )
            }

            Menu {
                Button("全部星级") {
                    selectedStars = nil
                }
                ForEach((1...5).reversed(), id: \.self) { stars in
                    Button {
                        selectedStars = stars
                    } label: {
                        Label("\(stars) 星", systemImage: selectedStars == stars ? "star.fill" : "star")
                    }
                }
            } label: {
                filterChip(
                    title: selectedStars.map { "\($0) 星" } ?? "星级",
                    systemName: "star",
                    isSelected: selectedStars != nil
                )
            }

            if hasActiveFilters {
                Button(action: clearFilters) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 14 * leafyControlScale, weight: .semibold))
                        .foregroundStyle(AppTheme.accentEmphasis(for: themeColorPreference))
                        .frame(width: 36 * leafyControlScale, height: 36 * leafyControlScale)
                        .leafyGlassSurface(in: Circle(), isInteractive: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除筛选")
            }
        }
    }

    private func filterChip(title: String, systemName: String, isSelected: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemName)
                .font(.system(size: 12 * leafyControlScale, weight: .semibold))
            Text(title)
                .leafySubheadline()
                .lineLimit(1)
        }
        .foregroundStyle(isSelected ? AppTheme.textOnAccent(for: themeColorPreference) : AppTheme.primaryText)
        .padding(.horizontal, 12 * leafyControlScale)
        .frame(height: 36 * leafyControlScale)
        .leafyCapsuleChipSurface(isSelected: isSelected)
    }
}

private struct DishFilterToolbar: View {
    @Environment(\.leafyControlScale) private var leafyControlScale
    @Environment(\.leafyThemeColorPreference) private var themeColorPreference

    @Binding var search: String
    @Binding var selectedCanteen: String?
    @Binding var selectedLocation: String?
    @Binding var selectedStars: Int?
    @Binding var isExpanded: Bool

    let hasActiveFilters: Bool
    let clearFilters: () -> Void

    private var availableLocations: [CampusDiningLocation] {
        if let selectedCanteen {
            return CampusDiningLocation.locations(for: selectedCanteen)
        }
        return CampusDiningLocation.all
    }

    var body: some View {
        HStack(spacing: 10) {
            searchControl
                .animation(.snappy, value: isExpanded)

            ScrollView(.horizontal, showsIndicators: false) {
                filterMenus
                    .padding(.horizontal, 1)
            }
            .leafyTransparentHorizontalScrollRail()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var searchControl: some View {
        if isExpanded {
            searchField
                .transition(.move(edge: .leading).combined(with: .opacity))
        } else {
            collapsedButton
                .transition(.scale.combined(with: .opacity))
        }
    }

    private var collapsedButton: some View {
        Button {
            isExpanded = true
        } label: {
            Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "magnifyingglass")
                .font(.system(size: 15 * leafyControlScale, weight: .semibold))
                .foregroundStyle(AppTheme.accentEmphasis(for: themeColorPreference))
                .frame(width: 40 * leafyControlScale, height: 40 * leafyControlScale)
                .leafyGlassSurface(in: Circle(), isInteractive: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("筛选菜品")
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppTheme.secondaryText)

            TextField("搜索菜名或地点", text: $search)
                .leafyDisableAutocapitalization()
                .autocorrectionDisabled()
                .leafyBody()

            Button {
                if search.isEmpty {
                    isExpanded = false
                } else {
                    search = ""
                }
            } label: {
                Image(systemName: search.isEmpty ? "chevron.up.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(AppTheme.tertiaryText)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(search.isEmpty ? "收起筛选" : "清空搜索")
        }
        .padding(.horizontal, 12)
        .frame(width: 220 * leafyControlScale, height: 40 * leafyControlScale)
        .leafyGlassSurface(
            in: Capsule(),
            fallbackFill: AppTheme.cardElevated.opacity(0.96),
            isInteractive: true
        )
    }

    private var filterMenus: some View {
        HStack(spacing: 10) {
            Menu {
                Button("全部食堂") {
                    selectedCanteen = nil
                    selectedLocation = nil
                }
                ForEach(CampusDiningLocation.canteens, id: \.self) { canteen in
                    Button {
                        selectedCanteen = canteen
                        if let currentLocation = selectedLocation,
                           !CampusDiningLocation.locations(for: canteen).contains(where: { $0.fullName == currentLocation }) {
                            selectedLocation = nil
                        }
                    } label: {
                        Label(canteen, systemImage: selectedCanteen == canteen ? "checkmark.circle.fill" : "circle")
                    }
                }
            } label: {
                filterChip(
                    title: selectedCanteen ?? "食堂",
                    systemName: "building.2",
                    isSelected: selectedCanteen != nil
                )
            }

            Menu {
                Button("全部地点") {
                    selectedLocation = nil
                }
                ForEach(availableLocations) { location in
                    Button {
                        selectedCanteen = location.canteen
                        selectedLocation = location.fullName
                    } label: {
                        Label(location.displayName, systemImage: selectedLocation == location.fullName ? "checkmark.circle.fill" : "circle")
                    }
                }
            } label: {
                filterChip(
                    title: selectedLocation.flatMap(CampusDiningLocation.displayName(for:)) ?? "地点",
                    systemName: "mappin.and.ellipse",
                    isSelected: selectedLocation != nil
                )
            }

            Menu {
                Button("全部星级") {
                    selectedStars = nil
                }
                ForEach((1...5).reversed(), id: \.self) { stars in
                    Button {
                        selectedStars = stars
                    } label: {
                        Label("\(stars) 星", systemImage: selectedStars == stars ? "star.fill" : "star")
                    }
                }
            } label: {
                filterChip(
                    title: selectedStars.map { "\($0) 星" } ?? "星级",
                    systemName: "star",
                    isSelected: selectedStars != nil
                )
            }

            if hasActiveFilters {
                Button(action: clearFilters) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 14 * leafyControlScale, weight: .semibold))
                        .foregroundStyle(AppTheme.accentEmphasis(for: themeColorPreference))
                        .frame(width: 36 * leafyControlScale, height: 36 * leafyControlScale)
                        .leafyGlassSurface(in: Circle(), isInteractive: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除筛选")
            }
        }
    }

    private func filterChip(title: String, systemName: String, isSelected: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemName)
                .font(.system(size: 12 * leafyControlScale, weight: .semibold))
            Text(title)
                .leafySubheadline()
                .lineLimit(1)
        }
        .foregroundStyle(isSelected ? AppTheme.textOnAccent(for: themeColorPreference) : AppTheme.primaryText)
        .padding(.horizontal, 12 * leafyControlScale)
        .frame(height: 36 * leafyControlScale)
        .leafyCapsuleChipSurface(isSelected: isSelected)
    }
}

private struct CatalogSuggestionPromptButton: View {
    @Environment(\.leafyControlScale) private var leafyControlScale
    @Environment(\.leafyThemeColorPreference) private var themeColorPreference

    let title: String
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemName)
                .font(.system(size: 13 * leafyControlScale, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(AppTheme.accentEmphasis(for: themeColorPreference))
                .padding(.horizontal, 12 * leafyControlScale)
                .frame(height: 36 * leafyControlScale)
                .leafyCapsuleChipSurface(isSelected: false)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

private struct CatalogSuggestionSheetContext: Identifiable {
    let id = UUID()
    let type: CatalogSuggestionType
    let initialName: String
    let initialCategory: String?
    let initialLocation: String?
}

private struct CatalogSuggestionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.leafyDependencies) private var dependencies
    @Environment(\.leafyLanguage) private var leafyLanguage

    let context: CatalogSuggestionSheetContext

    @State private var name: String
    @State private var unit = ""
    @State private var teacherName = ""
    @State private var category: String
    @State private var credit = ""
    @State private var selectedCanteen: String?
    @State private var selectedDishLocation: String?
    @State private var initialStars = 0
    @State private var note = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var operationAlert: LeafyOperationAlert?

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedUnit: String {
        if context.type == .dish {
            return selectedDishLocation?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        return unit.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedTeacherName: String {
        teacherName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var parsedCredit: Double? {
        let text = credit.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return Double(text.replacingOccurrences(of: ",", with: "."))
    }

    private var isCreditValid: Bool {
        guard context.type == .course else { return true }
        let text = credit.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return true }
        guard let parsedCredit else { return false }
        return parsedCredit >= 0
    }

    private var canSubmit: Bool {
        !trimmedName.isEmpty &&
        !trimmedUnit.isEmpty &&
        (context.type == .teacher || !trimmedTeacherName.isEmpty) &&
        isCreditValid &&
        !isSubmitting
    }

    init(context: CatalogSuggestionSheetContext) {
        self.context = context
        _name = State(initialValue: context.initialName)
        _category = State(initialValue: context.initialCategory?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "公选课")
        let initialLocation = context.initialLocation.flatMap(CampusDiningLocation.location(for:))
        _selectedCanteen = State(initialValue: initialLocation?.canteen)
        _selectedDishLocation = State(initialValue: initialLocation?.fullName)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.card) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(context.type.sheetTitle)
                            .leafyTitle3()
                            .foregroundStyle(AppTheme.primaryText)
                        Text(context.type.sheetSubtitle)
                            .leafyBody()
                            .foregroundStyle(AppTheme.secondaryText)
                    }

                    if context.type == .dish {
                        Text("提交新菜名前，建议先在评菜页搜索菜名并切换地点确认是否已经有人提交过。")
                            .leafyBody()
                            .foregroundStyle(AppTheme.secondaryText)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        CatalogSuggestionTextField(
                            title: context.type.nameFieldTitle,
                            placeholder: context.type.nameFieldPlaceholder,
                            text: $name
                        )

                        if context.type == .course {
                            CatalogSuggestionTextField(
                                title: "授课老师",
                                placeholder: "例如：张三",
                                text: $teacherName
                            )
                        }

                        if context.type == .dish {
                            CatalogSuggestionDiningLocationPicker(
                                selectedCanteen: $selectedCanteen,
                                selectedLocation: $selectedDishLocation
                            )
                        } else {
                            CatalogSuggestionOptionMenu(
                                title: context.type == .teacher ? "学院/单位" : "开课单位",
                                placeholder: context.type == .teacher ? "选择学院/单位" : "选择开课单位",
                                options: CommunityCatalogOptions.units,
                                selection: $unit
                            )
                        }

                        if context.type == .course {
                            CatalogSuggestionTextField(
                                title: "分类",
                                placeholder: "公选课",
                                text: $category
                            )

                            CatalogSuggestionTextField(
                                title: "学分",
                                placeholder: "可留空",
                                text: $credit,
                                keyboardType: .decimalPad
                            )
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("顺手评分（可选）")
                                .leafySubheadline()
                                .foregroundStyle(AppTheme.primaryText)
                            TeacherStarPicker(selection: $initialStars)
                            if initialStars > 0 {
                                Button("清除评分") {
                                    initialStars = 0
                                }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.accent)
                            }
                            Text("审核通过后，这个评分才会计入正式均分。")
                                .microCaption()
                                .foregroundStyle(AppTheme.secondaryText)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("补充说明")
                                .leafySubheadline()
                                .foregroundStyle(AppTheme.primaryText)
                            TextEditor(text: $note)
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 92)
                                .padding(10)
                                .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                                        .stroke(AppTheme.separator.opacity(0.7), lineWidth: 1)
                                )
                        }

                        if !isCreditValid {
                            Text("学分需要填写为非负数字。")
                                .leafyBody()
                                .foregroundStyle(AppTheme.danger)
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .leafyBody()
                                .foregroundStyle(AppTheme.danger)
                        }

                        Button {
                            Task { await submit() }
                        } label: {
                            HStack(spacing: 8) {
                                if isSubmitting {
                                    ProgressView()
                                        .tint(.white)
                                }
                                Text("提交建议")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundStyle(.white)
                            .background(Capsule().fill(canSubmit ? AppTheme.accent : AppTheme.tertiaryText))
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSubmit)
                    }
                    .padding(18)
                    .leafyCardStyle()
                }
                .padding(AppSpacing.page)
            }
            .background(LeafyPageBackground())
            .navigationTitle(context.type.navigationTitle)
            .leafyInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .leafyTrailing) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
            .leafyOperationAlert($operationAlert)
        }
    }

    @MainActor
    private func submit() async {
        guard canSubmit else { return }
        isSubmitting = true
        defer { isSubmitting = false }

        if ReviewDemoMode.isEnabled {
            errorMessage = nil
            operationAlert = .success(
                L10n.text("已提交，等待审核。", language: leafyLanguage),
                buttonTitle: L10n.text("好的", language: leafyLanguage),
                action: { dismiss() }
            )
            return
        }

        let input = CatalogSuggestionInput(
            type: context.type,
            name: trimmedName,
            unit: trimmedUnit,
            teacherName: context.type == .course ? trimmedTeacherName : nil,
            category: context.type == .course ? category.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "公选课" : nil,
            credit: context.type == .course ? parsedCredit : nil,
            initialStars: initialStars == 0 ? nil : initialStars,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )

        do {
            try await dependencies.communityRepository.submitCatalogSuggestion(input: input)
            errorMessage = nil
            operationAlert = .success(
                L10n.text("已提交，等待审核。", language: leafyLanguage),
                buttonTitle: L10n.text("好的", language: leafyLanguage),
                action: { dismiss() }
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct CatalogSuggestionOptionMenu: View {
    let title: String
    let placeholder: String
    let options: [String]
    @Binding var selection: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .leafySubheadline()
                .foregroundStyle(AppTheme.primaryText)

            Menu {
                ForEach(options, id: \.self) { option in
                    Button {
                        selection = option
                    } label: {
                        if selection == option {
                            Label(option, systemImage: "checkmark")
                        } else {
                            Text(option)
                        }
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Text(selection.isEmpty ? placeholder : selection)
                        .leafyBody()
                        .foregroundStyle(selection.isEmpty ? AppTheme.tertiaryText : AppTheme.primaryText)
                        .lineLimit(1)

                    Spacer()

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.accentEmphasis)
                }
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                        .stroke(AppTheme.separator.opacity(0.7), lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }
}

private struct CatalogSuggestionDiningLocationPicker: View {
    @Binding var selectedCanteen: String?
    @Binding var selectedLocation: String?

    private var availableLocations: [CampusDiningLocation] {
        if let selectedCanteen {
            return CampusDiningLocation.locations(for: selectedCanteen)
        }
        return []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CatalogSuggestionPickerMenu(
                title: "食堂",
                placeholder: "选择东区或西区食堂",
                options: CampusDiningLocation.canteens,
                selection: Binding(
                    get: { selectedCanteen ?? "" },
                    set: { canteen in
                        selectedCanteen = canteen.isEmpty ? nil : canteen
                        if let selectedLocation,
                           !CampusDiningLocation.locations(for: canteen).contains(where: { $0.fullName == selectedLocation }) {
                            self.selectedLocation = nil
                        }
                    }
                )
            )

            CatalogSuggestionPickerMenu(
                title: "地点",
                placeholder: selectedCanteen == nil ? "先选择食堂" : "选择楼层和餐厅",
                options: availableLocations.map(\.displayName),
                selection: Binding(
                    get: { selectedLocation.flatMap(CampusDiningLocation.displayName(for:)) ?? "" },
                    set: { displayName in
                        guard let location = availableLocations.first(where: { $0.displayName == displayName }) else {
                            selectedLocation = nil
                            return
                        }
                        selectedLocation = location.fullName
                    }
                )
            )
            .disabled(selectedCanteen == nil)
        }
    }
}

private struct CatalogSuggestionPickerMenu: View {
    let title: String
    let placeholder: String
    let options: [String]
    @Binding var selection: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .leafySubheadline()
                .foregroundStyle(AppTheme.primaryText)

            Menu {
                ForEach(options, id: \.self) { option in
                    Button {
                        selection = option
                    } label: {
                        if selection == option {
                            Label(option, systemImage: "checkmark")
                        } else {
                            Text(option)
                        }
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Text(selection.isEmpty ? placeholder : selection)
                        .leafyBody()
                        .foregroundStyle(selection.isEmpty ? AppTheme.tertiaryText : AppTheme.primaryText)
                        .lineLimit(1)

                    Spacer()

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.accentEmphasis)
                }
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                        .stroke(AppTheme.separator.opacity(0.7), lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }
}

private struct CatalogSuggestionTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .leafySubheadline()
                .foregroundStyle(AppTheme.primaryText)
            TextField(placeholder, text: $text)
                .leafyDisableAutocapitalization()
                .autocorrectionDisabled()
                .keyboardType(keyboardType)
                .leafyBody()
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                        .stroke(AppTheme.separator.opacity(0.7), lineWidth: 1)
                )
        }
    }
}

private extension CatalogSuggestionType {
    var sheetTitle: String {
        switch self {
        case .teacher:
            return "提交缺失老师"
        case .course:
            return "提交缺失课程"
        case .dish:
            return "提交缺失菜品"
        }
    }

    var sheetSubtitle: String {
        switch self {
        case .teacher:
            return "审核通过后会进入评教老师名录。"
        case .course:
            return "审核通过后会进入公选课课程库。"
        case .dish:
            return "审核通过后会进入评菜菜品库。"
        }
    }

    var navigationTitle: String {
        switch self {
        case .teacher:
            return "缺失老师"
        case .course:
            return "缺失课程"
        case .dish:
            return "缺失菜品"
        }
    }

    var nameFieldTitle: String {
        switch self {
        case .teacher:
            return "老师姓名"
        case .course:
            return "课程名"
        case .dish:
            return "菜名"
        }
    }

    var nameFieldPlaceholder: String {
        switch self {
        case .teacher:
            return "例如：张三"
        case .course:
            return "例如：森林生态学导论"
        case .dish:
            return "例如：番茄牛腩饭"
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private struct TeacherSectionMessageCard: View {
    @Environment(\.leafyLanguage) private var leafyLanguage

    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.text(title, language: leafyLanguage))
                .leafyHeadline()
                .foregroundStyle(AppTheme.primaryText)
            Text(L10n.text(message, language: leafyLanguage))
                .leafyBody()
                .foregroundStyle(AppTheme.secondaryText)

            if let actionTitle, let action {
                Button(L10n.text(actionTitle, language: leafyLanguage), action: action)
                    .foregroundStyle(AppTheme.accentEmphasis)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .leafyCardStyle()
    }
}

private struct RatingLoadMoreButton: View {
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.down.circle")
                }
                Text(isLoading ? "加载中" : "加载更多")
                    .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundStyle(AppTheme.primaryText)
            .leafyGlassSurface(in: Capsule(), isInteractive: true)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}

private struct CommunityPostCard: View {
    let post: CommunityMockPost

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Circle()
                    .fill(post.avatarColor.opacity(0.18))
                    .frame(width: 42, height: 42)
                    .overlay(
                        Text(String(post.author.prefix(1)))
                            .font(.headline)
                            .foregroundStyle(post.avatarColor)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(post.author)
                        .leafyHeadline()
                        .foregroundStyle(AppTheme.primaryText)
                    Text(post.timestamp)
                        .microCaption()
                        .foregroundStyle(AppTheme.secondaryText)
                }

                Spacer()
            }

            Text(post.title)
                .leafyHeadline()
                .foregroundStyle(AppTheme.primaryText)

            Text(post.body)
                .leafyBody()
                .foregroundStyle(AppTheme.secondaryText)

            if !post.photoLabels.isEmpty {
                CommunityPhotoGrid(labels: post.photoLabels)
            }

            HStack(spacing: 16) {
                CommunityStat(icon: "heart", value: "\(post.likes)")
                CommunityStat(icon: "message", value: "\(post.comments)")
                CommunityStat(icon: "bookmark", value: post.tag)
            }
        }
        .padding(18)
        .leafyCardStyle()
    }
}

private struct CommunityPhotoGrid: View {
    let labels: [String]

    private let columns = [
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(labels, id: \.self) { label in
                RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                    .fill(AppTheme.subtleGreenGradient)
                    .frame(height: 88)
                    .overlay(
                        Text(label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.accentEmphasis)
                    )
            }
        }
    }
}

private struct CommunityStat: View {
    let icon: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(value)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(AppTheme.secondaryText)
    }
}

private extension TeacherProfile {
    var ratingStarBucket: Int? {
        guard ratingCount > 0 else { return nil }
        return min(max(Int(ratingAverage.rounded()), 1), 5)
    }
}

private extension CourseProfile {
    var ratingStarBucket: Int? {
        guard ratingCount > 0 else { return nil }
        return min(max(Int(ratingAverage.rounded()), 1), 5)
    }

    var creditText: String {
        if credit == floor(credit) {
            return "\(Int(credit)) 学分"
        }
        return String(format: "%.1f 学分", credit)
    }
}

private extension DishProfile {
    var ratingStarBucket: Int? {
        guard ratingCount > 0 else { return nil }
        return min(max(Int(ratingAverage.rounded()), 1), 5)
    }

    var displayLocation: String {
        CampusDiningLocation.displayName(for: location) ?? location
    }
}

private struct TeacherCard: View {
    @Environment(\.leafyThemeColorPreference) private var themeColorPreference

    let summary: TeacherRatingSummary

    private var teacher: TeacherProfile {
        summary.teacher
    }

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(AppTheme.accentSoft(for: themeColorPreference))
                .frame(width: 48, height: 48)
                .overlay(
                    Text(String(teacher.name.prefix(1)))
                        .font(.headline)
                        .foregroundStyle(AppTheme.accentEmphasis(for: themeColorPreference))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(teacher.name)
                    .leafyHeadline()
                    .foregroundStyle(AppTheme.primaryText)
                Text(teacher.unit)
                    .microCaption()
                    .foregroundStyle(AppTheme.secondaryText)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                        .font(.caption)
                    Text(teacher.ratingCount == 0 ? "暂无" : String(format: "%.1f", teacher.ratingAverage))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(AppTheme.primaryText)
                }

                Text("\(teacher.ratingCount) 人评分")
                    .microCaption()
                    .foregroundStyle(AppTheme.tertiaryText)
            }
        }
        .padding(18)
        .leafyCardStyle()
    }
}

private struct CourseCard: View {
    @Environment(\.leafyThemeColorPreference) private var themeColorPreference

    let summary: CourseRatingSummary

    private var course: CourseProfile {
        summary.course
    }

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(AppTheme.accentSoft(for: themeColorPreference))
                .frame(width: 48, height: 48)
                .overlay(
                    Image(systemName: "book.closed.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppTheme.accentEmphasis(for: themeColorPreference))
                )

            VStack(alignment: .leading, spacing: 5) {
                Text(course.name)
                    .leafyHeadline()
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(2)
                Text("\(course.displayUnit) · \(course.displayCategory) · \(course.creditText)")
                    .microCaption()
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(2)
            }

            Spacer(minLength: 10)

            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                        .font(.caption)
                    Text(course.ratingCount == 0 ? "暂无" : String(format: "%.1f", course.ratingAverage))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(AppTheme.primaryText)
                }

                Text("\(course.ratingCount) 人评分")
                    .microCaption()
                    .foregroundStyle(AppTheme.tertiaryText)
            }
        }
        .padding(18)
        .leafyCardStyle()
    }
}

private struct DishCard: View {
    @Environment(\.leafyThemeColorPreference) private var themeColorPreference

    let summary: DishRatingSummary

    private var dish: DishProfile {
        summary.dish
    }

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(AppTheme.accentSoft(for: themeColorPreference))
                .frame(width: 48, height: 48)
                .overlay(
                    Image(systemName: "fork.knife")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppTheme.accentEmphasis(for: themeColorPreference))
                )

            VStack(alignment: .leading, spacing: 5) {
                Text(dish.name)
                    .leafyHeadline()
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(2)
                Text(dish.displayLocation)
                    .microCaption()
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(2)
            }

            Spacer(minLength: 10)

            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                        .font(.caption)
                    Text(dish.ratingCount == 0 ? "暂无" : String(format: "%.1f", dish.ratingAverage))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(AppTheme.primaryText)
                }

                Text("\(dish.ratingCount) 人评分")
                    .microCaption()
                    .foregroundStyle(AppTheme.tertiaryText)
            }
        }
        .padding(18)
        .leafyCardStyle()
    }
}

private struct ComposerPlaceholderSheet: View {
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                LeafySectionTitle("发布帖子", subtitle: "当前阶段先验证半屏模态和表单结构，发布行为继续使用 Mock。")

                VStack(alignment: .leading, spacing: 12) {
                    Text("标题")
                        .font(.headline)
                    RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                        .fill(AppTheme.fill)
                        .frame(height: 52)

                    Text("正文")
                        .font(.headline)
                    RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                        .fill(AppTheme.fill)
                        .frame(height: 160)
                }
                .padding(18)
                .leafyCardStyle()

                Spacer()
            }
            .padding(AppSpacing.page)
            .background(LeafyPageBackground())
            .navigationTitle("发布")
            .leafyInlineNavigationTitle()
        }
    }
}

private struct CommunityPostDetailSheet: View {
    let post: CommunityMockPost

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.card) {
                    CommunityPostCard(post: post)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("评论区")
                            .font(.headline)
                        ForEach(post.mockComments, id: \.self) { comment in
                            Text(comment)
                                .leafyBody()
                                .foregroundStyle(AppTheme.secondaryText)
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .leafyCardStyle()
                        }
                    }
                }
                .padding(AppSpacing.page)
            }
            .background(LeafyPageBackground())
            .navigationTitle("帖子详情")
            .leafyInlineNavigationTitle()
        }
    }
}

struct TeacherDetailSheet: View {
    @Environment(\.leafyLanguage) private var leafyLanguage
    @Environment(\.leafyDependencies) private var dependencies
    @State private var summary: TeacherRatingSummary
    @State private var selectedStars: Int
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var operationAlert: LeafyOperationAlert?

    let onUpdate: (TeacherRatingSummary) -> Void

    private var teacher: TeacherProfile {
        summary.teacher
    }

    private var communityAccessGate: CommunityAccessGate {
        CommunityAccessGate(termsChecker: dependencies.communityRepository)
    }

    init(summary: TeacherRatingSummary, onUpdate: @escaping (TeacherRatingSummary) -> Void) {
        _summary = State(initialValue: summary)
        _selectedStars = State(initialValue: summary.myRating?.stars ?? 0)
        self.onUpdate = onUpdate
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.card) {
                    TeacherCard(summary: summary)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("评分分布")
                            .leafyHeadline()
                            .foregroundStyle(AppTheme.primaryText)

                        ForEach((1...5).reversed(), id: \.self) { stars in
                            TeacherRatingDistributionRow(
                                stars: stars,
                                count: teacher.ratingCountsByStars[stars] ?? 0,
                                total: teacher.ratingCount
                            )
                        }
                    }
                    .padding(18)
                    .leafyCardStyle()

                    VStack(alignment: .leading, spacing: 14) {
                        Text("我的评分")
                            .leafyHeadline()
                            .foregroundStyle(AppTheme.primaryText)

                        TeacherStarPicker(selection: $selectedStars)

                        if let myRating = summary.myRating {
                            Text("当前已评 \(myRating.stars) 星，可直接修改。")
                                .leafyBody()
                                .foregroundStyle(AppTheme.secondaryText)
                        } else {
                            Text("每位老师每个账号只保留一条评分记录。")
                                .leafyBody()
                                .foregroundStyle(AppTheme.secondaryText)
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .leafyBody()
                                .foregroundStyle(AppTheme.danger)
                        }

                        Button {
                            Task { await submitRating() }
                        } label: {
                            HStack(spacing: 8) {
                                if isSaving {
                                    ProgressView()
                                        .tint(.white)
                                }
                                Text(summary.myRating == nil ? "提交评分" : "更新评分")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundStyle(.white)
                            .background(
                                Capsule()
                                    .fill(selectedStars == 0 ? AppTheme.tertiaryText : AppTheme.accent)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(selectedStars == 0 || isSaving)
                    }
                    .padding(18)
                    .leafyCardStyle()
                }
                .padding(AppSpacing.page)
            }
            .background(LeafyPageBackground())
            .navigationTitle(teacher.name)
            .leafyInlineNavigationTitle()
            .leafyOperationAlert($operationAlert)
        }
    }

    @MainActor
    private func submitRating() async {
        guard selectedStars > 0 else { return }

        isSaving = true
        defer { isSaving = false }

        if ReviewDemoMode.isEnabled {
            let updatedSummary = ReviewDemoDataSeeder.updatedTeacherSummary(teacherID: teacher.id, stars: selectedStars)
            summary = updatedSummary
            selectedStars = updatedSummary.myRating?.stars ?? selectedStars
            errorMessage = nil
            onUpdate(updatedSummary)
            operationAlert = .success(L10n.text("评分已保存！", language: leafyLanguage))
            return
        }

        switch await communityAccessGate.evaluate(.rating) {
        case .allowed:
            break
        case .requiresProfileCompletion, .requiresTermsAcceptance:
            break
        case .failed(let message):
            errorMessage = message
            return
        }

        do {
            let updatedSummary = try await dependencies.communityActivityRepository.submitTeacherRating(
                teacherID: teacher.id,
                stars: selectedStars
            )
            summary = updatedSummary
            selectedStars = updatedSummary.myRating?.stars ?? selectedStars
            errorMessage = nil
            onUpdate(updatedSummary)
            operationAlert = .success(L10n.text("评分已保存！", language: leafyLanguage))
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct CourseRatingDetailSheet: View {
    @Environment(\.leafyLanguage) private var leafyLanguage
    @Environment(\.leafyDependencies) private var dependencies
    @State private var summary: CourseRatingSummary
    @State private var selectedStars: Int
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var operationAlert: LeafyOperationAlert?

    let onUpdate: (CourseRatingSummary) -> Void

    private var course: CourseProfile {
        summary.course
    }

    private var communityAccessGate: CommunityAccessGate {
        CommunityAccessGate(termsChecker: dependencies.communityRepository)
    }

    init(summary: CourseRatingSummary, onUpdate: @escaping (CourseRatingSummary) -> Void) {
        _summary = State(initialValue: summary)
        _selectedStars = State(initialValue: summary.myRating?.stars ?? 0)
        self.onUpdate = onUpdate
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.card) {
                    CourseCard(summary: summary)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("评分分布")
                            .leafyHeadline()
                            .foregroundStyle(AppTheme.primaryText)

                        ForEach((1...5).reversed(), id: \.self) { stars in
                            CourseRatingDistributionRow(
                                stars: stars,
                                count: course.ratingCountsByStars[stars] ?? 0,
                                total: course.ratingCount
                            )
                        }
                    }
                    .padding(18)
                    .leafyCardStyle()

                    VStack(alignment: .leading, spacing: 14) {
                        Text("我的评分")
                            .leafyHeadline()
                            .foregroundStyle(AppTheme.primaryText)

                        CourseStarPicker(selection: $selectedStars)

                        if let myRating = summary.myRating {
                            Text("当前已评 \(myRating.stars) 星，可直接修改。")
                                .leafyBody()
                                .foregroundStyle(AppTheme.secondaryText)
                        } else {
                            Text("每门课程每个账号只保留一条评分记录。")
                                .leafyBody()
                                .foregroundStyle(AppTheme.secondaryText)
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .leafyBody()
                                .foregroundStyle(AppTheme.danger)
                        }

                        Button {
                            Task { await submitRating() }
                        } label: {
                            HStack(spacing: 8) {
                                if isSaving {
                                    ProgressView()
                                        .tint(.white)
                                }
                                Text(summary.myRating == nil ? "提交评分" : "更新评分")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundStyle(.white)
                            .background(
                                Capsule()
                                    .fill(selectedStars == 0 ? AppTheme.tertiaryText : AppTheme.accent)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(selectedStars == 0 || isSaving)
                    }
                    .padding(18)
                    .leafyCardStyle()
                }
                .padding(AppSpacing.page)
            }
            .background(LeafyPageBackground())
            .navigationTitle(course.name)
            .leafyInlineNavigationTitle()
            .leafyOperationAlert($operationAlert)
        }
    }

    @MainActor
    private func submitRating() async {
        guard selectedStars > 0 else { return }

        isSaving = true
        defer { isSaving = false }

        if ReviewDemoMode.isEnabled {
            let updatedSummary = ReviewDemoDataSeeder.updatedCourseSummary(courseID: course.id, stars: selectedStars)
            summary = updatedSummary
            selectedStars = updatedSummary.myRating?.stars ?? selectedStars
            errorMessage = nil
            onUpdate(updatedSummary)
            operationAlert = .success(L10n.text("评分已保存！", language: leafyLanguage))
            return
        }

        switch await communityAccessGate.evaluate(.rating) {
        case .allowed:
            break
        case .requiresProfileCompletion, .requiresTermsAcceptance:
            break
        case .failed(let message):
            errorMessage = message
            return
        }

        do {
            let updatedSummary = try await dependencies.communityActivityRepository.submitCourseRating(
                courseID: course.id,
                stars: selectedStars
            )
            summary = updatedSummary
            selectedStars = updatedSummary.myRating?.stars ?? selectedStars
            errorMessage = nil
            onUpdate(updatedSummary)
            operationAlert = .success(L10n.text("评分已保存！", language: leafyLanguage))
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct DishDetailSheet: View {
    @Environment(\.leafyLanguage) private var leafyLanguage
    @Environment(\.leafyDependencies) private var dependencies
    @State private var summary: DishRatingSummary
    @State private var selectedStars: Int
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var operationAlert: LeafyOperationAlert?

    let onUpdate: (DishRatingSummary) -> Void

    private var dish: DishProfile {
        summary.dish
    }

    private var communityAccessGate: CommunityAccessGate {
        CommunityAccessGate(termsChecker: dependencies.communityRepository)
    }

    init(summary: DishRatingSummary, onUpdate: @escaping (DishRatingSummary) -> Void) {
        _summary = State(initialValue: summary)
        _selectedStars = State(initialValue: summary.myRating?.stars ?? 0)
        self.onUpdate = onUpdate
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.card) {
                    DishCard(summary: summary)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("评分分布")
                            .leafyHeadline()
                            .foregroundStyle(AppTheme.primaryText)

                        ForEach((1...5).reversed(), id: \.self) { stars in
                            DishRatingDistributionRow(
                                stars: stars,
                                count: dish.ratingCountsByStars[stars] ?? 0,
                                total: dish.ratingCount
                            )
                        }
                    }
                    .padding(18)
                    .leafyCardStyle()

                    VStack(alignment: .leading, spacing: 14) {
                        Text("我的评分")
                            .leafyHeadline()
                            .foregroundStyle(AppTheme.primaryText)

                        DishStarPicker(selection: $selectedStars)

                        if let myRating = summary.myRating {
                            Text("当前已评 \(myRating.stars) 星，可直接修改。")
                                .leafyBody()
                                .foregroundStyle(AppTheme.secondaryText)
                        } else {
                            Text("每道菜每个账号只保留一条评分记录。")
                                .leafyBody()
                                .foregroundStyle(AppTheme.secondaryText)
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .leafyBody()
                                .foregroundStyle(AppTheme.danger)
                        }

                        Button {
                            Task { await submitRating() }
                        } label: {
                            HStack(spacing: 8) {
                                if isSaving {
                                    ProgressView()
                                        .tint(.white)
                                }
                                Text(summary.myRating == nil ? "提交评分" : "更新评分")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundStyle(.white)
                            .background(
                                Capsule()
                                    .fill(selectedStars == 0 ? AppTheme.tertiaryText : AppTheme.accent)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(selectedStars == 0 || isSaving)
                    }
                    .padding(18)
                    .leafyCardStyle()
                }
                .padding(AppSpacing.page)
            }
            .background(LeafyPageBackground())
            .navigationTitle(dish.name)
            .leafyInlineNavigationTitle()
            .leafyOperationAlert($operationAlert)
        }
    }

    @MainActor
    private func submitRating() async {
        guard selectedStars > 0 else { return }

        isSaving = true
        defer { isSaving = false }

        if ReviewDemoMode.isEnabled {
            let updatedSummary = ReviewDemoDataSeeder.updatedDishSummary(dishID: dish.id, stars: selectedStars)
            summary = updatedSummary
            selectedStars = updatedSummary.myRating?.stars ?? selectedStars
            errorMessage = nil
            onUpdate(updatedSummary)
            operationAlert = .success(L10n.text("评分已保存！", language: leafyLanguage))
            return
        }

        switch await communityAccessGate.evaluate(.rating) {
        case .allowed:
            break
        case .requiresProfileCompletion, .requiresTermsAcceptance:
            break
        case .failed(let message):
            errorMessage = message
            return
        }

        do {
            let updatedSummary = try await dependencies.communityActivityRepository.submitDishRating(
                dishID: dish.id,
                stars: selectedStars
            )
            summary = updatedSummary
            selectedStars = updatedSummary.myRating?.stars ?? selectedStars
            errorMessage = nil
            onUpdate(updatedSummary)
            operationAlert = .success(L10n.text("评分已保存！", language: leafyLanguage))
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct TeacherRatingDistributionRow: View {
    let stars: Int
    let count: Int
    let total: Int

    private var progress: Double {
        guard total > 0 else { return 0 }
        return Double(count) / Double(total)
    }

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                Text("\(stars)")
                    .microCaption()
                    .foregroundStyle(AppTheme.secondaryText)
                Image(systemName: "star.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.yellow)
            }
            .frame(width: 34, alignment: .leading)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AppTheme.fill)
                    Capsule()
                        .fill(AppTheme.accent)
                        .frame(width: max(4, proxy.size.width * progress))
                        .opacity(count == 0 ? 0 : 1)
                }
            }
            .frame(height: 8)

            Text("\(count)")
                .microCaption()
                .foregroundStyle(AppTheme.tertiaryText)
                .frame(width: 28, alignment: .trailing)
        }
    }
}

private struct CourseRatingDistributionRow: View {
    let stars: Int
    let count: Int
    let total: Int

    var body: some View {
        TeacherRatingDistributionRow(stars: stars, count: count, total: total)
    }
}

private struct DishRatingDistributionRow: View {
    let stars: Int
    let count: Int
    let total: Int

    var body: some View {
        TeacherRatingDistributionRow(stars: stars, count: count, total: total)
    }
}

private struct TeacherStarPicker: View {
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...5, id: \.self) { stars in
                Button {
                    selection = stars
                } label: {
                    Image(systemName: stars <= selection ? "star.fill" : "star")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(stars <= selection ? .yellow : AppTheme.tertiaryText)
                        .frame(width: 42, height: 42)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(stars) 星")
            }
        }
    }
}

private struct CourseStarPicker: View {
    @Binding var selection: Int

    var body: some View {
        TeacherStarPicker(selection: $selection)
    }
}

private struct DishStarPicker: View {
    @Binding var selection: Int

    var body: some View {
        TeacherStarPicker(selection: $selection)
    }
}

private struct CommunityMockPost: Identifiable {
    let id: Int
    let author: String
    let title: String
    let body: String
    let timestamp: String
    let likes: Int
    let comments: Int
    let tag: String
    let avatarColor: Color
    let photoLabels: [String]
    let mockComments: [String]

    static let samples: [CommunityMockPost] = [
        CommunityMockPost(
            id: 1,
            author: "匿名同学",
            title: "食堂晚饭有没有稳定不踩雷的窗口？",
            body: "最近想固定一个晚饭窗口，不想每天随机试错。有没有那种价格稳定、出餐快、晚上也不容易翻车的推荐？",
            timestamp: "今天 18:42",
            likes: 23,
            comments: 8,
            tag: "食堂",
            avatarColor: AppTheme.featureTints[0],
            photoLabels: ["晚饭", "北林", "推荐"],
            mockComments: ["一食堂二层的烤盘饭比较稳。", "三食堂窗口更新快，晚上选择多。"]
        ),
        CommunityMockPost(
            id: 2,
            author: "林学 23 级",
            title: "图书馆闭馆前一小时人会突然少很多吗？",
            body: "想找一个相对安静的时间段复习，白天人流太大。有人长期蹲馆的话，可以说一下晚上座位变化吗？",
            timestamp: "昨天 21:15",
            likes: 16,
            comments: 5,
            tag: "自习",
            avatarColor: AppTheme.featureTints[2],
            photoLabels: [],
            mockComments: ["九点以后会明显松一点。", "考试周不一定，平时是这样的。"]
        )
    ]
}
