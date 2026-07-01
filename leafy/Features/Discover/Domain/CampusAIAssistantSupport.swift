import Foundation
import Security
import SwiftData
import Supabase

nonisolated enum CampusAIMessageRole: String, Codable, Hashable {
    case user
    case assistant
}

nonisolated enum CampusAIActionStatus: String, Codable, Hashable {
    case pending
    case completed
    case cancelled
    case failed
}

nonisolated enum CampusAIActionKind: String, Codable, Hashable {
    case openAcademicRoute
    case createCountdown
    case createTimetableReminder

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        switch rawValue {
        case Self.openAcademicRoute.rawValue, "open_academic_route":
            self = .openAcademicRoute
        case Self.createCountdown.rawValue, "create_countdown":
            self = .createCountdown
        case Self.createTimetableReminder.rawValue, "create_timetable_reminder":
            self = .createTimetableReminder
        default:
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported AI action kind.")
        }
    }
}

nonisolated enum CampusAIAcademicRouteID: String, Codable, CaseIterable, Hashable {
    case grades
    case gradeAnalytics
    case examSchedule
    case scheduleReports
    case customCountdowns
    case teachingPlan
    case trainingProgram

    var detailRoute: AcademicDetailRoute {
        switch self {
        case .grades: return .grades
        case .gradeAnalytics: return .gradeAnalytics
        case .examSchedule: return .examSchedule
        case .scheduleReports: return .scheduleReports
        case .customCountdowns: return .customCountdowns
        case .teachingPlan: return .teachingPlan
        case .trainingProgram: return .trainingProgram
        }
    }

    var title: String {
        switch self {
        case .grades: return "成绩查询"
        case .gradeAnalytics: return "成绩分析"
        case .examSchedule: return "考试与日程"
        case .scheduleReports: return "日程推送"
        case .customCountdowns: return "自定义倒计时"
        case .teachingPlan: return "教学计划"
        case .trainingProgram: return "培养方案"
        }
    }
}

nonisolated struct CampusAIActionPayload: Codable, Hashable {
    var route: String?
    var countdownTitle: String?
    var targetDate: String?
    var week: Int?
    var dayOfWeek: Int?
    var period: Int?
    var endPeriod: Int?
    var title: String?
    var location: String?
    var note: String?
    var minutesBefore: Int?

    init(
        route: String? = nil,
        countdownTitle: String? = nil,
        targetDate: String? = nil,
        week: Int? = nil,
        dayOfWeek: Int? = nil,
        period: Int? = nil,
        endPeriod: Int? = nil,
        title: String? = nil,
        location: String? = nil,
        note: String? = nil,
        minutesBefore: Int? = nil
    ) {
        self.route = route
        self.countdownTitle = countdownTitle
        self.targetDate = targetDate
        self.week = week
        self.dayOfWeek = dayOfWeek
        self.period = period
        self.endPeriod = endPeriod
        self.title = title
        self.location = location
        self.note = note
        self.minutesBefore = minutesBefore
    }
}

nonisolated struct CampusAIActionDraft: Identifiable, Codable, Hashable {
    var id: String
    var kind: CampusAIActionKind
    var title: String
    var detail: String
    var payload: CampusAIActionPayload

    init(
        id: String = UUID().uuidString,
        kind: CampusAIActionKind,
        title: String,
        detail: String = "",
        payload: CampusAIActionPayload
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.payload = payload
    }

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case title
        case detail
        case payload
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        kind = try container.decode(CampusAIActionKind.self, forKey: .kind)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        detail = try container.decodeIfPresent(String.self, forKey: .detail) ?? ""
        payload = try container.decodeIfPresent(CampusAIActionPayload.self, forKey: .payload) ?? CampusAIActionPayload()
    }
}

nonisolated enum CampusAIActionValidation {
    static func validated(_ drafts: [CampusAIActionDraft]) -> [CampusAIActionDraft] {
        drafts.compactMap(validate)
    }

    static func validate(_ draft: CampusAIActionDraft) -> CampusAIActionDraft? {
        switch draft.kind {
        case .openAcademicRoute:
            return validateOpenRoute(draft)
        case .createCountdown:
            return validateCountdown(draft)
        case .createTimetableReminder:
            return validateTimetableReminder(draft)
        }
    }

    static func routeID(for draft: CampusAIActionDraft) -> CampusAIAcademicRouteID? {
        guard let route = draft.payload.route?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }
        return CampusAIAcademicRouteID(rawValue: route)
    }

    static func countdownDate(for draft: CampusAIActionDraft) -> Date? {
        parseDate(draft.payload.targetDate)
    }

    private static func validateOpenRoute(_ draft: CampusAIActionDraft) -> CampusAIActionDraft? {
        guard let routeID = routeID(for: draft) else { return nil }
        var normalized = draft
        normalized.title = normalized.title.nonEmptyTrimmed ?? "打开\(routeID.title)"
        normalized.payload.route = routeID.rawValue
        return normalized
    }

    private static func validateCountdown(_ draft: CampusAIActionDraft) -> CampusAIActionDraft? {
        let title = draft.payload.countdownTitle?.nonEmptyTrimmed ?? draft.payload.title?.nonEmptyTrimmed
        guard let title, parseDate(draft.payload.targetDate) != nil else {
            return nil
        }
        var normalized = draft
        normalized.title = normalized.title.nonEmptyTrimmed ?? "创建倒计时"
        normalized.payload.countdownTitle = title
        normalized.payload.title = nil
        return normalized
    }

    private static func validateTimetableReminder(_ draft: CampusAIActionDraft) -> CampusAIActionDraft? {
        guard let week = draft.payload.week,
              (1...SemesterConfig.supportedWeeks).contains(week),
              let day = draft.payload.dayOfWeek,
              (1...7).contains(day),
              let period = draft.payload.period,
              TimetablePeriodSchedule.slot(for: period) != nil,
              let title = draft.payload.title?.nonEmptyTrimmed
        else {
            return nil
        }
        var normalized = draft
        normalized.title = normalized.title.nonEmptyTrimmed ?? "创建课表提醒"
        normalized.payload.week = week
        normalized.payload.dayOfWeek = day
        normalized.payload.period = period
        if let endPeriod = normalized.payload.endPeriod,
           TimetablePeriodSchedule.slot(for: endPeriod) == nil {
            normalized.payload.endPeriod = nil
        }
        normalized.payload.title = title
        normalized.payload.minutesBefore = max(0, normalized.payload.minutesBefore ?? 0)
        return normalized
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        if let date = ISO8601DateFormatter().date(from: value) {
            return date
        }
        return queryDateFormatter().date(from: value)
    }

    private static func queryDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
}

nonisolated struct CampusAIChatMessage: Codable, Hashable {
    let role: CampusAIMessageRole
    let text: String
}

nonisolated enum CampusAIProviderID: String, Codable, CaseIterable, Hashable, Identifiable {
    case deepSeek = "deepseek"

    var id: String { rawValue }
}

nonisolated enum CampusAIServiceMode: String, Codable, CaseIterable, Hashable, Identifiable {
    case ownAPIKey
    case leafyManaged

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ownAPIKey:
            return "使用已有 API Key"
        case .leafyManaged:
            return "Leafy 托管服务"
        }
    }

    var shortTitle: String {
        switch self {
        case .ownAPIKey:
            return "DeepSeek Key"
        case .leafyManaged:
            return "Leafy 托管"
        }
    }
}

nonisolated struct CampusAIProviderDescriptor: Hashable, Identifiable {
    let id: CampusAIProviderID
    let displayName: String
    let modelIdentifier: String
    let modelDisplayName: String
    let baseURLString: String
}

nonisolated enum CampusAIProviderCatalog {
    static let deepSeek = CampusAIProviderDescriptor(
        id: .deepSeek,
        displayName: "DeepSeek",
        modelIdentifier: "deepseek-v4-flash",
        modelDisplayName: "DeepSeek V4 Flash",
        baseURLString: "https://api.deepseek.com"
    )
    static let all = [deepSeek]
    static let defaultProvider = deepSeek

    static func provider(for id: CampusAIProviderID) -> CampusAIProviderDescriptor {
        all.first(where: { $0.id == id }) ?? defaultProvider
    }
}

nonisolated struct CampusAIContextSettings: Codable, Hashable {
    var includesTimetable: Bool
    var includesGrades: Bool
    var includesExamsAndPlans: Bool
    var includesLearningWorkspace: Bool
    var includesPostgraduateAndCareer: Bool
    var includesHonorsFitnessQuality: Bool
    var includesMedicalLedger: Bool
    var includesCommunityCache: Bool

    static let defaultValue = CampusAIContextSettings(
        includesTimetable: true,
        includesGrades: true,
        includesExamsAndPlans: true,
        includesLearningWorkspace: true,
        includesPostgraduateAndCareer: true,
        includesHonorsFitnessQuality: true,
        includesMedicalLedger: true,
        includesCommunityCache: true
    )
}

nonisolated struct CampusAIUserSettings: Codable, Hashable {
    var serviceMode: CampusAIServiceMode
    var selectedProviderID: CampusAIProviderID
    var systemPrompt: String
    var contextSettings: CampusAIContextSettings

    static var defaultValue: CampusAIUserSettings {
        CampusAIUserSettings(
            serviceMode: CampusAIKeychainStore.hasAPIKey() ? .ownAPIKey : .leafyManaged,
            selectedProviderID: CampusAIProviderCatalog.defaultProvider.id,
            systemPrompt: CampusAISettingsStore.defaultSystemPrompt,
            contextSettings: .defaultValue
        )
    }

    init(
        serviceMode: CampusAIServiceMode = .leafyManaged,
        selectedProviderID: CampusAIProviderID = CampusAIProviderCatalog.defaultProvider.id,
        systemPrompt: String,
        contextSettings: CampusAIContextSettings
    ) {
        self.serviceMode = serviceMode
        self.selectedProviderID = selectedProviderID
        self.systemPrompt = systemPrompt
        self.contextSettings = contextSettings
    }

    enum CodingKeys: String, CodingKey {
        case serviceMode
        case selectedProviderID
        case systemPrompt
        case contextSettings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        serviceMode = try container.decodeIfPresent(CampusAIServiceMode.self, forKey: .serviceMode) ??
            (CampusAIKeychainStore.hasAPIKey() ? .ownAPIKey : .leafyManaged)
        selectedProviderID = try container.decodeIfPresent(CampusAIProviderID.self, forKey: .selectedProviderID) ??
            CampusAIProviderCatalog.defaultProvider.id
        systemPrompt = try container.decodeIfPresent(String.self, forKey: .systemPrompt) ??
            CampusAISettingsStore.defaultSystemPrompt
        contextSettings = try container.decodeIfPresent(CampusAIContextSettings.self, forKey: .contextSettings) ??
            .defaultValue
    }

    var selectedProvider: CampusAIProviderDescriptor {
        CampusAIProviderCatalog.provider(for: selectedProviderID)
    }

    var effectiveSystemPrompt: String {
        let trimmed = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? CampusAISettingsStore.defaultSystemPrompt : String(trimmed.prefix(3000))
    }
}

nonisolated enum CampusAISettingsStore {
    static let defaultSystemPrompt = """
    请用中文回答，优先使用清晰的 Markdown 结构。可以围绕校园学习、生活安排和个人事项整理给出建议，但要明确区分本机上下文、一般常识和不确定内容。回答要具体、可执行，必要时用标题、列表和加粗来组织重点。若上下文不足，请直接说明缺少哪些本机数据，不要编造。
    """

    private static let storageKey = "campusAI.userSettings.v2"
    private static let legacyStorageKey = "campusAI.userSettings.v1"

    static func load(userDefaults: UserDefaults = .standard) -> CampusAIUserSettings {
        if let data = userDefaults.data(forKey: storageKey),
           let settings = try? JSONDecoder().decode(CampusAIUserSettings.self, from: data) {
            return settings
        }

        guard let legacyData = userDefaults.data(forKey: legacyStorageKey),
              let legacySettings = try? JSONDecoder().decode(LegacyUserSettings.self, from: legacyData)
        else {
            return .defaultValue
        }
        let migrated = CampusAIUserSettings(
            serviceMode: CampusAIKeychainStore.hasAPIKey() ? .ownAPIKey : .leafyManaged,
            systemPrompt: legacySettings.systemPrompt ?? defaultSystemPrompt,
            contextSettings: legacySettings.contextSettings ?? .defaultValue
        )
        save(migrated, userDefaults: userDefaults)
        userDefaults.removeObject(forKey: legacyStorageKey)
        return migrated
    }

    static func save(_ settings: CampusAIUserSettings, userDefaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        userDefaults.set(data, forKey: storageKey)
    }

    static func reset(userDefaults: UserDefaults = .standard) -> CampusAIUserSettings {
        userDefaults.removeObject(forKey: storageKey)
        userDefaults.removeObject(forKey: legacyStorageKey)
        return .defaultValue
    }

    private struct LegacyUserSettings: Decodable {
        let systemPrompt: String?
        let contextSettings: CampusAIContextSettings?
    }
}

nonisolated struct CampusAIRequest: Codable, Hashable {
    let requestID: UUID
    let message: String
    let context: CampusAIContextPayload
    let recentMessages: [CampusAIChatMessage]
    let model: String
    let userSystemPrompt: String
    let contextSettings: CampusAIContextSettings

    init(
        requestID: UUID = UUID(),
        message: String,
        context: CampusAIContextPayload,
        recentMessages: [CampusAIChatMessage],
        model: String = CampusAIProviderCatalog.defaultProvider.modelIdentifier,
        userSystemPrompt: String = CampusAISettingsStore.defaultSystemPrompt,
        contextSettings: CampusAIContextSettings = .defaultValue
    ) {
        self.requestID = requestID
        self.message = message
        self.context = context
        self.recentMessages = recentMessages
        self.model = model
        self.userSystemPrompt = String(userSystemPrompt.prefix(3000))
        self.contextSettings = contextSettings
    }
}

nonisolated struct CampusAIResponse: Codable, Hashable {
    var answer: String
    var reasoning: String
    var finishReason: String?
    var suggestedTitle: String?
    var summary: String?
    var actions: [CampusAIActionDraft]

    enum CodingKeys: String, CodingKey {
        case answer
        case reasoning
        case finishReason = "finish_reason"
        case suggestedTitle = "suggested_title"
        case summary
        case actions
    }

    init(
        answer: String,
        reasoning: String = "",
        finishReason: String? = nil,
        suggestedTitle: String? = nil,
        summary: String? = nil,
        actions: [CampusAIActionDraft] = []
    ) {
        self.answer = answer
        self.reasoning = reasoning
        self.finishReason = finishReason
        self.suggestedTitle = suggestedTitle
        self.summary = summary
        self.actions = actions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        answer = try container.decodeIfPresent(String.self, forKey: .answer) ?? ""
        reasoning = try container.decodeIfPresent(String.self, forKey: .reasoning) ?? ""
        finishReason = try container.decodeIfPresent(String.self, forKey: .finishReason)
        suggestedTitle = try container.decodeIfPresent(String.self, forKey: .suggestedTitle)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        actions = CampusAIActionValidation.validated(
            try container.decodeIfPresent([CampusAIActionDraft].self, forKey: .actions) ?? []
        )
    }
}

nonisolated struct CampusAIQuotaSnapshot: Codable, Hashable {
    var planSource: String
    var limit: Int
    var used: Int
    var remaining: Int
    var resetAt: String
    var status: String

    enum CodingKeys: String, CodingKey {
        case planSource = "plan_source"
        case limit
        case used
        case remaining
        case resetAt = "reset_at"
        case status
    }

    var displayText: String {
        "\(remaining)/\(limit)"
    }
}

nonisolated struct CampusAIContextPayload: Codable, Hashable {
    let generatedAt: String
    let campusID: String
    let campusName: String
    let currentWeek: Int
    let currentDayOfWeek: Int
    let includedScopes: [String]
    let omittedScopes: [String]
    let dataBoundary: [String]
    let sourceStatus: [CampusAIContextSourceStatus]
    let timetable: CampusAITimetableContext
    let exams: [CampusAIExamContext]
    let grades: CampusAIGradeContext
    let teachingPlan: [CampusAITeachingPlanContext]
    let trainingProgram: CampusAITrainingProgramContext?
    let countdowns: [CampusAICountdownContext]
    let learningWorkspace: CampusAILearningWorkspaceContext
    let postgraduateAndCareer: CampusAIPostgraduateCareerContext
    let honorsFitnessQuality: CampusAIHonorsFitnessQualityContext
    let medicalLedger: CampusAIMedicalLedgerContext
    let communityCache: CampusAICommunityCacheContext

    var hasReadableAcademicData: Bool {
        !timetable.today.isEmpty ||
            !timetable.currentWeek.isEmpty ||
            !timetable.allCourses.isEmpty ||
            !exams.isEmpty ||
            grades.courseCount > 0 ||
            !teachingPlan.isEmpty ||
            trainingProgram != nil ||
            !countdowns.isEmpty ||
            learningWorkspace.hasContent ||
            postgraduateAndCareer.hasContent ||
            honorsFitnessQuality.hasContent ||
            medicalLedger.hasContent ||
            communityCache.hasContent
    }
}

nonisolated enum CampusAIContextSourceState: String, Codable, Hashable {
    case available
    case missing
    case disabled
    case localOnly
}

nonisolated struct CampusAIContextSourceStatus: Codable, Hashable {
    let scope: String
    let itemCount: Int
    let lastSyncAt: String?
    let state: CampusAIContextSourceState
    let note: String
}

nonisolated struct CampusAITimetableContext: Codable, Hashable {
    let today: [CampusAICourseContext]
    let currentWeek: [CampusAICourseContext]
    let allCourses: [CampusAICourseContext]
    let courseNotes: [CampusAICourseNoteContext]
    let occurrenceNotes: [CampusAICourseOccurrenceNoteContext]
    let courseReminders: [CampusAICourseReminderContext]
    let cellReminders: [CampusAITimetableCellReminderContext]
    let favoriteClassrooms: [String]
}

nonisolated struct CampusAICourseContext: Codable, Hashable {
    let name: String
    let teacher: String
    let room: String
    let location: String
    let dayOfWeek: Int
    let periods: [Int]
    let weeks: [Int]
}

nonisolated struct CampusAIExamContext: Codable, Hashable {
    let name: String
    let date: String
    let start: String
    let end: String
    let location: String
}

nonisolated struct CampusAIGradeContext: Codable, Hashable {
    let courseCount: Int
    let termCount: Int
    let latestTerm: String?
    let officialGPA: Double?
    let officialWeightedAverage: Double?
    let totalCredits: Double?
    let requiredCredits: Double?
    let publicElectiveCredits: Double?
    let professionalElectiveCredits: Double?
    let recentCourses: [CampusAIGradeCourseContext]
    let allCourses: [CampusAIGradeCourseContext]
    let rankings: [CampusAIGradeRankingContext]
}

nonisolated struct CampusAIGradeCourseContext: Codable, Hashable {
    let term: String
    let name: String
    let credit: String
    let score: String
    let type: String
}

nonisolated struct CampusAITeachingPlanContext: Codable, Hashable {
    let term: String
    let totalCredits: Double
    let courses: [String]
}

nonisolated struct CampusAITrainingProgramContext: Codable, Hashable {
    let title: String
    let sections: [String]
    let creditRequirements: [String]
}

nonisolated struct CampusAICountdownContext: Codable, Hashable {
    let title: String
    let targetDate: String
}

nonisolated struct CampusAICourseNoteContext: Codable, Hashable {
    let courseName: String
    let text: String
    let updatedAt: String
}

nonisolated struct CampusAICourseOccurrenceNoteContext: Codable, Hashable {
    let courseName: String
    let week: Int
    let dayOfWeek: Int
    let text: String
    let updatedAt: String
}

nonisolated struct CampusAICourseReminderContext: Codable, Hashable {
    let courseName: String
    let minutesBefore: Int
    let anchorPeriod: Int?
    let updatedAt: String
}

nonisolated struct CampusAITimetableCellReminderContext: Codable, Hashable {
    let week: Int
    let dayOfWeek: Int
    let period: Int
    let endPeriod: Int?
    let title: String
    let location: String?
    let note: String?
    let minutesBefore: Int
    let updatedAt: String
}

nonisolated struct CampusAIGradeRankingContext: Codable, Hashable {
    let term: String
    let range: String
    let rank: Int?
    let totalCount: Int?
    let percentile: Double?
    let metric: String
}

nonisolated struct CampusAILearningWorkspaceContext: Codable, Hashable {
    let projects: [CampusAILearningProjectContext]
    let tasks: [CampusAILearningTaskContext]
    let materials: [CampusAIFileMetadataContext]
    let studyRecords: [CampusAIStudyRecordContext]

    static let empty = CampusAILearningWorkspaceContext(projects: [], tasks: [], materials: [], studyRecords: [])

    var hasContent: Bool {
        !projects.isEmpty || !tasks.isEmpty || !materials.isEmpty || !studyRecords.isEmpty
    }
}

nonisolated struct CampusAILearningProjectContext: Codable, Hashable {
    let title: String
    let kind: String
    let goal: String
    let isArchived: Bool
    let updatedAt: String
}

nonisolated struct CampusAILearningTaskContext: Codable, Hashable {
    let title: String
    let category: String
    let note: String
    let dueAt: String?
    let isCompleted: Bool
    let updatedAt: String
}

nonisolated struct CampusAIFileMetadataContext: Codable, Hashable {
    let title: String
    let note: String
    let category: String
    let fileType: String
    let updatedAt: String
}

nonisolated struct CampusAIStudyRecordContext: Codable, Hashable {
    let content: String
    let category: String
    let location: String
    let note: String
    let startedAt: String
    let minutes: Int
}

nonisolated struct CampusAIPostgraduateCareerContext: Codable, Hashable {
    let postgraduateTargets: [CampusAIPostgraduateTargetContext]
    let resumes: [CampusAIFileMetadataContext]
    let careerTasks: [CampusAICareerTaskContext]
    let opportunities: [CampusAICareerOpportunityContext]

    static let empty = CampusAIPostgraduateCareerContext(
        postgraduateTargets: [],
        resumes: [],
        careerTasks: [],
        opportunities: []
    )

    var hasContent: Bool {
        !postgraduateTargets.isEmpty || !resumes.isEmpty || !careerTasks.isEmpty || !opportunities.isEmpty
    }
}

nonisolated struct CampusAIPostgraduateTargetContext: Codable, Hashable {
    let school: String
    let unit: String
    let major: String
    let direction: String
    let examYear: Int
    let subjects: String
    let scoreAndPlanNote: String
    let personalNote: String
    let state: String
    let updatedAt: String
}

nonisolated struct CampusAICareerTaskContext: Codable, Hashable {
    let title: String
    let note: String
    let dueAt: String?
    let isCompleted: Bool
    let updatedAt: String
}

nonisolated struct CampusAICareerOpportunityContext: Codable, Hashable {
    let title: String
    let organization: String
    let status: String
    let note: String
    let updatedAt: String
}

nonisolated struct CampusAIHonorsFitnessQualityContext: Codable, Hashable {
    let honors: [CampusAIFileMetadataContext]
    let fitnessTests: [CampusAIFitnessTestContext]
    let comprehensiveQualityRecords: [CampusAIComprehensiveQualityRecordContext]
    let comprehensiveQualityComponents: [CampusAIComprehensiveQualityComponentContext]
    let comprehensiveQualityEvidence: [CampusAIFileMetadataContext]

    static let empty = CampusAIHonorsFitnessQualityContext(
        honors: [],
        fitnessTests: [],
        comprehensiveQualityRecords: [],
        comprehensiveQualityComponents: [],
        comprehensiveQualityEvidence: []
    )

    var hasContent: Bool {
        !honors.isEmpty ||
            !fitnessTests.isEmpty ||
            !comprehensiveQualityRecords.isEmpty ||
            !comprehensiveQualityComponents.isEmpty ||
            !comprehensiveQualityEvidence.isEmpty
    }
}

nonisolated struct CampusAIFitnessTestContext: Codable, Hashable {
    let item: String
    let value: String
    let note: String
    let testedAt: String
}

nonisolated struct CampusAIComprehensiveQualityRecordContext: Codable, Hashable {
    let collegeName: String
    let cohort: String
    let academicStandardScore: Double?
    let officialQualityScore: Double?
    let officialCompositeScore: Double?
    let note: String
    let updatedAt: String
}

nonisolated struct CampusAIComprehensiveQualityComponentContext: Codable, Hashable {
    let collegeName: String
    let cohort: String
    let component: String
    let rawScore: Double?
    let peerMaxScore: Double?
    let officialStandardScore: Double?
    let materialReady: Bool
    let note: String
    let updatedAt: String
}

nonisolated struct CampusAIMedicalLedgerContext: Codable, Hashable {
    let entries: [CampusAIMedicalLedgerEntryContext]
    let photoCount: Int

    static let empty = CampusAIMedicalLedgerContext(entries: [], photoCount: 0)

    var hasContent: Bool {
        !entries.isEmpty || photoCount > 0
    }
}

nonisolated struct CampusAIMedicalLedgerEntryContext: Codable, Hashable {
    let visitDate: String
    let hospitalName: String
    let department: String
    let diagnosisNote: String
    let scenario: String
    let totalExpense: Double
    let estimatedReimbursement: Double?
    let actualReimbursement: Double?
    let status: String
    let reimbursementDeadline: String?
    let materials: [String]
    let note: String
    let photoCount: Int
    let updatedAt: String
}

nonisolated struct CampusAICommunityCacheContext: Codable, Hashable {
    let posts: [CampusAICommunityPostContext]

    static let empty = CampusAICommunityCacheContext(posts: [])

    var hasContent: Bool {
        !posts.isEmpty
    }
}

nonisolated struct CampusAICommunityPostContext: Codable, Hashable {
    let title: String
    let body: String
    let category: String?
    let commentCount: Int
    let likeCount: Int
    let imageCount: Int
    let createdAt: String
    let updatedAt: String
}

nonisolated enum CampusAIContextBuilder {
    @MainActor
    static func build(
        modelContext: ModelContext,
        settings: CampusAIContextSettings = .defaultValue,
        now: Date = Date()
    ) -> CampusAIContextPayload {
        build(
            courses: fetch(Course.self, in: modelContext),
            courseNotes: fetch(CourseNote.self, in: modelContext),
            occurrenceNotes: fetch(CourseOccurrenceNote.self, in: modelContext),
            courseReminders: fetch(CourseReminderSetting.self, in: modelContext),
            cellReminders: fetch(TimetableCellReminder.self, in: modelContext),
            favoriteClassrooms: fetch(FavoriteClassroom.self, in: modelContext),
            grades: fetch(Grade.self, in: modelContext),
            gradeRankings: SchoolDataCache.loadGradeRankings(),
            exams: SchoolDataCache.loadExamSchedule(),
            teachingPlan: SchoolDataCache.loadTeachingPlan(),
            trainingProgram: SchoolDataCache.loadTrainingProgram(),
            gradeCreditSummary: SchoolDataCache.loadGradeCreditSummary(),
            countdowns: CustomCountdownStore.load(),
            learningMaterials: fetch(LearningMaterialDocument.self, in: modelContext),
            learningProjects: fetch(LearningProject.self, in: modelContext),
            learningTasks: fetch(LearningProjectTask.self, in: modelContext),
            studyRecords: fetch(StudyTimeRecord.self, in: modelContext),
            postgraduateTargets: fetch(PostgraduateTarget.self, in: modelContext),
            careerResumes: fetch(CareerResumeDocument.self, in: modelContext),
            careerTasks: fetch(CareerTask.self, in: modelContext),
            careerOpportunities: fetch(CareerOpportunity.self, in: modelContext),
            honors: fetch(HonorRecord.self, in: modelContext),
            fitnessTests: fetch(FitnessTestRecord.self, in: modelContext),
            qualityRecords: fetch(ComprehensiveQualityRecord.self, in: modelContext),
            qualityComponents: fetch(ComprehensiveQualityComponentEntry.self, in: modelContext),
            qualityEvidence: fetch(ComprehensiveQualityEvidenceDocument.self, in: modelContext),
            medicalEntries: fetch(MedicalLedgerEntry.self, in: modelContext),
            medicalPhotos: fetch(MedicalLedgerPhoto.self, in: modelContext),
            communityPosts: CommunityFeedCache().load(query: .default),
            timetableLastSyncAt: TimetableCacheMetadata.lastSyncAt,
            gradeDetailsLastSyncAt: SchoolDataCache.lastSyncDate(for: .gradeDetails),
            gradeSupplementalLastSyncAt: SchoolDataCache.lastSyncDate(for: .gradeRankings),
            examScheduleLastSyncAt: SchoolDataCache.lastSyncDate(for: .examSchedule),
            teachingPlanLastSyncAt: SchoolDataCache.lastSyncDate(for: .teachingPlan),
            trainingProgramLastSyncAt: SchoolDataCache.lastSyncDate(for: .graduationRequirements),
            settings: settings,
            now: now
        )
    }

    static func build(
        courses: [Course],
        courseNotes: [CourseNote] = [],
        occurrenceNotes: [CourseOccurrenceNote] = [],
        courseReminders: [CourseReminderSetting] = [],
        cellReminders: [TimetableCellReminder] = [],
        favoriteClassrooms: [FavoriteClassroom] = [],
        grades: [Grade],
        gradeRankings: [GradeRankingRecord] = [],
        exams: [ExamArrangement],
        teachingPlan: [TeachingPlanSection],
        trainingProgram: TrainingProgramDocument?,
        gradeCreditSummary: GradeCreditSummary? = nil,
        countdowns: [CustomCountdownEvent],
        learningMaterials: [LearningMaterialDocument] = [],
        learningProjects: [LearningProject] = [],
        learningTasks: [LearningProjectTask] = [],
        studyRecords: [StudyTimeRecord] = [],
        postgraduateTargets: [PostgraduateTarget] = [],
        careerResumes: [CareerResumeDocument] = [],
        careerTasks: [CareerTask] = [],
        careerOpportunities: [CareerOpportunity] = [],
        honors: [HonorRecord] = [],
        fitnessTests: [FitnessTestRecord] = [],
        qualityRecords: [ComprehensiveQualityRecord] = [],
        qualityComponents: [ComprehensiveQualityComponentEntry] = [],
        qualityEvidence: [ComprehensiveQualityEvidenceDocument] = [],
        medicalEntries: [MedicalLedgerEntry] = [],
        medicalPhotos: [MedicalLedgerPhoto] = [],
        communityPosts: [CommunityPost] = [],
        timetableLastSyncAt: Date? = nil,
        gradeDetailsLastSyncAt: Date? = nil,
        gradeSupplementalLastSyncAt: Date? = nil,
        examScheduleLastSyncAt: Date? = nil,
        teachingPlanLastSyncAt: Date? = nil,
        trainingProgramLastSyncAt: Date? = nil,
        settings: CampusAIContextSettings = .defaultValue,
        now: Date = Date()
    ) -> CampusAIContextPayload {
        let weekAndDay = SemesterConfig.weekAndDay(for: now)
        let todayStart = Calendar.current.startOfDay(for: now)
        let sortedCourses = courses.sorted(by: courseSort)
        let weekCourses = sortedCourses
            .filter { $0.weeks.contains(weekAndDay.week) }
        let todayCourses = weekCourses.filter { $0.dayOfWeek == weekAndDay.day }
        let sortedExams = exams
            .filter { exam in
                guard let startsAt = examStartDate(exam) else { return true }
                return startsAt >= todayStart
            }
            .sorted { lhs, rhs in
                (examStartDate(lhs) ?? .distantFuture) < (examStartDate(rhs) ?? .distantFuture)
            }
        let includedScopes = includedScopeNames(settings)
        let omittedScopes = omittedScopeNames(settings)
        let courseNamesByKey = LeafyFirstValueMap.build(
            courses.map { ($0.stableCourseKey, $0.courseName) }
        )
        let photoCounts = Dictionary(grouping: medicalPhotos, by: \.entryID).mapValues(\.count)

        return CampusAIContextPayload(
            generatedAt: ISO8601DateFormatter().string(from: now),
            campusID: ActiveCampusContext.descriptor.id.rawValue,
            campusName: ActiveCampusContext.descriptor.displayName,
            currentWeek: weekAndDay.week,
            currentDayOfWeek: weekAndDay.day,
            includedScopes: includedScopes,
            omittedScopes: omittedScopes,
            dataBoundary: [
                "仅包含用户在设置中允许的本机缓存或本地保存结构化数据。",
                "课表字段 today 和 currentWeek 是当前日期/本周子集；timetable.allCourses 是当前设备已缓存的全学期课程集合。",
                "用户上传文件本体、图片像素、OCR、PDF/Word/PPT/表格正文和本地文件路径永远不会进入上下文。",
                "社区上下文仅来自当前设备缓存的公开 feed 摘要，不包含私信、图片 URL 或未缓存远端内容。"
            ],
            sourceStatus: sourceStatuses(
                settings: settings,
                timetableCount: sortedCourses.count,
                timetableLastSyncAt: timetableLastSyncAt,
                gradeCount: grades.count,
                gradeDetailsLastSyncAt: gradeDetailsLastSyncAt,
                gradeSupplementalCount: gradeRankings.count + (gradeCreditSummary.map { _ in 1 } ?? 0),
                gradeSupplementalLastSyncAt: gradeSupplementalLastSyncAt,
                examCount: sortedExams.count,
                examScheduleLastSyncAt: examScheduleLastSyncAt,
                teachingPlanCourseCount: teachingPlan.reduce(0) { $0 + $1.courses.count },
                teachingPlanLastSyncAt: teachingPlanLastSyncAt,
                trainingProgramRequirementCount: trainingProgram?.creditRequirements.count ?? 0,
                trainingProgramLastSyncAt: trainingProgramLastSyncAt,
                localSavedDataCount: localSavedDataCount(
                    settings: settings,
                    courseNotes: courseNotes,
                    occurrenceNotes: occurrenceNotes,
                    courseReminders: courseReminders,
                    cellReminders: cellReminders,
                    favoriteClassrooms: favoriteClassrooms,
                    countdowns: countdowns,
                    learningMaterials: learningMaterials,
                    learningProjects: learningProjects,
                    learningTasks: learningTasks,
                    studyRecords: studyRecords,
                    postgraduateTargets: postgraduateTargets,
                    careerResumes: careerResumes,
                    careerTasks: careerTasks,
                    careerOpportunities: careerOpportunities,
                    honors: honors,
                    fitnessTests: fitnessTests,
                    qualityRecords: qualityRecords,
                    qualityComponents: qualityComponents,
                    qualityEvidence: qualityEvidence,
                    medicalEntries: medicalEntries,
                    medicalPhotos: medicalPhotos
                )
            ),
            timetable: CampusAITimetableContext(
                today: settings.includesTimetable ? todayCourses.prefix(10).map { CampusAICourseContext(course: $0) } : [],
                currentWeek: settings.includesTimetable ? weekCourses.prefix(60).map { CampusAICourseContext(course: $0) } : [],
                allCourses: settings.includesTimetable ? sortedCourses.prefix(160).map { CampusAICourseContext(course: $0) } : [],
                courseNotes: settings.includesTimetable ? courseNotes.sorted { $0.updatedAt > $1.updatedAt }.prefix(40).map {
                    CampusAICourseNoteContext(note: $0, courseName: courseNamesByKey[$0.courseKey])
                } : [],
                occurrenceNotes: settings.includesTimetable ? occurrenceNotes.sorted { $0.updatedAt > $1.updatedAt }.prefix(40).map {
                    CampusAICourseOccurrenceNoteContext(note: $0, courseName: courseNamesByKey[$0.courseKey])
                } : [],
                courseReminders: settings.includesTimetable ? courseReminders.sorted { $0.updatedAt > $1.updatedAt }.prefix(40).map {
                    CampusAICourseReminderContext(reminder: $0, courseName: courseNamesByKey[$0.courseKey])
                } : [],
                cellReminders: settings.includesTimetable ? cellReminders.sorted { $0.updatedAt > $1.updatedAt }.prefix(40).map { CampusAITimetableCellReminderContext(reminder: $0) } : [],
                favoriteClassrooms: settings.includesTimetable ? favoriteClassrooms.prefix(20).map(\.displayName) : []
            ),
            exams: settings.includesExamsAndPlans ? Array(sortedExams.prefix(40)).map { CampusAIExamContext(exam: $0) } : [],
            grades: settings.includesGrades ? gradeContext(from: grades, rankings: gradeRankings, creditSummary: gradeCreditSummary) : .empty,
            teachingPlan: settings.includesExamsAndPlans ? teachingPlan.prefix(12).map { CampusAITeachingPlanContext(section: $0) } : [],
            trainingProgram: settings.includesExamsAndPlans ? trainingProgram.map { CampusAITrainingProgramContext(document: $0) } : nil,
            countdowns: settings.includesExamsAndPlans ? countdowns
                .filter { $0.targetDate >= todayStart }
                .sorted { $0.targetDate < $1.targetDate }
                .prefix(30)
                .map { CampusAICountdownContext(countdown: $0) } : [],
            learningWorkspace: settings.includesLearningWorkspace
                ? learningContext(materials: learningMaterials, projects: learningProjects, tasks: learningTasks, studyRecords: studyRecords, now: now)
                : .empty,
            postgraduateAndCareer: settings.includesPostgraduateAndCareer
                ? postgraduateCareerContext(targets: postgraduateTargets, resumes: careerResumes, tasks: careerTasks, opportunities: careerOpportunities)
                : .empty,
            honorsFitnessQuality: settings.includesHonorsFitnessQuality
                ? honorsFitnessQualityContext(honors: honors, fitnessTests: fitnessTests, qualityRecords: qualityRecords, qualityComponents: qualityComponents, qualityEvidence: qualityEvidence)
                : .empty,
            medicalLedger: settings.includesMedicalLedger
                ? medicalLedgerContext(entries: medicalEntries, photoCounts: photoCounts)
                : .empty,
            communityCache: settings.includesCommunityCache
                ? CampusAICommunityCacheContext(posts: communityPosts.prefix(20).map { CampusAICommunityPostContext(post: $0) })
                : .empty
        )
    }

    @MainActor
    private static func fetch<T: PersistentModel>(_ type: T.Type, in modelContext: ModelContext) -> [T] {
        (try? modelContext.fetch(FetchDescriptor<T>())) ?? []
    }

    private static func courseSort(_ lhs: Course, _ rhs: Course) -> Bool {
        if lhs.dayOfWeek != rhs.dayOfWeek {
            return lhs.dayOfWeek < rhs.dayOfWeek
        }
        return (lhs.duration.min() ?? 0) < (rhs.duration.min() ?? 0)
    }

    private static func examStartDate(_ exam: ExamArrangement) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: "\(exam.date) \(exam.start)")
    }

    private static func gradeContext(
        from grades: [Grade],
        rankings: [GradeRankingRecord],
        creditSummary: GradeCreditSummary?
    ) -> CampusAIGradeContext {
        let sortedGrades = grades.sorted {
            if $0.term != $1.term {
                return $0.term > $1.term
            }
            return $0.courseName < $1.courseName
        }
        let terms = Set(grades.map(\.term))
        return CampusAIGradeContext(
            courseCount: grades.count,
            termCount: terms.count,
            latestTerm: sortedGrades.first?.term,
            officialGPA: creditSummary?.officialGPA,
            officialWeightedAverage: creditSummary?.officialWeightedAverage,
            totalCredits: creditSummary.flatMap { $0.totalCredits > 0 ? $0.totalCredits : nil },
            requiredCredits: creditSummary.flatMap { $0.requiredCredits > 0 ? $0.requiredCredits : nil },
            publicElectiveCredits: creditSummary.flatMap { $0.publicElectiveCredits > 0 ? $0.publicElectiveCredits : nil },
            professionalElectiveCredits: creditSummary.flatMap { $0.professionalElectiveCredits > 0 ? $0.professionalElectiveCredits : nil },
            recentCourses: sortedGrades.prefix(20).map { CampusAIGradeCourseContext(grade: $0) },
            allCourses: sortedGrades.prefix(160).map { CampusAIGradeCourseContext(grade: $0) },
            rankings: rankings.prefix(20).map { CampusAIGradeRankingContext(ranking: $0) }
        )
    }

    private static func learningContext(
        materials: [LearningMaterialDocument],
        projects: [LearningProject],
        tasks: [LearningProjectTask],
        studyRecords: [StudyTimeRecord],
        now: Date
    ) -> CampusAILearningWorkspaceContext {
        CampusAILearningWorkspaceContext(
            projects: projects.sorted { $0.updatedAt > $1.updatedAt }.prefix(30).map { CampusAILearningProjectContext(project: $0) },
            tasks: tasks.sorted { $0.updatedAt > $1.updatedAt }.prefix(60).map { CampusAILearningTaskContext(task: $0) },
            materials: materials.sorted { $0.updatedAt > $1.updatedAt }.prefix(60).map(CampusAIFileMetadataContext.init(material:)),
            studyRecords: studyRecords.sorted { $0.startedAt > $1.startedAt }.prefix(60).map { CampusAIStudyRecordContext(record: $0) }
        )
    }

    private static func postgraduateCareerContext(
        targets: [PostgraduateTarget],
        resumes: [CareerResumeDocument],
        tasks: [CareerTask],
        opportunities: [CareerOpportunity]
    ) -> CampusAIPostgraduateCareerContext {
        CampusAIPostgraduateCareerContext(
            postgraduateTargets: targets.sorted { $0.updatedAt > $1.updatedAt }.prefix(30).map { CampusAIPostgraduateTargetContext(target: $0) },
            resumes: resumes.sorted { $0.updatedAt > $1.updatedAt }.prefix(20).map(CampusAIFileMetadataContext.init(resume:)),
            careerTasks: tasks.sorted { $0.updatedAt > $1.updatedAt }.prefix(40).map { CampusAICareerTaskContext(task: $0) },
            opportunities: opportunities.sorted { $0.updatedAt > $1.updatedAt }.prefix(40).map { CampusAICareerOpportunityContext(opportunity: $0) }
        )
    }

    private static func honorsFitnessQualityContext(
        honors: [HonorRecord],
        fitnessTests: [FitnessTestRecord],
        qualityRecords: [ComprehensiveQualityRecord],
        qualityComponents: [ComprehensiveQualityComponentEntry],
        qualityEvidence: [ComprehensiveQualityEvidenceDocument]
    ) -> CampusAIHonorsFitnessQualityContext {
        CampusAIHonorsFitnessQualityContext(
            honors: honors.sorted { $0.updatedAt > $1.updatedAt }.prefix(40).map(CampusAIFileMetadataContext.init(honor:)),
            fitnessTests: fitnessTests.sorted {
                if $0.testedAt != $1.testedAt {
                    return $0.testedAt > $1.testedAt
                }
                return $0.createdAt > $1.createdAt
            }.prefix(40).map { CampusAIFitnessTestContext(record: $0) },
            comprehensiveQualityRecords: qualityRecords.sorted { $0.updatedAt > $1.updatedAt }.prefix(20).map { CampusAIComprehensiveQualityRecordContext(record: $0) },
            comprehensiveQualityComponents: qualityComponents.sorted { $0.updatedAt > $1.updatedAt }.prefix(60).map { CampusAIComprehensiveQualityComponentContext(component: $0) },
            comprehensiveQualityEvidence: qualityEvidence.sorted { $0.updatedAt > $1.updatedAt }.prefix(40).map(CampusAIFileMetadataContext.init(qualityEvidence:))
        )
    }

    private static func medicalLedgerContext(
        entries: [MedicalLedgerEntry],
        photoCounts: [String: Int]
    ) -> CampusAIMedicalLedgerContext {
        CampusAIMedicalLedgerContext(
            entries: entries.sorted { $0.updatedAt > $1.updatedAt }.prefix(40).map {
                CampusAIMedicalLedgerEntryContext(entry: $0, photoCount: photoCounts[$0.id.uuidString] ?? 0)
            },
            photoCount: photoCounts.values.reduce(0, +)
        )
    }

    private static func sourceStatuses(
        settings: CampusAIContextSettings,
        timetableCount: Int,
        timetableLastSyncAt: Date?,
        gradeCount: Int,
        gradeDetailsLastSyncAt: Date?,
        gradeSupplementalCount: Int,
        gradeSupplementalLastSyncAt: Date?,
        examCount: Int,
        examScheduleLastSyncAt: Date?,
        teachingPlanCourseCount: Int,
        teachingPlanLastSyncAt: Date?,
        trainingProgramRequirementCount: Int,
        trainingProgramLastSyncAt: Date?,
        localSavedDataCount: Int
    ) -> [CampusAIContextSourceStatus] {
        [
            sourceStatus(
                scope: "全学期课表",
                isEnabled: settings.includesTimetable,
                itemCount: timetableCount,
                lastSyncAt: timetableLastSyncAt,
                missingNote: "当前设备还没有可用课表缓存；需要连接校园网同步或导入。"
            ),
            sourceStatus(
                scope: "成绩明细",
                isEnabled: settings.includesGrades,
                itemCount: gradeCount,
                lastSyncAt: gradeDetailsLastSyncAt,
                missingNote: "当前设备还没有可用成绩明细缓存；需要连接校园网同步或导入。"
            ),
            sourceStatus(
                scope: "成绩排名和学分汇总",
                isEnabled: settings.includesGrades,
                itemCount: gradeSupplementalCount,
                lastSyncAt: gradeSupplementalLastSyncAt,
                missingNote: "当前设备还没有可用排名或学分汇总缓存，教务系统也可能未开放排名。"
            ),
            sourceStatus(
                scope: "考试安排",
                isEnabled: settings.includesExamsAndPlans,
                itemCount: examCount,
                lastSyncAt: examScheduleLastSyncAt,
                missingNote: "当前设备还没有可用考试安排缓存。"
            ),
            sourceStatus(
                scope: "教学计划",
                isEnabled: settings.includesExamsAndPlans,
                itemCount: teachingPlanCourseCount,
                lastSyncAt: teachingPlanLastSyncAt,
                missingNote: "当前设备还没有可用教学计划缓存。"
            ),
            sourceStatus(
                scope: "培养方案",
                isEnabled: settings.includesExamsAndPlans,
                itemCount: trainingProgramRequirementCount,
                lastSyncAt: trainingProgramLastSyncAt,
                missingNote: "当前设备还没有可用培养方案缓存。"
            ),
            CampusAIContextSourceStatus(
                scope: "本地保存数据",
                itemCount: localSavedDataCount,
                lastSyncAt: nil,
                state: .localOnly,
                note: localSavedDataCount > 0 ? "来自当前设备的备注、提醒、资料元数据和个人台账。" : "当前设备暂未保存本地扩展数据。"
            )
        ]
    }

    private static func sourceStatus(
        scope: String,
        isEnabled: Bool,
        itemCount: Int,
        lastSyncAt: Date?,
        missingNote: String
    ) -> CampusAIContextSourceStatus {
        if !isEnabled {
            return CampusAIContextSourceStatus(
                scope: scope,
                itemCount: 0,
                lastSyncAt: nil,
                state: .disabled,
                note: "用户已在 Leafy AI 设置中关闭此上下文。"
            )
        }

        let syncText = lastSyncAt.map { "最近同步：\(ISO8601DateFormatter().string(from: $0))。" } ?? "暂无同步时间记录。"
        return CampusAIContextSourceStatus(
            scope: scope,
            itemCount: itemCount,
            lastSyncAt: lastSyncAt.map { ISO8601DateFormatter().string(from: $0) },
            state: itemCount > 0 ? .available : .missing,
            note: itemCount > 0 ? syncText : missingNote
        )
    }

    private static func localSavedDataCount(
        settings: CampusAIContextSettings,
        courseNotes: [CourseNote],
        occurrenceNotes: [CourseOccurrenceNote],
        courseReminders: [CourseReminderSetting],
        cellReminders: [TimetableCellReminder],
        favoriteClassrooms: [FavoriteClassroom],
        countdowns: [CustomCountdownEvent],
        learningMaterials: [LearningMaterialDocument],
        learningProjects: [LearningProject],
        learningTasks: [LearningProjectTask],
        studyRecords: [StudyTimeRecord],
        postgraduateTargets: [PostgraduateTarget],
        careerResumes: [CareerResumeDocument],
        careerTasks: [CareerTask],
        careerOpportunities: [CareerOpportunity],
        honors: [HonorRecord],
        fitnessTests: [FitnessTestRecord],
        qualityRecords: [ComprehensiveQualityRecord],
        qualityComponents: [ComprehensiveQualityComponentEntry],
        qualityEvidence: [ComprehensiveQualityEvidenceDocument],
        medicalEntries: [MedicalLedgerEntry],
        medicalPhotos: [MedicalLedgerPhoto]
    ) -> Int {
        let timetableCount = settings.includesTimetable ? (
            courseNotes.count +
            occurrenceNotes.count +
            courseReminders.count +
            cellReminders.count +
            favoriteClassrooms.count
        ) : 0
        let countdownCount = settings.includesExamsAndPlans ? countdowns.count : 0
        let learningCount = settings.includesLearningWorkspace ? (
            learningMaterials.count +
            learningProjects.count +
            learningTasks.count +
            studyRecords.count
        ) : 0
        let careerCount = settings.includesPostgraduateAndCareer ? (
            postgraduateTargets.count +
            careerResumes.count +
            careerTasks.count +
            careerOpportunities.count
        ) : 0
        let honorsCount = settings.includesHonorsFitnessQuality ? (
            honors.count +
            fitnessTests.count +
            qualityRecords.count +
            qualityComponents.count +
            qualityEvidence.count
        ) : 0
        let medicalCount = settings.includesMedicalLedger ? (
            medicalEntries.count +
            medicalPhotos.count
        ) : 0
        return timetableCount + countdownCount + learningCount + careerCount + honorsCount + medicalCount
    }

    private static func includedScopeNames(_ settings: CampusAIContextSettings) -> [String] {
        scopePairs(settings).compactMap { $0.isIncluded ? $0.name : nil }
    }

    private static func omittedScopeNames(_ settings: CampusAIContextSettings) -> [String] {
        scopePairs(settings).compactMap { $0.isIncluded ? nil : $0.name }
    }

    private static func scopePairs(_ settings: CampusAIContextSettings) -> [(name: String, isIncluded: Bool)] {
        [
            ("课表和提醒", settings.includesTimetable),
            ("成绩和排名", settings.includesGrades),
            ("考试和培养计划", settings.includesExamsAndPlans),
            ("学习空间", settings.includesLearningWorkspace),
            ("考研和职业规划", settings.includesPostgraduateAndCareer),
            ("荣誉体测综测", settings.includesHonorsFitnessQuality),
            ("医疗台账", settings.includesMedicalLedger),
            ("社区公开缓存", settings.includesCommunityCache)
        ]
    }
}

nonisolated extension CampusAICourseContext {
    init(course: Course) {
        self.init(
            name: course.courseName,
            teacher: course.teacher,
            room: course.room,
            location: course.location,
            dayOfWeek: course.dayOfWeek,
            periods: course.duration,
            weeks: course.weeks
        )
    }
}

nonisolated extension CampusAIExamContext {
    init(exam: ExamArrangement) {
        self.init(name: exam.name, date: exam.date, start: exam.start, end: exam.end, location: exam.location)
    }
}

nonisolated extension CampusAIGradeCourseContext {
    init(grade: Grade) {
        self.init(term: grade.term, name: grade.courseName, credit: grade.credit, score: grade.score, type: grade.type)
    }
}

nonisolated extension CampusAIGradeContext {
    static let empty = CampusAIGradeContext(
        courseCount: 0,
        termCount: 0,
        latestTerm: nil,
        officialGPA: nil,
        officialWeightedAverage: nil,
        totalCredits: nil,
        requiredCredits: nil,
        publicElectiveCredits: nil,
        professionalElectiveCredits: nil,
        recentCourses: [],
        allCourses: [],
        rankings: []
    )
}

nonisolated extension CampusAIGradeRankingContext {
    init(ranking: GradeRankingRecord) {
        self.init(
            term: ranking.term,
            range: ranking.rankingRange,
            rank: ranking.rank,
            totalCount: ranking.totalCount,
            percentile: ranking.percentile,
            metric: ranking.metricText
        )
    }
}

nonisolated extension CampusAITeachingPlanContext {
    init(section: TeachingPlanSection) {
        self.init(
            term: section.term,
            totalCredits: section.courses.reduce(0) { $0 + $1.credit },
            courses: section.courses.prefix(24).map { "\($0.name)（\($0.credit) 学分）" }
        )
    }
}

nonisolated extension CampusAITrainingProgramContext {
    init(document: TrainingProgramDocument) {
        self.init(
            title: document.title,
            sections: document.sections.prefix(8).map { "\($0.title)：\($0.body)" },
            creditRequirements: document.creditRequirements.prefix(16).map {
                "\(Self.displayCategory(for: $0)) \($0.courseName) 需 \($0.requiredCredits) 学分"
            }
        )
    }

    private static func displayCategory(for requirement: GraduationCreditRequirement) -> String {
        switch requirement.kind {
        case .total:
            return "总学分"
        case .publicElective:
            return "公选课"
        case .professionalElective:
            return "专选课"
        case .other:
            return requirement.category
        }
    }
}

nonisolated extension CampusAICourseNoteContext {
    init(note: CourseNote, courseName: String?) {
        self.init(
            courseName: courseName ?? "未知课程",
            text: note.text.clampedForAIContext(),
            updatedAt: Self.dateString(note.updatedAt)
        )
    }

    private static func dateString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}

nonisolated extension CampusAICourseOccurrenceNoteContext {
    init(note: CourseOccurrenceNote, courseName: String?) {
        self.init(
            courseName: courseName ?? "未知课程",
            week: note.week,
            dayOfWeek: note.dayOfWeek,
            text: note.text.clampedForAIContext(),
            updatedAt: ISO8601DateFormatter().string(from: note.updatedAt)
        )
    }
}

nonisolated extension CampusAICourseReminderContext {
    init(reminder: CourseReminderSetting, courseName: String?) {
        self.init(
            courseName: courseName ?? "未知课程",
            minutesBefore: reminder.minutesBefore,
            anchorPeriod: reminder.anchorPeriod,
            updatedAt: ISO8601DateFormatter().string(from: reminder.updatedAt)
        )
    }
}

nonisolated extension CampusAITimetableCellReminderContext {
    init(reminder: TimetableCellReminder) {
        self.init(
            week: reminder.week,
            dayOfWeek: reminder.dayOfWeek,
            period: reminder.period,
            endPeriod: reminder.endPeriod,
            title: reminder.title.clampedForAIContext(80),
            location: reminder.location?.clampedForAIContext(80),
            note: reminder.note?.clampedForAIContext(),
            minutesBefore: reminder.minutesBefore,
            updatedAt: ISO8601DateFormatter().string(from: reminder.updatedAt)
        )
    }
}

nonisolated extension CampusAICountdownContext {
    init(countdown: CustomCountdownEvent) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        self.init(title: countdown.title, targetDate: formatter.string(from: countdown.targetDate))
    }
}

nonisolated extension CampusAILearningProjectContext {
    init(project: LearningProject) {
        self.init(
            title: project.title.clampedForAIContext(80),
            kind: Self.kindTitle(project.kindRawValue),
            goal: project.goal.clampedForAIContext(),
            isArchived: project.isArchived,
            updatedAt: ISO8601DateFormatter().string(from: project.updatedAt)
        )
    }

    private static func kindTitle(_ rawValue: String) -> String {
        switch rawValue {
        case LearningProjectKind.course.rawValue:
            return "课程"
        case LearningProjectKind.exam.rawValue:
            return "考试"
        case LearningProjectKind.certificate.rawValue:
            return "证书"
        default:
            return "通用"
        }
    }
}

nonisolated extension CampusAILearningTaskContext {
    init(task: LearningProjectTask) {
        self.init(
            title: task.title.clampedForAIContext(80),
            category: task.category.rawValue,
            note: task.note.clampedForAIContext(),
            dueAt: task.dueAt.map { ISO8601DateFormatter().string(from: $0) },
            isCompleted: task.isCompleted,
            updatedAt: ISO8601DateFormatter().string(from: task.updatedAt)
        )
    }
}

nonisolated extension CampusAIFileMetadataContext {
    init(material: LearningMaterialDocument) {
        self.init(
            title: material.title.clampedForAIContext(80),
            note: material.note.clampedForAIContext(),
            category: material.category.rawValue,
            fileType: material.displayType,
            updatedAt: ISO8601DateFormatter().string(from: material.updatedAt)
        )
    }

    init(resume: CareerResumeDocument) {
        self.init(
            title: resume.title.clampedForAIContext(80),
            note: resume.note.clampedForAIContext(),
            category: "简历",
            fileType: LearningMaterialDocument.displayType(
                contentTypeIdentifier: resume.contentTypeIdentifier,
                originalFilename: resume.originalFilename
            ),
            updatedAt: ISO8601DateFormatter().string(from: resume.updatedAt)
        )
    }

    init(honor: HonorRecord) {
        self.init(
            title: honor.title.clampedForAIContext(80),
            note: honor.note.clampedForAIContext(),
            category: "荣誉",
            fileType: LearningMaterialDocument.displayType(
                contentTypeIdentifier: honor.contentTypeIdentifier,
                originalFilename: honor.originalFilename
            ),
            updatedAt: ISO8601DateFormatter().string(from: honor.updatedAt)
        )
    }

    init(qualityEvidence: ComprehensiveQualityEvidenceDocument) {
        self.init(
            title: qualityEvidence.title.clampedForAIContext(80),
            note: qualityEvidence.note.clampedForAIContext(),
            category: qualityEvidence.componentRawValue,
            fileType: LearningMaterialDocument.displayType(
                contentTypeIdentifier: qualityEvidence.contentTypeIdentifier,
                originalFilename: qualityEvidence.originalFilename
            ),
            updatedAt: ISO8601DateFormatter().string(from: qualityEvidence.updatedAt)
        )
    }
}

nonisolated extension CampusAIStudyRecordContext {
    init(record: StudyTimeRecord) {
        self.init(
            content: record.content.clampedForAIContext(100),
            category: record.category.rawValue,
            location: record.location.clampedForAIContext(80),
            note: record.note.clampedForAIContext(),
            startedAt: ISO8601DateFormatter().string(from: record.startedAt),
            minutes: max(Int(record.endedAt.timeIntervalSince(record.startedAt) / 60), 0)
        )
    }
}

nonisolated extension CampusAIPostgraduateTargetContext {
    init(target: PostgraduateTarget) {
        self.init(
            school: target.school.clampedForAIContext(80),
            unit: target.unit.clampedForAIContext(80),
            major: target.major.clampedForAIContext(80),
            direction: target.direction.clampedForAIContext(80),
            examYear: target.examYear,
            subjects: target.subjects.clampedForAIContext(),
            scoreAndPlanNote: target.scoreAndPlanNote.clampedForAIContext(),
            personalNote: target.personalNote.clampedForAIContext(),
            state: target.state.rawValue,
            updatedAt: ISO8601DateFormatter().string(from: target.updatedAt)
        )
    }
}

nonisolated extension CampusAICareerTaskContext {
    init(task: CareerTask) {
        self.init(
            title: task.title.clampedForAIContext(80),
            note: task.note.clampedForAIContext(),
            dueAt: task.dueAt.map { ISO8601DateFormatter().string(from: $0) },
            isCompleted: task.isCompleted,
            updatedAt: ISO8601DateFormatter().string(from: task.updatedAt)
        )
    }
}

nonisolated extension CampusAICareerOpportunityContext {
    init(opportunity: CareerOpportunity) {
        self.init(
            title: opportunity.title.clampedForAIContext(80),
            organization: opportunity.organization.clampedForAIContext(80),
            status: opportunity.statusRawValue,
            note: opportunity.note.clampedForAIContext(),
            updatedAt: ISO8601DateFormatter().string(from: opportunity.updatedAt)
        )
    }
}

nonisolated extension CampusAIFitnessTestContext {
    init(record: FitnessTestRecord) {
        self.init(
            item: record.item.rawValue,
            value: record.displayValue,
            note: record.note.clampedForAIContext(),
            testedAt: ISO8601DateFormatter().string(from: record.testedAt)
        )
    }
}

nonisolated extension CampusAIComprehensiveQualityRecordContext {
    init(record: ComprehensiveQualityRecord) {
        self.init(
            collegeName: record.collegeName.clampedForAIContext(80),
            cohort: record.cohort,
            academicStandardScore: record.academicStandardScore,
            officialQualityScore: record.officialQualityScore,
            officialCompositeScore: record.officialCompositeScore,
            note: record.note.clampedForAIContext(),
            updatedAt: ISO8601DateFormatter().string(from: record.updatedAt)
        )
    }
}

nonisolated extension CampusAIComprehensiveQualityComponentContext {
    init(component: ComprehensiveQualityComponentEntry) {
        self.init(
            collegeName: component.collegeName.clampedForAIContext(80),
            cohort: component.cohort,
            component: component.componentRawValue,
            rawScore: component.rawScore,
            peerMaxScore: component.peerMaxScore,
            officialStandardScore: component.officialStandardScore,
            materialReady: component.materialReady,
            note: component.note.clampedForAIContext(),
            updatedAt: ISO8601DateFormatter().string(from: component.updatedAt)
        )
    }
}

nonisolated extension CampusAIMedicalLedgerEntryContext {
    init(entry: MedicalLedgerEntry, photoCount: Int) {
        self.init(
            visitDate: ISO8601DateFormatter().string(from: entry.visitDate),
            hospitalName: entry.hospitalName.clampedForAIContext(80),
            department: entry.department.clampedForAIContext(80),
            diagnosisNote: entry.diagnosisNote.clampedForAIContext(),
            scenario: entry.scenario.rawValue,
            totalExpense: entry.totalExpense,
            estimatedReimbursement: entry.estimatedOrCalculatedReimbursement,
            actualReimbursement: entry.actualReimbursement,
            status: entry.status.rawValue,
            reimbursementDeadline: entry.reimbursementDeadline.map { ISO8601DateFormatter().string(from: $0) },
            materials: entry.materials.sorted { $0.rawValue < $1.rawValue }.map(\.rawValue),
            note: entry.note.clampedForAIContext(),
            photoCount: photoCount,
            updatedAt: ISO8601DateFormatter().string(from: entry.updatedAt)
        )
    }
}

nonisolated extension CampusAICommunityPostContext {
    init(post: CommunityPost) {
        self.init(
            title: post.title.clampedForAIContext(80),
            body: post.body.clampedForAIContext(180),
            category: post.category,
            commentCount: post.commentCount,
            likeCount: post.likeCount,
            imageCount: post.images.count,
            createdAt: post.createdAt,
            updatedAt: post.updatedAt
        )
    }
}

nonisolated enum CampusAIServiceError: LocalizedError, Equatable {
    case emptyMessage
    case missingAPIKey
    case invalidBaseURL
    case managedServiceUnavailable
    case quotaExhausted(String)
    case providerRejected(String)
    case invalidProviderResponse

    var errorDescription: String? {
        switch self {
        case .emptyMessage:
            return "请先输入想问的问题。"
        case .missingAPIKey:
            return "请先在 Leafy 设置中填写 DeepSeek API Key。"
        case .invalidBaseURL:
            return "Base URL 设置不正确，请使用 HTTPS 地址。"
        case .managedServiceUnavailable:
            return "Leafy 托管服务暂时不可用，请稍后再试。"
        case .quotaExhausted(let message):
            return message
        case .providerRejected(let message):
            return message
        case .invalidProviderResponse:
            return "AI 助手返回了无法识别的响应。"
        }
    }
}

nonisolated enum CampusAIKeychainError: LocalizedError {
    case unexpectedStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            return "API Key 保存失败（\(status)）。"
        }
    }
}

nonisolated enum CampusAIKeychainStore {
    private static let service = "com.myleafy.campus-ai"
    private static let legacyCleanupStorageKey = "campusAI.keychainLegacyCleanup.v2"
    static let legacyAccounts = ["zhipu-api-key", "customOpenAICompatible-api-key"]

    static func load(providerID: CampusAIProviderID = CampusAIProviderCatalog.defaultProvider.id) -> String? {
        try? removeLegacyKeysIfNeeded()
        return load(account: account(for: providerID))
    }

    static func save(
        _ apiKey: String,
        providerID: CampusAIProviderID = CampusAIProviderCatalog.defaultProvider.id
    ) throws {
        try removeLegacyKeysIfNeeded()
        guard let trimmed = apiKey.nonEmptyTrimmed else {
            try delete(providerID: providerID)
            return
        }

        let data = Data(trimmed.utf8)
        let updateStatus = SecItemUpdate(
            baseQuery(account: account(for: providerID)) as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess {
            return
        }
        if updateStatus != errSecItemNotFound {
            throw CampusAIKeychainError.unexpectedStatus(updateStatus)
        }

        var addQuery = baseQuery(account: account(for: providerID))
        addQuery[kSecValueData as String] = data
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw CampusAIKeychainError.unexpectedStatus(addStatus)
        }
    }

    static func delete(providerID: CampusAIProviderID = CampusAIProviderCatalog.defaultProvider.id) throws {
        try removeLegacyKeysIfNeeded()
        let status = SecItemDelete(baseQuery(account: account(for: providerID)) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CampusAIKeychainError.unexpectedStatus(status)
        }
    }

    static func hasAPIKey(providerID: CampusAIProviderID = CampusAIProviderCatalog.defaultProvider.id) -> Bool {
        load(providerID: providerID) != nil
    }

    static func configuredProviderIDs() -> Set<CampusAIProviderID> {
        Set(
            CampusAIProviderCatalog.all.compactMap { provider in
                hasAPIKey(providerID: provider.id) ? provider.id : nil
            }
        )
    }

    static func removeLegacyKeysIfNeeded(userDefaults: UserDefaults = .standard) throws {
        try removeLegacyKeysIfNeeded(userDefaults: userDefaults) { account in
            SecItemDelete(baseQuery(account: account) as CFDictionary)
        }
    }

    static func removeLegacyKeysIfNeeded(
        userDefaults: UserDefaults,
        deleteItem: (String) -> OSStatus
    ) throws {
        guard !userDefaults.bool(forKey: legacyCleanupStorageKey) else { return }
        for account in legacyAccounts {
            let status = deleteItem(account)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw CampusAIKeychainError.unexpectedStatus(status)
            }
        }
        userDefaults.set(true, forKey: legacyCleanupStorageKey)
    }

    private static func load(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return value.nonEmptyTrimmed
    }

    private static func account(for providerID: CampusAIProviderID) -> String {
        "\(providerID.rawValue)-api-key"
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

nonisolated struct CampusAIAPIKeyResolver {
    var userAPIKey: (CampusAIProviderID) -> String?

    init(
        userAPIKey: @escaping (CampusAIProviderID) -> String? = CampusAIKeychainStore.load(providerID:)
    ) {
        self.userAPIKey = userAPIKey
    }

    func resolve(for settings: CampusAIUserSettings) throws -> String {
        if let userKey = userAPIKey(settings.selectedProviderID)?.nonEmptyTrimmed {
            return userKey
        }
        throw CampusAIServiceError.missingAPIKey
    }
}

nonisolated enum CampusAIStreamEvent: Equatable {
    case delta(String)
    case reasoningDelta(String)
    case quota(CampusAIQuotaSnapshot)
    case done(CampusAIResponse)
    case error(String)
}

nonisolated struct CampusAISSEParser {
    private var pendingData = Data()
    private var buffer = ""
    private let decoder = JSONDecoder()
    private var accumulatedAnswer = ""
    private var accumulatedReasoning = ""
    private var finishReason: String?
    private var emittedDone = false

    init() {}

    mutating func append(_ data: Data) throws -> [CampusAIStreamEvent] {
        pendingData.append(data)
        guard let string = String(data: pendingData, encoding: .utf8) else {
            return []
        }
        pendingData.removeAll(keepingCapacity: true)
        guard !string.isEmpty else {
            return []
        }
        buffer += string
        return try drainCompleteBlocks(includeRemainder: false)
    }

    mutating func finish() throws -> [CampusAIStreamEvent] {
        if !pendingData.isEmpty {
            guard let string = String(data: pendingData, encoding: .utf8) else {
                throw CampusAIServiceError.invalidProviderResponse
            }
            buffer += string
            pendingData.removeAll(keepingCapacity: true)
        }
        return try drainCompleteBlocks(includeRemainder: true)
    }

    private mutating func drainCompleteBlocks(includeRemainder: Bool) throws -> [CampusAIStreamEvent] {
        var events: [CampusAIStreamEvent] = []
        while let range = buffer.range(of: "\n\n") ?? buffer.range(of: "\r\n\r\n") {
            let block = String(buffer[..<range.lowerBound])
            buffer.removeSubrange(..<range.upperBound)
            events.append(contentsOf: try parseBlock(block))
        }

        if includeRemainder, !buffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            events.append(contentsOf: try parseBlock(buffer))
            buffer = ""
        }
        if includeRemainder, !emittedDone {
            emittedDone = true
            events.append(doneEvent())
        }
        return events
    }

    private mutating func parseBlock(_ block: String) throws -> [CampusAIStreamEvent] {
        let dataLines = block
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .compactMap { line -> String? in
                if line.hasPrefix(":") {
                    return nil
                }
                guard line.hasPrefix("data:") else {
                    return nil
                }
                let value = line.dropFirst(5)
                if value.first == " " {
                    return String(value.dropFirst())
                }
                return String(value)
            }
        let payloadText = dataLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !payloadText.isEmpty else {
            return []
        }
        if payloadText == "[DONE]" {
            emittedDone = true
            return [doneEvent()]
        }

        let payloadData = Data(payloadText.utf8)
        if let managedPayload = try? decoder.decode(CampusAIManagedStreamPayload.self, from: payloadData),
           managedPayload.type != nil {
            return try parseManagedPayload(managedPayload)
        }

        let payload: CampusAIProviderStreamPayload
        do {
            payload = try decoder.decode(CampusAIProviderStreamPayload.self, from: payloadData)
        } catch {
            throw CampusAIServiceError.invalidProviderResponse
        }

        if let providerError = payload.error {
            let message = providerError.message?.nonEmptyTrimmed ?? "AI 助手暂时不可用，请稍后重试。"
            throw CampusAIServiceError.providerRejected(CampusAIService.redactProviderError(message))
        }

        let choices = payload.choices ?? []
        if let newFinishReason = choices.compactMap(\.finishReason).last?.nonEmptyTrimmed {
            finishReason = newFinishReason
        }

        let reasoningDelta = choices
            .compactMap { $0.delta?.reasoningContent ?? $0.message?.reasoningContent }
            .joined()
        let contentDelta = choices
            .compactMap { $0.delta?.content ?? $0.message?.content }
            .joined()

        var events: [CampusAIStreamEvent] = []
        if !reasoningDelta.isEmpty {
            accumulatedReasoning += reasoningDelta
            events.append(.reasoningDelta(reasoningDelta))
        }
        if !contentDelta.isEmpty {
            accumulatedAnswer += contentDelta
            events.append(.delta(contentDelta))
        }
        return events
    }

    private mutating func parseManagedPayload(_ payload: CampusAIManagedStreamPayload) throws -> [CampusAIStreamEvent] {
        switch payload.type {
        case "delta":
            let text = payload.text ?? ""
            accumulatedAnswer += text
            return text.isEmpty ? [] : [.delta(text)]
        case "reasoning_delta":
            let text = payload.text ?? ""
            accumulatedReasoning += text
            return text.isEmpty ? [] : [.reasoningDelta(text)]
        case "quota":
            guard let quota = payload.quota else { return [] }
            return [.quota(quota)]
        case "done":
            emittedDone = true
            let answer = payload.answer ?? accumulatedAnswer
            let reasoning = payload.reasoning ?? accumulatedReasoning
            return [
                .done(
                    CampusAIResponse(
                        answer: answer,
                        reasoning: reasoning,
                        finishReason: payload.finishReason,
                        suggestedTitle: payload.suggestedTitle,
                        summary: payload.summary
                    )
                )
            ]
        case "error":
            let message = payload.error?.nonEmptyTrimmed ?? "AI 助手暂时不可用，请稍后重试。"
            throw CampusAIServiceError.providerRejected(CampusAIService.redactProviderError(message))
        default:
            return []
        }
    }

    private func doneEvent() -> CampusAIStreamEvent {
        .done(
            CampusAIResponse(
                answer: accumulatedAnswer,
                reasoning: accumulatedReasoning,
                finishReason: finishReason
            )
        )
    }
}

nonisolated private struct CampusAIProviderStreamPayload: Decodable {
    let choices: [Choice]?
    let error: ProviderError?

    struct Choice: Decodable {
        let delta: MessageDelta?
        let message: MessageDelta?
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case delta
            case message
            case finishReason = "finish_reason"
        }
    }

    struct MessageDelta: Decodable {
        let content: String?

        let reasoningContent: String?

        enum CodingKeys: String, CodingKey {
            case content
            case reasoningContent = "reasoning_content"
        }
    }

    struct ProviderError: Decodable {
        let message: String?
    }
}

nonisolated private struct CampusAIManagedStreamPayload: Decodable {
    let type: String?
    let text: String?
    let answer: String?
    let reasoning: String?
    let finishReason: String?
    let suggestedTitle: String?
    let summary: String?
    let error: String?
    let quota: CampusAIQuotaSnapshot?

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case answer
        case reasoning
        case finishReason = "finish_reason"
        case suggestedTitle = "suggested_title"
        case summary
        case error
        case quota
    }
}

nonisolated struct CampusAIChatCompletionsPayload: Encodable, Hashable {
    let model: String
    let messages: [Message]
    let stream: Bool
    let thinking: Thinking
    let streamOptions: StreamOptions
    let temperature: Double
    let maxTokens: Int
    let user: String?

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case stream
        case thinking
        case streamOptions = "stream_options"
        case temperature
        case maxTokens = "max_tokens"
        case user
    }

    struct Thinking: Encodable, Hashable {
        let type: String

        static let enabled = Thinking(type: "enabled")
    }

    struct StreamOptions: Encodable, Hashable {
        let includeUsage: Bool

        enum CodingKeys: String, CodingKey {
            case includeUsage = "include_usage"
        }

        static let includeUsage = StreamOptions(includeUsage: true)
    }

    struct Message: Encodable, Hashable {
        let role: String
        let content: String
    }
}

nonisolated struct CampusAIService {
    var streamInvoke: @Sendable (CampusAIRequest, CampusAIUserSettings) -> AsyncThrowingStream<CampusAIStreamEvent, Error>

    init(
        streamInvoke: @escaping @Sendable (CampusAIRequest, CampusAIUserSettings) -> AsyncThrowingStream<CampusAIStreamEvent, Error> = CampusAIService.invokeStream
    ) {
        self.streamInvoke = streamInvoke
    }

    func send(
        message: String,
        context: CampusAIContextPayload,
        recentMessages: [CampusAIChatMessage],
        settings: CampusAIUserSettings = .defaultValue
    ) async throws -> CampusAIResponse {
        var accumulatedAnswer = ""
        var accumulatedReasoning = ""
        var finalResponse: CampusAIResponse?
        for try await event in stream(
            message: message,
            context: context,
            recentMessages: recentMessages,
            settings: settings
        ) {
            switch event {
            case .delta(let text):
                accumulatedAnswer += text
            case .reasoningDelta(let text):
                accumulatedReasoning += text
            case .quota:
                break
            case .done(let response):
                finalResponse = response
            case .error(let message):
                throw CampusAIServiceError.providerRejected(message)
            }
        }
        var response = finalResponse ?? CampusAIResponse(answer: accumulatedAnswer)
        if response.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            response.answer = accumulatedAnswer
        }
        if response.reasoning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            response.reasoning = accumulatedReasoning
        }
        response.actions = []
        return response
    }

    func stream(
        message: String,
        context: CampusAIContextPayload,
        recentMessages: [CampusAIChatMessage],
        settings: CampusAIUserSettings = .defaultValue
    ) -> AsyncThrowingStream<CampusAIStreamEvent, Error> {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: CampusAIServiceError.emptyMessage)
            }
        }
        let request = CampusAIRequest(
            message: trimmed,
            context: context,
            recentMessages: recentMessages,
            model: settings.selectedProvider.modelIdentifier,
            userSystemPrompt: settings.effectiveSystemPrompt,
            contextSettings: settings.contextSettings
        )
        return streamInvoke(request, settings)
    }

    private static func invokeStream(
        _ request: CampusAIRequest,
        settings: CampusAIUserSettings
    ) -> AsyncThrowingStream<CampusAIStreamEvent, Error> {
        switch settings.serviceMode {
        case .ownAPIKey:
            return invokeDirectStream(request, settings: settings)
        case .leafyManaged:
            return invokeManagedStream(request, settings: settings)
        }
    }

    private static func invokeDirectStream(
        _ request: CampusAIRequest,
        settings: CampusAIUserSettings
    ) -> AsyncThrowingStream<CampusAIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let apiKey = try CampusAIAPIKeyResolver().resolve(for: settings)
                    let urlRequest = try makeChatCompletionsRequest(
                        for: request,
                        baseURLString: settings.selectedProvider.baseURLString,
                        apiKey: apiKey
                    )
                    let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw CampusAIServiceError.invalidProviderResponse
                    }
                    guard (200..<300).contains(httpResponse.statusCode) else {
                        let body = try await providerErrorBody(from: bytes)
                        throw CampusAIServiceError.providerRejected(
                            providerHTTPErrorMessage(statusCode: httpResponse.statusCode, body: body)
                        )
                    }

                    let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
                    if contentType.contains("text/event-stream") {
                        var parser = CampusAISSEParser()
                        var chunk = Data()
                        chunk.reserveCapacity(4_096)
                        for try await byte in bytes {
                            try Task.checkCancellation()
                            chunk.append(byte)
                            if chunk.count >= 4_096 {
                                for event in try parser.append(chunk) {
                                    continuation.yield(event)
                                }
                                chunk.removeAll(keepingCapacity: true)
                            }
                        }

                        if !chunk.isEmpty {
                            for event in try parser.append(chunk) {
                                continuation.yield(event)
                            }
                        }

                        for event in try parser.finish() {
                            continuation.yield(event)
                        }
                    } else {
                        let body = try await providerBody(from: bytes)
                        for event in try providerEvents(from: body) {
                            continuation.yield(event)
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private static func invokeManagedStream(
        _ request: CampusAIRequest,
        settings: CampusAIUserSettings
    ) -> AsyncThrowingStream<CampusAIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let urlRequest = try await makeManagedFunctionRequest(for: request, settings: settings)
                    let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw CampusAIServiceError.invalidProviderResponse
                    }
                    guard (200..<300).contains(httpResponse.statusCode) else {
                        let body = try await providerErrorBody(from: bytes)
                        throw CampusAIServiceError.providerRejected(
                            managedHTTPErrorMessage(statusCode: httpResponse.statusCode, body: body)
                        )
                    }

                    var parser = CampusAISSEParser()
                    var chunk = Data()
                    chunk.reserveCapacity(4_096)
                    for try await byte in bytes {
                        try Task.checkCancellation()
                        chunk.append(byte)
                        if chunk.count >= 4_096 {
                            for event in try parser.append(chunk) {
                                continuation.yield(event)
                            }
                            chunk.removeAll(keepingCapacity: true)
                        }
                    }

                    if !chunk.isEmpty {
                        for event in try parser.append(chunk) {
                            continuation.yield(event)
                        }
                    }

                    for event in try parser.finish() {
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    static func makeChatCompletionsRequest(
        for request: CampusAIRequest,
        baseURLString: String,
        apiKey: String
    ) throws -> URLRequest {
        let url = try chatCompletionsURL(baseURLString: baseURLString)
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try providerJSONEncoder().encode(chatCompletionsPayload(for: request))
        return urlRequest
    }

    static func makeManagedFunctionRequest(
        for request: CampusAIRequest,
        settings: CampusAIUserSettings
    ) async throws -> URLRequest {
        try await CommunityService.shared.ensureAnonymousSession()
        let client = try LeafySupabase.shared.requireClient()
        let config = try LeafySupabase.shared.requireConfig()
        let session = try await client.auth.session
        let appTransaction = try await CampusAIManagedEntitlementClient.appTransactionPayload()

        var url = config.url
        url.appendPathComponent("functions")
        url.appendPathComponent("v1")
        url.appendPathComponent(config.campusAIFunctionName)

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue(config.publishableKey, forHTTPHeaderField: "apikey")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try providerJSONEncoder().encode(
            CampusAIManagedFunctionRequest(
                request: request,
                appTransactionID: appTransaction.appTransactionID,
                appTransactionJWS: appTransaction.jwsRepresentation,
                serviceMode: settings.serviceMode
            )
        )
        return urlRequest
    }

    static func chatCompletionsURL(baseURLString: String) throws -> URL {
        guard let trimmed = baseURLString.nonEmptyTrimmed,
              let baseURL = URL(string: trimmed),
              baseURL.scheme?.lowercased() == "https",
              baseURL.host != nil
        else {
            throw CampusAIServiceError.invalidBaseURL
        }
        return baseURL.appendingPathComponent("chat/completions")
    }

    static func chatCompletionsPayload(for request: CampusAIRequest) throws -> CampusAIChatCompletionsPayload {
        let userContent = CampusAIProviderUserContent(
            message: request.message,
            context: request.context,
            contextSettings: request.contextSettings,
            recentMessages: request.recentMessages.suffix(10).map { message in
                CampusAIProviderUserContent.RecentMessage(
                    role: message.role == .assistant ? "assistant" : "user",
                    text: message.text
                )
            }
        )
        guard let userContentString = String(data: try providerJSONEncoder().encode(userContent), encoding: .utf8) else {
            throw CampusAIServiceError.invalidProviderResponse
        }

        return CampusAIChatCompletionsPayload(
            model: request.model,
            messages: [
                .init(role: "system", content: systemPrompt(userPrompt: request.userSystemPrompt)),
                .init(role: "user", content: userContentString)
            ],
            stream: true,
            thinking: .enabled,
            streamOptions: .includeUsage,
            temperature: 0.2,
            maxTokens: 1800,
            user: nil
        )
    }

    static func systemPrompt(userPrompt: String) -> String {
        let customPrompt = userPrompt.nonEmptyTrimmed.map { String($0.prefix(3000)) }
        return [
            "你是 MyLeafy 的校园学习与生活助手，当前是测试功能。",
            "优先根据请求中提供的本机缓存或本地保存上下文回答；可以补充明确标注为一般建议的常识，但不要把常识伪装成本机数据。",
            "数据不足时直接说明缺少哪些上下文。",
            "不要声称读取了未提供的数据，不要声称读取了用户上传文件正文、图片像素、OCR、PDF、Word、PPT、表格或本地文件路径。",
            "社区内容只可当作用户当前设备已缓存的公开 feed 摘要，不要推断私信、身份资料或未缓存远端内容。",
            "医疗台账只能做整理、提醒、流程梳理和材料核对，不提供诊断、治疗、用药或医疗决策建议。",
            "回复必须是中文 Markdown。优先使用短标题、列表、加粗和清晰分段；不要输出 JSON，不要输出动作草稿。",
            customPrompt.map { "用户自定义偏好：\n\($0)" }
        ].compactMap { $0 }.joined(separator: "\n")
    }

    static func redactProviderError(_ value: String) -> String {
        value
            .replacingOccurrences(
                of: #"(?i)(bearer\s+)?[A-Za-z0-9]{24,}\.[A-Za-z0-9._-]+"#,
                with: "[redacted]",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"sk-[A-Za-z0-9_-]+"#,
                with: "sk-redacted",
                options: .regularExpression
            )
    }

    private static func providerJSONEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static func providerErrorBody(from bytes: URLSession.AsyncBytes) async throws -> String {
        var body = ""
        for try await line in bytes.lines {
            if !body.isEmpty {
                body += "\n"
            }
            body += line
            if body.count > 1000 {
                break
            }
        }
        return redactProviderError(body)
    }

    private static func providerBody(from bytes: URLSession.AsyncBytes, limit: Int = 2_000_000) async throws -> String {
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count > limit {
                break
            }
        }
        guard let body = String(data: data, encoding: .utf8) else {
            throw CampusAIServiceError.invalidProviderResponse
        }
        return body
    }

    static func providerEvents(from body: String) throws -> [CampusAIStreamEvent] {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw CampusAIServiceError.invalidProviderResponse
        }

        var parser = CampusAISSEParser()
        let parseData: Data
        if trimmed.hasPrefix("data:") || trimmed.contains("\ndata:") || trimmed.contains("\r\ndata:") {
            parseData = Data(body.utf8)
        } else if trimmed.hasPrefix("{") {
            let dataLines = trimmed
                .replacingOccurrences(of: "\r\n", with: "\n")
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { "data: \($0)" }
                .joined(separator: "\n")
            parseData = Data("\(dataLines)\n\ndata: [DONE]\n\n".utf8)
        } else {
            throw CampusAIServiceError.invalidProviderResponse
        }

        return try parser.append(parseData) + parser.finish()
    }

    private static func providerHTTPErrorMessage(statusCode: Int, body: String) -> String {
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedBody.isEmpty {
            return "AI 助手返回了 \(statusCode) 错误。"
        }
        return "AI 助手返回了 \(statusCode) 错误：\(trimmedBody)"
    }

    private static func managedHTTPErrorMessage(statusCode: Int, body: String) -> String {
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmedBody.data(using: .utf8),
           let payload = try? JSONDecoder().decode(CampusAIManagedErrorPayload.self, from: data),
           let error = payload.error?.nonEmptyTrimmed {
            return statusCode == 402 ? error : "Leafy 托管服务返回了 \(statusCode) 错误：\(error)"
        }
        if trimmedBody.isEmpty {
            return "Leafy 托管服务返回了 \(statusCode) 错误。"
        }
        return "Leafy 托管服务返回了 \(statusCode) 错误：\(trimmedBody)"
    }
}

nonisolated private struct CampusAIProviderUserContent: Encodable {
    let message: String
    let context: CampusAIContextPayload
    let contextSettings: CampusAIContextSettings
    let recentMessages: [RecentMessage]

    enum CodingKeys: String, CodingKey {
        case message
        case context
        case contextSettings = "context_settings"
        case recentMessages = "recent_messages"
    }

    struct RecentMessage: Encodable, Hashable {
        let role: String
        let text: String
    }
}

nonisolated private struct CampusAIManagedFunctionRequest: Encodable {
    let requestID: String
    let appTransactionID: String
    let appTransactionJWS: String
    let serviceMode: String
    let message: String
    let context: CampusAIContextPayload
    let recentMessages: [CampusAIChatMessage]
    let userSystemPrompt: String
    let contextSettings: CampusAIContextSettings

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case appTransactionID = "app_transaction_id"
        case appTransactionJWS = "app_transaction_jws"
        case serviceMode = "service_mode"
        case message
        case context
        case recentMessages = "recent_messages"
        case userSystemPrompt = "user_system_prompt"
        case contextSettings = "context_settings"
    }

    init(
        request: CampusAIRequest,
        appTransactionID: String,
        appTransactionJWS: String,
        serviceMode: CampusAIServiceMode
    ) {
        self.requestID = request.requestID.uuidString
        self.appTransactionID = appTransactionID
        self.appTransactionJWS = appTransactionJWS
        self.serviceMode = serviceMode.rawValue
        self.message = request.message
        self.context = request.context
        self.recentMessages = request.recentMessages
        self.userSystemPrompt = request.userSystemPrompt
        self.contextSettings = request.contextSettings
    }
}

nonisolated private struct CampusAIManagedErrorPayload: Decodable {
    let error: String?
}

nonisolated private extension String {
    var nonEmptyTrimmed: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func clampedForAIContext(_ limit: Int = 240) -> String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(max(limit - 1, 0))) + "…"
    }
}
