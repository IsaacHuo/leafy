import Foundation
import SwiftData

enum SchoolDataSyncOutcome: Equatable {
    case success(String)
    case needsLogin
    case needsReauthentication(SchoolReauthenticationContext)
}

enum SchoolDataRefreshScope: String, CaseIterable, Sendable {
    case timetable
    case grades
    case gradeSupplemental
    case exams
    case teachingPlan
    case trainingProgram
    case all
}

struct SchoolDataRefreshEvent: Sendable {
    let scopes: Set<SchoolDataRefreshScope>

    init(_ scopes: Set<SchoolDataRefreshScope>) {
        self.scopes = scopes
    }

    init(_ scope: SchoolDataRefreshScope) {
        self.init([scope])
    }

    func contains(_ scope: SchoolDataRefreshScope) -> Bool {
        scopes.contains(.all) || scopes.contains(scope)
    }
}

extension Notification.Name {
    static let schoolDataDidRefresh = Notification.Name("SchoolDataDidRefresh")
}

enum SchoolDataRefreshNotifier {
    static func post(_ scopes: Set<SchoolDataRefreshScope>) {
        guard !scopes.isEmpty else { return }
        NotificationCenter.default.post(
            name: .schoolDataDidRefresh,
            object: SchoolDataRefreshEvent(scopes)
        )
    }

    static func post(_ scope: SchoolDataRefreshScope) {
        post([scope])
    }
}

@MainActor
enum SchoolDataSyncService {
    static func syncAll(
        modelContext: ModelContext,
        language: AppLanguagePreference,
        userInitiated: Bool = false
    ) async -> SchoolDataSyncOutcome {
        let networkManager = ActiveCampusContext.networkManager

        if ReviewDemoMode.isEnabled {
            ReviewDemoDataSeeder.seed(using: modelContext)
            LeafyWidgetSnapshotBuilder.publish(from: modelContext, isAuthenticated: true)
            return .success(L10n.text("已刷新演示学校数据。社区数据仍使用真实服务。", language: language))
        }

        if ActiveCampusContext.identity?.isCustom == true {
            return .success(L10n.text("通用入口不连接教务系统。请在课表、成绩和考试页面使用“导入”更新本地数据。", language: language))
        }

        guard networkManager.hasCachedIdentity else {
            return .needsLogin
        }

        guard networkManager.isLoggedIn else {
            return .needsReauthentication(.schoolDataSync)
        }

        let semesterConfig = await SemesterConfig.refreshRemoteIfAvailable(force: true)

        var results: [String] = []
        var refreshedScopes: Set<SchoolDataRefreshScope> = []
        var parsedGrades: [Grade]?
        var gradeRankingsToSave: [GradeRankingRecord]?
        var gradeCreditSummaryToSave: GradeCreditSummary?
        var examScheduleToSave: [ExamArrangement]?
        var teachingPlanToSave: [TeachingPlanSection]?
        var trainingProgramToSave: TrainingProgramDocument?

        do {
            let html = try await networkManager.fetchTimetable()
            let parsed = try HTMLParser.parseTimetable(html: html)
            try persistTimetable(
                parsed,
                semesterID: semesterConfig.semesterID,
                modelContext: modelContext
            )
            results.append(L10n.text("课表 %d 门", language: language, parsed.count))
            if await TimetableSharingService.shared.publishExistingSnapshotIfNeeded(
                courses: parsed.map(SharedTimetableCourse.init(course:))
            ) {
                results.append(L10n.text("共享课表已更新", language: language))
            }
        } catch {
            modelContext.rollback()
            if requiresReauthentication(error, userInitiated: userInitiated) {
                return .needsReauthentication(.schoolDataSync)
            }
            TimetableCacheMetadata.lastFailureMessage = error.localizedDescription
            results.append(L10n.text("课表失败", language: language))
        }

        if networkManager.currentPortal == .undergraduate {
            do {
                let html = try await networkManager.fetchGrades()
                let parsed = try HTMLParser.parseGrades(html: html)
                let rankings = (try? HTMLParser.parseGradeRankings(html: html)) ?? []
                let creditSummary = try? HTMLParser.parseGradeCreditSummary(html: html)
                if !rankings.isEmpty {
                    gradeRankingsToSave = rankings
                }
                if let creditSummary {
                    gradeCreditSummaryToSave = creditSummary
                }
                parsedGrades = parsed
                results.append(L10n.text("成绩 %d 条", language: language, parsed.count))
            } catch {
                if requiresReauthentication(error, userInitiated: userInitiated) {
                    return .needsReauthentication(.schoolDataSync)
                }
                results.append(L10n.text("成绩失败", language: language))
            }

            do {
                let html = try await networkManager.fetchGradeRankings()
                let parsed = try HTMLParser.parseGradeRankings(html: html)
                gradeRankingsToSave = parsed
                if let creditSummary = try? HTMLParser.parseGradeCreditSummary(html: html) {
                    gradeCreditSummaryToSave = creditSummary
                }
                results.append(L10n.text("排名 %d 条", language: language, parsed.count))
            } catch {
                if requiresReauthentication(error, userInitiated: userInitiated) {
                    return .needsReauthentication(.schoolDataSync)
                }
                results.append(L10n.text("排名未开放", language: language))
            }

            do {
                let html = try await networkManager.fetchExamSchedule()
                let parsed = try HTMLParser.parseExams(html: html)
                examScheduleToSave = parsed
                results.append(L10n.text("考试 %d 条", language: language, parsed.count))
            } catch {
                if requiresReauthentication(error, userInitiated: userInitiated) {
                    return .needsReauthentication(.schoolDataSync)
                }
                results.append(L10n.text("考试失败", language: language))
            }

            do {
                let html = try await networkManager.fetchTeachingPlan()
                let parsed = try HTMLParser.parseTeachingPlan(html: html)
                teachingPlanToSave = parsed
                results.append(L10n.text("教学计划 %d 学期", language: language, parsed.count))
            } catch {
                if requiresReauthentication(error, userInitiated: userInitiated) {
                    return .needsReauthentication(.schoolDataSync)
                }
                results.append(L10n.text("教学计划失败", language: language))
            }

            do {
                let html = try await networkManager.fetchGraduationRequirements()
                let document = try HTMLParser.parseTrainingProgram(html: html)
                trainingProgramToSave = document
                results.append(L10n.text("培养方案 %d 类", language: language, document.creditRequirements.count))
            } catch {
                if requiresReauthentication(error, userInitiated: userInitiated) {
                    return .needsReauthentication(.schoolDataSync)
                }
                results.append(L10n.text("培养方案失败", language: language))
            }
        }

        if let parsedGrades, !parsedGrades.isEmpty {
            for grade in fetch(Grade.self, from: modelContext) {
                modelContext.delete(grade)
            }
            for grade in parsedGrades {
                modelContext.insert(grade)
            }
            SchoolDataCache.markGradeDetailsSynced()
            refreshedScopes.insert(.grades)
        }

        if let gradeRankingsToSave {
            SchoolDataCache.saveGradeRankings(gradeRankingsToSave, notifies: false)
            refreshedScopes.insert(.gradeSupplemental)
        }
        if let gradeCreditSummaryToSave {
            SchoolDataCache.saveGradeCreditSummary(gradeCreditSummaryToSave, notifies: false)
            refreshedScopes.insert(.gradeSupplemental)
        }
        if let examScheduleToSave {
            SchoolDataCache.saveExamSchedule(examScheduleToSave, notifies: false)
            refreshedScopes.insert(.exams)
        }
        if let teachingPlanToSave {
            SchoolDataCache.saveTeachingPlan(teachingPlanToSave, notifies: false)
            refreshedScopes.insert(.teachingPlan)
        }
        if let trainingProgramToSave {
            SchoolDataCache.saveTrainingProgram(trainingProgramToSave, notifies: false)
            refreshedScopes.insert(.trainingProgram)
        }

        try? modelContext.save()
        if examScheduleToSave != nil {
            LeafyWidgetSnapshotBuilder.publish(from: modelContext, isAuthenticated: true)
        }
        SchoolDataRefreshNotifier.post(refreshedScopes)

        return .success(
            L10n.text(
                "同步完成：%@。",
                language: language,
                results.joined(separator: L10n.text("，", language: language))
            )
        )
    }

    private static func persistTimetable(
        _ courses: [Course],
        semesterID: String,
        modelContext: ModelContext
    ) throws {
        for course in fetch(Course.self, from: modelContext) {
            modelContext.delete(course)
        }
        for course in courses {
            modelContext.insert(course)
        }
        try modelContext.save()

        let now = Date()
        TimetableCacheMetadata.lastSyncAt = now
        TimetableCacheMetadata.lastFailureMessage = nil
        TimetableCacheMetadata.lastSyncedSemesterID = semesterID
        AppStoreReviewCoordinator.recordSuccessfulSync(kind: .timetable, date: now)
        LeafyWidgetSnapshotBuilder.publish(from: modelContext, isAuthenticated: true)
        SchoolDataRefreshNotifier.post(.timetable)
    }

    private static func requiresReauthentication(
        _ error: Error,
        userInitiated: Bool
    ) -> Bool {
        userInitiated
            ? SchoolReauthentication.shouldPromptForUserInitiatedAccess(error)
            : SchoolReauthentication.requiresReauthentication(error)
    }

    private static func fetch<T: PersistentModel>(_ model: T.Type, from modelContext: ModelContext) -> [T] {
        (try? modelContext.fetch(FetchDescriptor<T>())) ?? []
    }
}
