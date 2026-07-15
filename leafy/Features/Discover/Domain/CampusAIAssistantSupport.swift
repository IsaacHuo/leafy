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
    case timetableProcessing
    case honorRecords
    case comprehensiveQuality
    case teachingPlan
    case trainingProgram
    case emptyClassroom
    case campusHeatmap
    case studyTimeRecords
    case sunshineRun
    case fitnessTestRecords
    case sportsVenues
    case schoolCalendar
    case countdowns
    case medicalPolicy
    case medicalScenarioAssistant
    case medicalLedger

    var detailRoute: AcademicDetailRoute {
        switch self {
        case .grades: return .grades
        case .gradeAnalytics: return .gradeAnalytics
        case .examSchedule: return .examSchedule
        case .scheduleReports: return .scheduleReports
        case .customCountdowns: return .customCountdowns
        case .timetableProcessing: return .timetableProcessing
        case .honorRecords: return .honorRecords
        case .comprehensiveQuality: return .comprehensiveQuality
        case .teachingPlan: return .teachingPlan
        case .trainingProgram: return .trainingProgram
        case .emptyClassroom: return .emptyClassroom
        case .campusHeatmap: return .campusHeatmap
        case .studyTimeRecords: return .studyTimeRecords
        case .sunshineRun: return .sunshineRun
        case .fitnessTestRecords: return .fitnessTestRecords
        case .sportsVenues: return .sportsVenues
        case .schoolCalendar: return .schoolCalendar
        case .countdowns: return .countdowns
        case .medicalPolicy: return .medicalPolicy
        case .medicalScenarioAssistant: return .medicalScenarioAssistant
        case .medicalLedger: return .medicalLedger
        }
    }

    var title: String {
        switch self {
        case .grades: return "成绩查询"
        case .gradeAnalytics: return "成绩分析"
        case .examSchedule: return "考试安排"
        case .scheduleReports: return "日程推送"
        case .customCountdowns: return "自定日程"
        case .timetableProcessing: return "课表导入"
        case .honorRecords: return "荣誉记录"
        case .comprehensiveQuality: return "综测记录"
        case .teachingPlan: return "教学计划"
        case .trainingProgram: return "培养方案"
        case .emptyClassroom: return "空教室"
        case .campusHeatmap: return "校园热力"
        case .studyTimeRecords: return "学习记录"
        case .sunshineRun: return "阳光长跑"
        case .fitnessTestRecords: return "体测记录"
        case .sportsVenues: return "体育场馆"
        case .schoolCalendar: return "校历"
        case .countdowns: return "倒计时"
        case .medicalPolicy: return "医保政策"
        case .medicalScenarioAssistant: return "医疗流程助手"
        case .medicalLedger: return "医疗台账"
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

    enum CodingKeys: String, CodingKey {
        case route
        case countdownTitle
        case countdownTitleSnake = "countdown_title"
        case targetDate
        case targetDateSnake = "target_date"
        case week
        case dayOfWeek
        case dayOfWeekSnake = "day_of_week"
        case period
        case endPeriod
        case endPeriodSnake = "end_period"
        case title
        case location
        case note
        case minutesBefore
        case minutesBeforeSnake = "minutes_before"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        route = try container.decodeIfPresent(String.self, forKey: .route)
        countdownTitle = try container.decodeIfPresent(String.self, forKey: .countdownTitle)
            ?? container.decodeIfPresent(String.self, forKey: .countdownTitleSnake)
        targetDate = try container.decodeIfPresent(String.self, forKey: .targetDate)
            ?? container.decodeIfPresent(String.self, forKey: .targetDateSnake)
        week = try container.decodeIfPresent(Int.self, forKey: .week)
        dayOfWeek = try container.decodeIfPresent(Int.self, forKey: .dayOfWeek)
            ?? container.decodeIfPresent(Int.self, forKey: .dayOfWeekSnake)
        period = try container.decodeIfPresent(Int.self, forKey: .period)
        endPeriod = try container.decodeIfPresent(Int.self, forKey: .endPeriod)
            ?? container.decodeIfPresent(Int.self, forKey: .endPeriodSnake)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        location = try container.decodeIfPresent(String.self, forKey: .location)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        minutesBefore = try container.decodeIfPresent(Int.self, forKey: .minutesBefore)
            ?? container.decodeIfPresent(Int.self, forKey: .minutesBeforeSnake)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(route, forKey: .route)
        try container.encodeIfPresent(countdownTitle, forKey: .countdownTitle)
        try container.encodeIfPresent(targetDate, forKey: .targetDate)
        try container.encodeIfPresent(week, forKey: .week)
        try container.encodeIfPresent(dayOfWeek, forKey: .dayOfWeek)
        try container.encodeIfPresent(period, forKey: .period)
        try container.encodeIfPresent(endPeriod, forKey: .endPeriod)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(location, forKey: .location)
        try container.encodeIfPresent(note, forKey: .note)
        try container.encodeIfPresent(minutesBefore, forKey: .minutesBefore)
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
        normalized.title = normalized.title.nonEmptyTrimmed ?? "创建重要日期"
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
           (endPeriod < period || TimetablePeriodSchedule.slot(for: endPeriod) == nil) {
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

nonisolated struct CampusAIToolSupportedAction: Encodable, Hashable {
    var kind: String
    var requiredPayloadFields: [String]
    var allowedValues: [String: [String]]

    enum CodingKeys: String, CodingKey {
        case kind
        case requiredPayloadFields = "required_payload_fields"
        case allowedValues = "allowed_values"
    }
}

nonisolated struct CampusAIToolDescriptor: Identifiable, Hashable {
    var id: String
    var title: String
    var detail: String
    var systemImageName: String
    var actionKind: CampusAIActionKind?
    var toolName: String?
    var requiresConfirmation: Bool
}

nonisolated enum CampusAIToolRegistry {
    static let webSearch = CampusAIToolDescriptor(
        id: "web.search",
        title: "联网搜索",
        detail: "检索学校官方页面和公开来源。",
        systemImageName: "network",
        actionKind: nil,
        toolName: "web.search",
        requiresConfirmation: false
    )

    static let localRetrieval = CampusAIToolDescriptor(
        id: "local.retrieval",
        title: "本机检索",
        detail: "检索当前设备中的课程、考试、学习资料和台账元数据。",
        systemImageName: "internaldrive",
        actionKind: nil,
        toolName: "local.retrieval",
        requiresConfirmation: false
    )

    static let actionPlan = CampusAIToolDescriptor(
        id: "action.plan",
        title: "动作规划",
        detail: "把回答整理成用户确认后执行的 Leafy 动作。",
        systemImageName: "wand.and.stars",
        actionKind: nil,
        toolName: "action.plan",
        requiresConfirmation: false
    )

    static let openAcademicRoute = CampusAIToolDescriptor(
        id: CampusAIActionKind.openAcademicRoute.rawValue,
        title: "打开页面",
        detail: "打开 Leafy 内的指定校园页面。",
        systemImageName: "arrow.up.right.square",
        actionKind: .openAcademicRoute,
        toolName: nil,
        requiresConfirmation: true
    )

    static let createCountdown = CampusAIToolDescriptor(
        id: CampusAIActionKind.createCountdown.rawValue,
        title: "创建重要日期",
        detail: "创建本机保存的重要日期或倒计时。",
        systemImageName: "calendar.badge.clock",
        actionKind: .createCountdown,
        toolName: nil,
        requiresConfirmation: true
    )

    static let createTimetableReminder = CampusAIToolDescriptor(
        id: CampusAIActionKind.createTimetableReminder.rawValue,
        title: "创建课表提醒",
        detail: "根据周次、星期和节次创建课表提醒。",
        systemImageName: "bell.badge",
        actionKind: .createTimetableReminder,
        toolName: nil,
        requiresConfirmation: true
    )

    static var all: [CampusAIToolDescriptor] {
        [
            webSearch,
            localRetrieval,
            actionPlan,
            openAcademicRoute,
            createCountdown,
            createTimetableReminder
        ]
    }

    static var actionTools: [CampusAIToolDescriptor] {
        all.filter { $0.actionKind != nil }
    }

    static func descriptor(for actionKind: CampusAIActionKind?) -> CampusAIToolDescriptor? {
        guard let actionKind else { return nil }
        return actionTools.first { $0.actionKind == actionKind }
    }

    static func descriptor(forToolName toolName: String) -> CampusAIToolDescriptor? {
        all.first { $0.toolName == toolName || $0.id == toolName }
    }

    static func supportedActions() -> [CampusAIToolSupportedAction] {
        [
            CampusAIToolSupportedAction(
                kind: CampusAIActionKind.openAcademicRoute.rawValue,
                requiredPayloadFields: ["route"],
                allowedValues: [
                    "route": CampusAIAcademicRouteID.allCases.map(\.rawValue)
                ]
            ),
            CampusAIToolSupportedAction(
                kind: CampusAIActionKind.createCountdown.rawValue,
                requiredPayloadFields: ["countdownTitle", "targetDate"],
                allowedValues: [
                    "targetDate": ["yyyy-MM-dd"]
                ]
            ),
            CampusAIToolSupportedAction(
                kind: CampusAIActionKind.createTimetableReminder.rawValue,
                requiredPayloadFields: ["week", "dayOfWeek", "period", "title"],
                allowedValues: [
                    "week": ["1...\(SemesterConfig.supportedWeeks)"],
                    "dayOfWeek": ["1...7"],
                    "period": TimetablePeriodSchedule.slots.map { String($0.period) }
                ]
            )
        ]
    }
}

nonisolated struct CampusAIChatMessage: Codable, Hashable {
    let role: CampusAIMessageRole
    let text: String
}

nonisolated enum CampusAITimelineMutationPlan {
    static func removedMessageIDs(
        orderedMessageIDs: [UUID],
        targetID: UUID,
        includesTarget: Bool
    ) -> [UUID] {
        guard let index = orderedMessageIDs.firstIndex(of: targetID) else { return [] }
        let startIndex = includesTarget ? index : orderedMessageIDs.index(after: index)
        guard startIndex < orderedMessageIDs.endIndex else { return [] }
        return Array(orderedMessageIDs[startIndex...])
    }
}

nonisolated enum CampusAIProviderID: String, Codable, CaseIterable, Hashable, Identifiable {
    case deepSeek = "deepseek"

    var id: String { rawValue }
}

nonisolated enum CampusAIModelID: String, Codable, CaseIterable, Hashable, Identifiable {
    case flash
    case pro

    var id: String { rawValue }
}

nonisolated struct CampusAIModelDescriptor: Hashable, Identifiable {
    let id: CampusAIModelID
    let modelIdentifier: String
    let shortDisplayName: String
    let fullDisplayName: String
}

nonisolated enum CampusAIModelCatalog {
    static let flash = CampusAIModelDescriptor(
        id: .flash,
        modelIdentifier: "deepseek-v4-flash",
        shortDisplayName: "Flash",
        fullDisplayName: "DeepSeek V4 Flash"
    )
    static let pro = CampusAIModelDescriptor(
        id: .pro,
        modelIdentifier: "deepseek-v4-pro",
        shortDisplayName: "Pro",
        fullDisplayName: "DeepSeek V4 Pro"
    )
    static let all = [flash, pro]
    static let defaultModel = flash

    static func model(for id: CampusAIModelID) -> CampusAIModelDescriptor {
        all.first(where: { $0.id == id }) ?? defaultModel
    }
}

nonisolated enum CampusAIServiceMode: String, Codable, CaseIterable, Hashable, Identifiable {
    case ownAPIKey
    case leafyManaged

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ownAPIKey:
            return "自备 DeepSeek API Key"
        case .leafyManaged:
            return "Leafy AI 服务"
        }
    }

    var shortTitle: String {
        switch self {
        case .ownAPIKey:
            return "DeepSeek Key"
        case .leafyManaged:
            return "Leafy AI"
        }
    }
}

nonisolated enum CampusAIAgentMode: String, Codable, Hashable {
    case auto
    case off
}

nonisolated struct CampusAIProviderDescriptor: Hashable, Identifiable {
    let id: CampusAIProviderID
    let displayName: String
    let modelIdentifier: String
    let modelDisplayName: String
    let baseURLString: String
    let apiKeyManagementURL: URL
}

nonisolated enum CampusAIProviderCatalog {
    static let deepSeek = CampusAIProviderDescriptor(
        id: .deepSeek,
        displayName: "DeepSeek",
        modelIdentifier: "deepseek-v4-flash",
        modelDisplayName: "DeepSeek V4 Flash",
        baseURLString: "https://api.deepseek.com",
        apiKeyManagementURL: URL(string: "https://platform.deepseek.com/api_keys")!
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
    var selectedModelID: CampusAIModelID
    var systemPrompt: String
    var contextSettings: CampusAIContextSettings
    var webSearchEnabled: Bool

    static var defaultValue: CampusAIUserSettings {
        CampusAIUserSettings(
            serviceMode: .leafyManaged,
            selectedProviderID: CampusAIProviderCatalog.defaultProvider.id,
            selectedModelID: CampusAIModelCatalog.defaultModel.id,
            systemPrompt: CampusAISettingsStore.defaultSystemPrompt,
            contextSettings: .defaultValue,
            webSearchEnabled: true
        )
    }

    init(
        serviceMode: CampusAIServiceMode = .leafyManaged,
        selectedProviderID: CampusAIProviderID = CampusAIProviderCatalog.defaultProvider.id,
        selectedModelID: CampusAIModelID = CampusAIModelCatalog.defaultModel.id,
        systemPrompt: String,
        contextSettings: CampusAIContextSettings,
        webSearchEnabled: Bool = true
    ) {
        self.serviceMode = serviceMode
        self.selectedProviderID = selectedProviderID
        self.selectedModelID = selectedModelID
        self.systemPrompt = systemPrompt
        self.contextSettings = contextSettings
        self.webSearchEnabled = webSearchEnabled
    }

    enum CodingKeys: String, CodingKey {
        case serviceMode
        case selectedProviderID
        case selectedModelID
        case systemPrompt
        case contextSettings
        case webSearchEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        serviceMode = try container.decodeIfPresent(CampusAIServiceMode.self, forKey: .serviceMode) ?? .leafyManaged
        selectedProviderID = try container.decodeIfPresent(CampusAIProviderID.self, forKey: .selectedProviderID) ??
            CampusAIProviderCatalog.defaultProvider.id
        selectedModelID = try container.decodeIfPresent(CampusAIModelID.self, forKey: .selectedModelID) ??
            CampusAIModelCatalog.defaultModel.id
        systemPrompt = try container.decodeIfPresent(String.self, forKey: .systemPrompt) ??
            CampusAISettingsStore.defaultSystemPrompt
        contextSettings = try container.decodeIfPresent(CampusAIContextSettings.self, forKey: .contextSettings) ??
            .defaultValue
        webSearchEnabled = try container.decodeIfPresent(Bool.self, forKey: .webSearchEnabled) ?? true
    }

    var selectedProvider: CampusAIProviderDescriptor {
        CampusAIProviderCatalog.provider(for: selectedProviderID)
    }

    var selectedModel: CampusAIModelDescriptor {
        CampusAIModelCatalog.model(for: selectedModelID)
    }

    var effectiveSystemPrompt: String {
        let trimmed = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? CampusAISettingsStore.defaultSystemPrompt : String(trimmed.prefix(3000))
    }

    var normalizedForLocalRuntime: CampusAIUserSettings {
        self
    }
}

nonisolated struct CampusAICapabilitySet: Codable, Hashable {
    var nonWebAgentEnabled: Bool
    var localSearchEnabled: Bool
    var actionPlanningEnabled: Bool
    var artifactGenerationEnabled: Bool
    var webSearchEnabled: Bool
    var officialDocumentSearchEnabled: Bool

    static let disabled = CampusAICapabilitySet(
        nonWebAgentEnabled: false,
        localSearchEnabled: false,
        actionPlanningEnabled: false,
        artifactGenerationEnabled: false,
        webSearchEnabled: false,
        officialDocumentSearchEnabled: false
    )

    init(
        nonWebAgentEnabled: Bool,
        localSearchEnabled: Bool,
        actionPlanningEnabled: Bool,
        artifactGenerationEnabled: Bool,
        webSearchEnabled: Bool,
        officialDocumentSearchEnabled: Bool
    ) {
        self.nonWebAgentEnabled = nonWebAgentEnabled
        self.localSearchEnabled = localSearchEnabled
        self.actionPlanningEnabled = actionPlanningEnabled
        self.artifactGenerationEnabled = artifactGenerationEnabled
        self.webSearchEnabled = webSearchEnabled
        self.officialDocumentSearchEnabled = officialDocumentSearchEnabled
    }

    init(serviceMode: CampusAIServiceMode, webSearchEnabled requestedWebSearch: Bool) {
        let canUseWeb = requestedWebSearch
        self.init(
            nonWebAgentEnabled: true,
            localSearchEnabled: true,
            actionPlanningEnabled: true,
            artifactGenerationEnabled: true,
            webSearchEnabled: canUseWeb,
            officialDocumentSearchEnabled: canUseWeb
        )
    }

    init(settings: CampusAIUserSettings) {
        self.init(serviceMode: settings.serviceMode, webSearchEnabled: settings.webSearchEnabled)
    }

    enum CodingKeys: String, CodingKey {
        case nonWebAgentEnabled
        case nonWebAgentEnabledSnake = "non_web_agent_enabled"
        case localSearchEnabled
        case localSearchEnabledSnake = "local_search_enabled"
        case actionPlanningEnabled
        case actionPlanningEnabledSnake = "action_planning_enabled"
        case artifactGenerationEnabled
        case artifactGenerationEnabledSnake = "artifact_generation_enabled"
        case webSearchEnabled
        case webSearchEnabledSnake = "web_search_enabled"
        case officialDocumentSearchEnabled
        case officialDocumentSearchEnabledSnake = "official_document_search_enabled"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        nonWebAgentEnabled = try container.decodeIfPresent(Bool.self, forKey: .nonWebAgentEnabled)
            ?? container.decodeIfPresent(Bool.self, forKey: .nonWebAgentEnabledSnake)
            ?? false
        localSearchEnabled = try container.decodeIfPresent(Bool.self, forKey: .localSearchEnabled)
            ?? container.decodeIfPresent(Bool.self, forKey: .localSearchEnabledSnake)
            ?? false
        actionPlanningEnabled = try container.decodeIfPresent(Bool.self, forKey: .actionPlanningEnabled)
            ?? container.decodeIfPresent(Bool.self, forKey: .actionPlanningEnabledSnake)
            ?? false
        artifactGenerationEnabled = try container.decodeIfPresent(Bool.self, forKey: .artifactGenerationEnabled)
            ?? container.decodeIfPresent(Bool.self, forKey: .artifactGenerationEnabledSnake)
            ?? false
        webSearchEnabled = try container.decodeIfPresent(Bool.self, forKey: .webSearchEnabled)
            ?? container.decodeIfPresent(Bool.self, forKey: .webSearchEnabledSnake)
            ?? false
        officialDocumentSearchEnabled = try container.decodeIfPresent(Bool.self, forKey: .officialDocumentSearchEnabled)
            ?? container.decodeIfPresent(Bool.self, forKey: .officialDocumentSearchEnabledSnake)
            ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(nonWebAgentEnabled, forKey: .nonWebAgentEnabled)
        try container.encode(localSearchEnabled, forKey: .localSearchEnabled)
        try container.encode(actionPlanningEnabled, forKey: .actionPlanningEnabled)
        try container.encode(artifactGenerationEnabled, forKey: .artifactGenerationEnabled)
        try container.encode(webSearchEnabled, forKey: .webSearchEnabled)
        try container.encode(officialDocumentSearchEnabled, forKey: .officialDocumentSearchEnabled)
    }
}

nonisolated enum CampusAISettingsStore {
    static let defaultSystemPrompt = """
    你是 Leafy 的通用 AI 助手。请用中文回答，默认简短直接，先给结论和下一步；相关时可以结合用户允许的本机数据提供更具体的建议。使用清晰的 Markdown 层级：不同主题换段或使用短标题，三项以上并列信息使用列表，不要用 emoji、连续加粗或挤在一段中的序号模拟结构。信息不足时直接说缺什么，不要编造。
    """

    static let previousGeneralDefaultSystemPrompt = """
    你是 Leafy 的通用 AI 助手。请用中文回答，默认简短直接，先给结论和下一步；相关时可以结合用户允许的本机数据提供更具体的建议。信息不足时直接说缺什么，不要编造。
    """

    static let legacyCampusDefaultSystemPrompt = """
    请用中文回答，默认简短直接，先给结论和下一步。可以围绕校园学习、生活安排和个人事项整理建议；信息不足时直接说缺什么，不要编造。
    """

    private static let storageKey = "campusAI.userSettings.v4"
    private static let previousStorageKey = "campusAI.userSettings.v3"
    private static let olderStorageKey = "campusAI.userSettings.v2"
    private static let legacyStorageKey = "campusAI.userSettings.v1"

    static func load(userDefaults: UserDefaults = .standard) -> CampusAIUserSettings {
        if let data = userDefaults.data(forKey: storageKey),
           let settings = try? JSONDecoder().decode(CampusAIUserSettings.self, from: data) {
            let normalized = migrateDefaultPrompt(in: settings.normalizedForLocalRuntime)
            if normalized != settings {
                save(normalized, userDefaults: userDefaults)
            }
            return normalized
        }

        if let data = userDefaults.data(forKey: previousStorageKey),
           var settings = try? JSONDecoder().decode(CampusAIUserSettings.self, from: data) {
            settings.serviceMode = .leafyManaged
            let migrated = migrateDefaultPrompt(in: settings)
            save(migrated, userDefaults: userDefaults)
            userDefaults.removeObject(forKey: previousStorageKey)
            return migrated
        }

        if let data = userDefaults.data(forKey: olderStorageKey),
           var settings = try? JSONDecoder().decode(CampusAIUserSettings.self, from: data) {
            settings.serviceMode = .leafyManaged
            settings.webSearchEnabled = true
            let migrated = migrateDefaultPrompt(in: settings)
            save(migrated, userDefaults: userDefaults)
            userDefaults.removeObject(forKey: olderStorageKey)
            return migrated
        }

        guard let legacyData = userDefaults.data(forKey: legacyStorageKey),
              let legacySettings = try? JSONDecoder().decode(LegacyUserSettings.self, from: legacyData)
        else {
            return .defaultValue
        }
        let migrated = migrateDefaultPrompt(in: CampusAIUserSettings(
            serviceMode: .leafyManaged,
            systemPrompt: legacySettings.systemPrompt ?? defaultSystemPrompt,
            contextSettings: legacySettings.contextSettings ?? .defaultValue
        ))
        save(migrated, userDefaults: userDefaults)
        userDefaults.removeObject(forKey: legacyStorageKey)
        return migrated
    }

    @discardableResult
    static func save(_ settings: CampusAIUserSettings, userDefaults: UserDefaults = .standard) -> Bool {
        do {
            let data = try JSONEncoder().encode(settings)
            userDefaults.set(data, forKey: storageKey)
            return true
        } catch {
            CampusAIDiagnostics.persistenceFailure(error, operation: "settings.save")
            return false
        }
    }

    static func reset(userDefaults: UserDefaults = .standard) -> CampusAIUserSettings {
        userDefaults.removeObject(forKey: storageKey)
        userDefaults.removeObject(forKey: previousStorageKey)
        userDefaults.removeObject(forKey: olderStorageKey)
        userDefaults.removeObject(forKey: legacyStorageKey)
        return .defaultValue
    }

    private static func migrateDefaultPrompt(in settings: CampusAIUserSettings) -> CampusAIUserSettings {
        let storedPrompt = settings.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let knownDefaults = [legacyCampusDefaultSystemPrompt, previousGeneralDefaultSystemPrompt]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard knownDefaults.contains(storedPrompt) else { return settings }
        var migrated = settings
        migrated.systemPrompt = defaultSystemPrompt
        return migrated
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
    let agentMode: CampusAIAgentMode
    let webSearchEnabled: Bool
    let capabilities: CampusAICapabilitySet
    let localRetrieval: CampusAILocalRetrievalPayload
    let outputMode: CampusAIOutputMode

    enum CodingKeys: String, CodingKey {
        case requestID
        case message
        case context
        case recentMessages
        case model
        case userSystemPrompt
        case contextSettings
        case agentMode
        case webSearchEnabled
        case capabilities
        case localRetrieval
        case outputMode
    }

    init(
        requestID: UUID = UUID(),
        message: String,
        context: CampusAIContextPayload,
        recentMessages: [CampusAIChatMessage],
        model: String = CampusAIProviderCatalog.defaultProvider.modelIdentifier,
        userSystemPrompt: String = CampusAISettingsStore.defaultSystemPrompt,
        contextSettings: CampusAIContextSettings = .defaultValue,
        agentMode: CampusAIAgentMode = .auto,
        webSearchEnabled: Bool = false,
        capabilities: CampusAICapabilitySet = .disabled,
        localRetrieval: CampusAILocalRetrievalPayload = .empty(query: ""),
        outputMode: CampusAIOutputMode = .automatic
    ) {
        self.requestID = requestID
        self.message = message
        self.context = context
        self.recentMessages = recentMessages
        self.model = model
        self.userSystemPrompt = String(userSystemPrompt.prefix(3000))
        self.contextSettings = contextSettings
        self.agentMode = agentMode
        self.webSearchEnabled = webSearchEnabled
        self.capabilities = capabilities
        self.localRetrieval = localRetrieval
        self.outputMode = outputMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        requestID = try container.decodeIfPresent(UUID.self, forKey: .requestID) ?? UUID()
        message = try container.decode(String.self, forKey: .message)
        context = try container.decode(CampusAIContextPayload.self, forKey: .context)
        recentMessages = try container.decodeIfPresent([CampusAIChatMessage].self, forKey: .recentMessages) ?? []
        model = try container.decodeIfPresent(String.self, forKey: .model)
            ?? CampusAIProviderCatalog.defaultProvider.modelIdentifier
        userSystemPrompt = try container.decodeIfPresent(String.self, forKey: .userSystemPrompt)
            ?? CampusAISettingsStore.defaultSystemPrompt
        contextSettings = try container.decodeIfPresent(CampusAIContextSettings.self, forKey: .contextSettings)
            ?? .defaultValue
        agentMode = try container.decodeIfPresent(CampusAIAgentMode.self, forKey: .agentMode) ?? .auto
        webSearchEnabled = try container.decodeIfPresent(Bool.self, forKey: .webSearchEnabled) ?? false
        capabilities = try container.decodeIfPresent(CampusAICapabilitySet.self, forKey: .capabilities) ?? .disabled
        localRetrieval = try container.decodeIfPresent(CampusAILocalRetrievalPayload.self, forKey: .localRetrieval)
            ?? .empty(query: message)
        outputMode = try container.decodeIfPresent(CampusAIOutputMode.self, forKey: .outputMode) ?? .automatic
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(requestID, forKey: .requestID)
        try container.encode(message, forKey: .message)
        try container.encode(context, forKey: .context)
        try container.encode(recentMessages, forKey: .recentMessages)
        try container.encode(model, forKey: .model)
        try container.encode(userSystemPrompt, forKey: .userSystemPrompt)
        try container.encode(contextSettings, forKey: .contextSettings)
        try container.encode(agentMode, forKey: .agentMode)
        try container.encode(webSearchEnabled, forKey: .webSearchEnabled)
        try container.encode(capabilities, forKey: .capabilities)
        try container.encode(localRetrieval, forKey: .localRetrieval)
        try container.encode(outputMode, forKey: .outputMode)
    }
}

nonisolated enum CampusAILocalKnowledgeDomain: String, Codable, CaseIterable, Hashable, Identifiable {
    case schedule
    case learning
    case academics
    case postgraduateCareer
    case fitnessSports
    case honorsQuality
    case medical
    case community

    var id: String { rawValue }

    var title: String {
        switch self {
        case .schedule: return "时间日程"
        case .learning: return "学习资料"
        case .academics: return "学业成绩"
        case .postgraduateCareer: return "考研职业"
        case .fitnessSports: return "体育体测"
        case .honorsQuality: return "荣誉综测"
        case .medical: return "医疗台账"
        case .community: return "社区公开摘要"
        }
    }

    var intentKeywords: [String] {
        switch self {
        case .schedule:
            return ["日程", "安排", "课表", "考试", "提醒", "待办", "倒计时", "重要日期", "自定日程", "今天", "明天", "本周"]
        case .learning:
            return ["学习", "资料", "任务", "项目", "复习", "笔记", "材料", "自习"]
        case .academics:
            return ["成绩", "绩点", "gpa", "排名", "学分", "培养方案", "教学计划", "毕业"]
        case .postgraduateCareer:
            return ["考研", "保研", "推免", "职业", "实习", "简历", "投递", "目标院校"]
        case .fitnessSports:
            return ["体育", "体测", "长跑", "阳光", "运动", "场馆", "跑步"]
        case .honorsQuality:
            return ["荣誉", "综测", "综合素质", "证明", "奖项", "材料"]
        case .medical:
            return ["医疗", "医保", "报销", "就诊", "医院", "台账", "材料", "发票"]
        case .community:
            return ["社区", "帖子", "动态", "同学", "公开", "讨论"]
        }
    }
}

nonisolated struct CampusAILocalKnowledgeResult: Identifiable, Codable, Hashable {
    var id: String
    var domain: CampusAILocalKnowledgeDomain
    var title: String
    var summary: String
    var sourceID: String
    var routeHint: String?
    var updatedAt: String?
    var score: Int

    enum CodingKeys: String, CodingKey {
        case id
        case domain
        case title
        case summary
        case sourceID
        case sourceIDSnake = "source_id"
        case routeHint
        case routeHintSnake = "route_hint"
        case updatedAt
        case updatedAtSnake = "updated_at"
        case score
    }

    init(
        id: String,
        domain: CampusAILocalKnowledgeDomain,
        title: String,
        summary: String,
        sourceID: String,
        routeHint: String? = nil,
        updatedAt: String? = nil,
        score: Int = 0
    ) {
        self.id = id
        self.domain = domain
        self.title = title
        self.summary = summary
        self.sourceID = sourceID
        self.routeHint = routeHint
        self.updatedAt = updatedAt
        self.score = score
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        domain = try container.decodeIfPresent(CampusAILocalKnowledgeDomain.self, forKey: .domain) ?? .academics
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
        sourceID = try container.decodeIfPresent(String.self, forKey: .sourceID)
            ?? container.decodeIfPresent(String.self, forKey: .sourceIDSnake)
            ?? id
        routeHint = try container.decodeIfPresent(String.self, forKey: .routeHint)
            ?? container.decodeIfPresent(String.self, forKey: .routeHintSnake)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
            ?? container.decodeIfPresent(String.self, forKey: .updatedAtSnake)
        score = try container.decodeIfPresent(Int.self, forKey: .score) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(domain, forKey: .domain)
        try container.encode(title, forKey: .title)
        try container.encode(summary, forKey: .summary)
        try container.encode(sourceID, forKey: .sourceID)
        try container.encodeIfPresent(routeHint, forKey: .routeHint)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
        try container.encode(score, forKey: .score)
    }
}

nonisolated struct CampusAILocalRetrievalPayload: Codable, Hashable {
    var query: String
    var generatedAt: String
    var results: [CampusAILocalKnowledgeResult]

    var isEmpty: Bool { results.isEmpty }

    enum CodingKeys: String, CodingKey {
        case query
        case generatedAt
        case generatedAtSnake = "generated_at"
        case results
    }

    init(query: String, generatedAt: String = ISO8601DateFormatter().string(from: Date()), results: [CampusAILocalKnowledgeResult]) {
        self.query = query
        self.generatedAt = generatedAt
        self.results = results
    }

    static func empty(query: String) -> CampusAILocalRetrievalPayload {
        CampusAILocalRetrievalPayload(query: query, results: [])
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        query = try container.decodeIfPresent(String.self, forKey: .query) ?? ""
        generatedAt = try container.decodeIfPresent(String.self, forKey: .generatedAt)
            ?? container.decodeIfPresent(String.self, forKey: .generatedAtSnake)
            ?? ""
        results = try container.decodeIfPresent([CampusAILocalKnowledgeResult].self, forKey: .results) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(query, forKey: .query)
        try container.encode(generatedAt, forKey: .generatedAt)
        try container.encode(results, forKey: .results)
    }
}

nonisolated enum CampusAILocalKnowledgeIndex {
    private struct Candidate {
        var domain: CampusAILocalKnowledgeDomain
        var title: String
        var summary: String
        var sourceID: String
        var routeHint: String?
        var updatedAt: String?
        var baseScore: Int
    }

    static let defaultMaxResults = 12
    static let defaultCharacterBudget = 6_000

    static func search(
        query: String,
        context: CampusAIContextPayload,
        maxResults: Int = defaultMaxResults,
        characterBudget: Int = defaultCharacterBudget
    ) -> CampusAILocalRetrievalPayload {
        let trimmedQuery = query.nonEmptyTrimmed ?? query
        let candidates = buildCandidates(from: context)
        guard !candidates.isEmpty, maxResults > 0, characterBudget > 0 else {
            return .empty(query: trimmedQuery)
        }

        let scored = candidates.compactMap { candidate -> CampusAILocalKnowledgeResult? in
            let score = relevanceScore(candidate: candidate, query: trimmedQuery)
            guard score > 0 else { return nil }
            return CampusAILocalKnowledgeResult(
                id: stableID(domain: candidate.domain, sourceID: candidate.sourceID),
                domain: candidate.domain,
                title: candidate.title.clampedForAIContext(100),
                summary: candidate.summary.clampedForAIContext(520),
                sourceID: candidate.sourceID,
                routeHint: candidate.routeHint,
                updatedAt: candidate.updatedAt,
                score: score
            )
        }
        .sorted {
            if $0.score != $1.score {
                return $0.score > $1.score
            }
            return $0.title < $1.title
        }

        return CampusAILocalRetrievalPayload(
            query: trimmedQuery,
            results: fit(scored, maxResults: maxResults, characterBudget: characterBudget)
        )
    }

    private static func buildCandidates(from context: CampusAIContextPayload) -> [Candidate] {
        var candidates: [Candidate] = []

        for (index, course) in context.timetable.today.enumerated() {
            candidates.append(candidate(
                domain: .schedule,
                title: "今日课程：\(course.name)",
                summary: join([
                    "第\(periodText(course.periods))节",
                    weekdayText(course.dayOfWeek),
                    course.room.nonEmptyTrimmed,
                    course.teacher.nonEmptyTrimmed.map { "教师：\($0)" }
                ]),
                sourceID: "timetable.today.\(index)",
                routeHint: CampusAIAcademicRouteID.examSchedule.rawValue,
                baseScore: 18
            ))
        }

        for (index, course) in context.timetable.currentWeek.prefix(40).enumerated() {
            candidates.append(candidate(
                domain: .schedule,
                title: "本周课程：\(course.name)",
                summary: join([
                    weekdayText(course.dayOfWeek),
                    "第\(periodText(course.periods))节",
                    course.room.nonEmptyTrimmed,
                    course.teacher.nonEmptyTrimmed.map { "教师：\($0)" },
                    course.weeks.isEmpty ? nil : "周次：\(course.weeks.map(String.init).joined(separator: ","))"
                ]),
                sourceID: "timetable.week.\(index)",
                routeHint: CampusAIAcademicRouteID.examSchedule.rawValue,
                baseScore: 8
            ))
        }

        for (index, exam) in context.exams.enumerated() {
            candidates.append(candidate(
                domain: .schedule,
                title: "考试：\(exam.name)",
                summary: join([exam.date, "\(exam.start)-\(exam.end)", exam.location.nonEmptyTrimmed]),
                sourceID: "exam.\(index)",
                routeHint: CampusAIAcademicRouteID.examSchedule.rawValue,
                baseScore: 24
            ))
        }

        for (index, countdown) in context.countdowns.enumerated() {
            candidates.append(candidate(
                domain: .schedule,
                title: "重要日期：\(countdown.title)",
                summary: "目标日期：\(countdown.targetDate)",
                sourceID: "countdown.\(index)",
                routeHint: CampusAIAcademicRouteID.customCountdowns.rawValue,
                baseScore: 18
            ))
        }

        for (index, reminder) in context.timetable.cellReminders.enumerated() {
            candidates.append(candidate(
                domain: .schedule,
                title: "课表提醒：\(reminder.title)",
                summary: join([
                    "第\(reminder.week)周",
                    weekdayText(reminder.dayOfWeek),
                    "第\(reminder.period)\(reminder.endPeriod.map { "-\($0)" } ?? "")节",
                    reminder.location?.nonEmptyTrimmed,
                    reminder.note?.nonEmptyTrimmed
                ]),
                sourceID: "timetable.reminder.\(index)",
                routeHint: CampusAIAcademicRouteID.examSchedule.rawValue,
                updatedAt: reminder.updatedAt,
                baseScore: 18
            ))
        }

        for (index, note) in context.timetable.courseNotes.enumerated() {
            candidates.append(candidate(
                domain: .schedule,
                title: "课程备注：\(note.courseName)",
                summary: note.text,
                sourceID: "course.note.\(index)",
                routeHint: CampusAIAcademicRouteID.examSchedule.rawValue,
                updatedAt: note.updatedAt,
                baseScore: 12
            ))
        }

        for (index, project) in context.learningWorkspace.projects.enumerated() {
            candidates.append(candidate(
                domain: .learning,
                title: "学习空间：\(project.title)",
                summary: join([project.kind.nonEmptyTrimmed, project.goal.nonEmptyTrimmed, project.isArchived ? "已归档" : "进行中"]),
                sourceID: "learning.project.\(index)",
                updatedAt: project.updatedAt,
                baseScore: 16
            ))
        }

        for (index, task) in context.learningWorkspace.tasks.enumerated() {
            candidates.append(candidate(
                domain: .learning,
                title: "学习任务：\(task.title)",
                summary: join([
                    task.category.nonEmptyTrimmed,
                    task.dueAt.map { "截止：\($0)" },
                    task.isCompleted ? "已完成" : "未完成",
                    task.note.nonEmptyTrimmed
                ]),
                sourceID: "learning.task.\(index)",
                updatedAt: task.updatedAt,
                baseScore: task.isCompleted ? 12 : 22
            ))
        }

        for (index, material) in context.learningWorkspace.materials.enumerated() {
            candidates.append(fileCandidate(
                domain: .learning,
                prefix: "学习资料",
                file: material,
                sourceID: "learning.material.\(index)",
                baseScore: 16
            ))
        }

        for (index, record) in context.learningWorkspace.studyRecords.enumerated() {
            candidates.append(candidate(
                domain: .learning,
                title: "学习记录：\(record.content)",
                summary: join([
                    record.category.nonEmptyTrimmed,
                    record.location.nonEmptyTrimmed,
                    "开始：\(record.startedAt)",
                    "时长：\(record.minutes) 分钟",
                    record.note.nonEmptyTrimmed
                ]),
                sourceID: "study.record.\(index)",
                baseScore: 12
            ))
        }

        for (index, grade) in context.grades.recentCourses.enumerated() {
            candidates.append(candidate(
                domain: .academics,
                title: "成绩：\(grade.name)",
                summary: join([grade.term.nonEmptyTrimmed, "成绩：\(grade.score)", "学分：\(grade.credit)", grade.type.nonEmptyTrimmed]),
                sourceID: "grade.course.\(index)",
                routeHint: CampusAIAcademicRouteID.grades.rawValue,
                baseScore: 18
            ))
        }

        for (index, ranking) in context.grades.rankings.enumerated() {
            let rankText = ranking.rank.map { "排名：\($0)" }
            let totalText = ranking.totalCount.map { "总人数：\($0)" }
            let percentileText = ranking.percentile.map { "百分位：\(Int(($0 * 100).rounded()))%" }
            candidates.append(candidate(
                domain: .academics,
                title: "成绩排名：\(ranking.term)",
                summary: join([ranking.range.nonEmptyTrimmed, ranking.metric.nonEmptyTrimmed, rankText, totalText, percentileText]),
                sourceID: "grade.ranking.\(index)",
                routeHint: CampusAIAcademicRouteID.gradeAnalytics.rawValue,
                baseScore: 20
            ))
        }

        for (index, plan) in context.teachingPlan.enumerated() {
            candidates.append(candidate(
                domain: .academics,
                title: "教学计划：\(plan.term)",
                summary: join(["总学分：\(plan.totalCredits)", plan.courses.prefix(12).joined(separator: "、")]),
                sourceID: "teaching.plan.\(index)",
                routeHint: CampusAIAcademicRouteID.teachingPlan.rawValue,
                baseScore: 16
            ))
        }

        if let trainingProgram = context.trainingProgram {
            candidates.append(candidate(
                domain: .academics,
                title: trainingProgram.title,
                summary: join([
                    trainingProgram.creditRequirements.prefix(8).joined(separator: "；"),
                    trainingProgram.sections.prefix(4).joined(separator: "；")
                ]),
                sourceID: "training.program",
                routeHint: CampusAIAcademicRouteID.trainingProgram.rawValue,
                baseScore: 18
            ))
        }

        for (index, target) in context.postgraduateAndCareer.postgraduateTargets.enumerated() {
            candidates.append(candidate(
                domain: .postgraduateCareer,
                title: "考研目标：\(join([target.school.nonEmptyTrimmed, target.unit.nonEmptyTrimmed, target.major.nonEmptyTrimmed], separator: " "))",
                summary: join([
                    "年份：\(target.examYear)",
                    target.direction.nonEmptyTrimmed,
                    target.subjects.nonEmptyTrimmed,
                    target.scoreAndPlanNote.nonEmptyTrimmed,
                    target.personalNote.nonEmptyTrimmed,
                    target.state.nonEmptyTrimmed
                ]),
                sourceID: "postgraduate.target.\(index)",
                updatedAt: target.updatedAt,
                baseScore: 18
            ))
        }

        for (index, task) in context.postgraduateAndCareer.careerTasks.enumerated() {
            candidates.append(candidate(
                domain: .postgraduateCareer,
                title: "职业任务：\(task.title)",
                summary: join([
                    task.dueAt.map { "截止：\($0)" },
                    task.isCompleted ? "已完成" : "未完成",
                    task.note.nonEmptyTrimmed
                ]),
                sourceID: "career.task.\(index)",
                updatedAt: task.updatedAt,
                baseScore: task.isCompleted ? 12 : 20
            ))
        }

        for (index, opportunity) in context.postgraduateAndCareer.opportunities.enumerated() {
            candidates.append(candidate(
                domain: .postgraduateCareer,
                title: "机会：\(opportunity.title)",
                summary: join([opportunity.organization.nonEmptyTrimmed, opportunity.status.nonEmptyTrimmed, opportunity.note.nonEmptyTrimmed]),
                sourceID: "career.opportunity.\(index)",
                updatedAt: opportunity.updatedAt,
                baseScore: 14
            ))
        }

        for (index, resume) in context.postgraduateAndCareer.resumes.enumerated() {
            candidates.append(fileCandidate(
                domain: .postgraduateCareer,
                prefix: "简历资料",
                file: resume,
                sourceID: "career.resume.\(index)",
                baseScore: 12
            ))
        }

        for (index, test) in context.honorsFitnessQuality.fitnessTests.enumerated() {
            candidates.append(candidate(
                domain: .fitnessSports,
                title: "体测：\(test.item)",
                summary: join([test.value.nonEmptyTrimmed, test.testedAt.nonEmptyTrimmed, test.note.nonEmptyTrimmed]),
                sourceID: "fitness.test.\(index)",
                routeHint: CampusAIAcademicRouteID.fitnessTestRecords.rawValue,
                baseScore: 18
            ))
        }

        for (index, honor) in context.honorsFitnessQuality.honors.enumerated() {
            candidates.append(fileCandidate(
                domain: .honorsQuality,
                prefix: "荣誉记录",
                file: honor,
                sourceID: "honor.\(index)",
                routeHint: CampusAIAcademicRouteID.honorRecords.rawValue,
                baseScore: 16
            ))
        }

        for (index, record) in context.honorsFitnessQuality.comprehensiveQualityRecords.enumerated() {
            candidates.append(candidate(
                domain: .honorsQuality,
                title: "综测记录：\(record.collegeName)",
                summary: join([
                    record.cohort.nonEmptyTrimmed,
                    record.academicStandardScore.map { "学业标准分：\($0)" },
                    record.officialQualityScore.map { "素质分：\($0)" },
                    record.officialCompositeScore.map { "综合分：\($0)" },
                    record.note.nonEmptyTrimmed
                ]),
                sourceID: "quality.record.\(index)",
                routeHint: CampusAIAcademicRouteID.comprehensiveQuality.rawValue,
                updatedAt: record.updatedAt,
                baseScore: 18
            ))
        }

        for (index, component) in context.honorsFitnessQuality.comprehensiveQualityComponents.enumerated() {
            candidates.append(candidate(
                domain: .honorsQuality,
                title: "综测项目：\(component.component)",
                summary: join([
                    component.collegeName.nonEmptyTrimmed,
                    component.cohort.nonEmptyTrimmed,
                    component.rawScore.map { "原始分：\($0)" },
                    component.officialStandardScore.map { "标准分：\($0)" },
                    component.materialReady ? "材料已准备" : "材料未标记完成",
                    component.note.nonEmptyTrimmed
                ]),
                sourceID: "quality.component.\(index)",
                routeHint: CampusAIAcademicRouteID.comprehensiveQuality.rawValue,
                updatedAt: component.updatedAt,
                baseScore: 16
            ))
        }

        for (index, evidence) in context.honorsFitnessQuality.comprehensiveQualityEvidence.enumerated() {
            candidates.append(fileCandidate(
                domain: .honorsQuality,
                prefix: "综测证明",
                file: evidence,
                sourceID: "quality.evidence.\(index)",
                routeHint: CampusAIAcademicRouteID.comprehensiveQuality.rawValue,
                baseScore: 14
            ))
        }

        for (index, entry) in context.medicalLedger.entries.enumerated() {
            candidates.append(candidate(
                domain: .medical,
                title: "医疗台账：\(entry.hospitalName.nonEmptyTrimmed ?? "就诊记录")",
                summary: join([
                    entry.visitDate.nonEmptyTrimmed,
                    entry.department.nonEmptyTrimmed,
                    entry.scenario.nonEmptyTrimmed,
                    "费用：\(entry.totalExpense)",
                    entry.estimatedReimbursement.map { "预计报销：\($0)" },
                    entry.actualReimbursement.map { "实际报销：\($0)" },
                    entry.status.nonEmptyTrimmed,
                    entry.reimbursementDeadline.map { "截止：\($0)" },
                    entry.materials.isEmpty ? nil : "材料：\(entry.materials.joined(separator: "、"))",
                    entry.note.nonEmptyTrimmed
                ]),
                sourceID: "medical.entry.\(index)",
                routeHint: CampusAIAcademicRouteID.medicalLedger.rawValue,
                updatedAt: entry.updatedAt,
                baseScore: 18
            ))
        }

        for (index, post) in context.communityCache.posts.enumerated() {
            candidates.append(candidate(
                domain: .community,
                title: "社区：\(post.title)",
                summary: join([
                    post.category,
                    post.body.nonEmptyTrimmed,
                    "评论 \(post.commentCount)",
                    "点赞 \(post.likeCount)",
                    post.imageCount > 0 ? "含 \(post.imageCount) 张图片" : nil
                ]),
                sourceID: "community.post.\(index)",
                updatedAt: post.updatedAt.nonEmptyTrimmed ?? post.createdAt,
                baseScore: 8
            ))
        }

        return candidates.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private static func candidate(
        domain: CampusAILocalKnowledgeDomain,
        title: String,
        summary: String,
        sourceID: String,
        routeHint: String? = nil,
        updatedAt: String? = nil,
        baseScore: Int
    ) -> Candidate {
        Candidate(
            domain: domain,
            title: title,
            summary: summary,
            sourceID: sourceID,
            routeHint: routeHint,
            updatedAt: updatedAt,
            baseScore: baseScore
        )
    }

    private static func fileCandidate(
        domain: CampusAILocalKnowledgeDomain,
        prefix: String,
        file: CampusAIFileMetadataContext,
        sourceID: String,
        routeHint: String? = nil,
        baseScore: Int
    ) -> Candidate {
        candidate(
            domain: domain,
            title: "\(prefix)：\(file.title)",
            summary: join([
                file.category.nonEmptyTrimmed,
                file.fileType.nonEmptyTrimmed,
                file.note.nonEmptyTrimmed
            ]),
            sourceID: sourceID,
            routeHint: routeHint,
            updatedAt: file.updatedAt,
            baseScore: baseScore
        )
    }

    private static func relevanceScore(candidate: Candidate, query: String) -> Int {
        let normalizedQuery = query.lowercased()
        let haystack = "\(candidate.title)\n\(candidate.summary)".lowercased()
        var score = candidate.baseScore

        if haystack.contains(normalizedQuery), normalizedQuery.count >= 2 {
            score += 36
        }

        for keyword in candidate.domain.intentKeywords where normalizedQuery.contains(keyword.lowercased()) {
            score += 18
        }

        for domain in CampusAILocalKnowledgeDomain.allCases where domain != candidate.domain {
            if domain.intentKeywords.contains(where: { normalizedQuery.contains($0.lowercased()) }) {
                score -= 4
            }
        }

        for token in queryTokens(query) where token.count >= 2 {
            if haystack.contains(token.lowercased()) {
                score += min(14, token.count + 4)
            }
        }

        return score
    }

    private static func fit(
        _ results: [CampusAILocalKnowledgeResult],
        maxResults: Int,
        characterBudget: Int
    ) -> [CampusAILocalKnowledgeResult] {
        var remaining = characterBudget
        var fitted: [CampusAILocalKnowledgeResult] = []
        for result in results.prefix(maxResults) {
            var next = result
            let fixedCost = next.title.count + next.domain.title.count + next.sourceID.count + 32
            let totalCost = fixedCost + next.summary.count
            if totalCost > remaining {
                let summaryLimit = remaining - fixedCost
                guard summaryLimit >= 80 else { break }
                next.summary = next.summary.clampedForAIContext(summaryLimit)
            }
            let cost = fixedCost + next.summary.count
            guard cost <= remaining else { break }
            fitted.append(next)
            remaining -= cost
        }
        return fitted
    }

    private static func queryTokens(_ value: String) -> [String] {
        let separated = value
            .lowercased()
            .replacingOccurrences(of: #"[\p{P}\p{S}\s]+"#, with: " ", options: .regularExpression)
        var tokens = separated.split(separator: " ").map(String.init)
        let important = CampusAILocalKnowledgeDomain.allCases.flatMap(\.intentKeywords)
        tokens.append(contentsOf: important.filter { value.contains($0) })
        return Array(Set(tokens))
    }

    private static func join(_ values: [String?], separator: String = "，") -> String {
        values.compactMap { $0?.nonEmptyTrimmed }.joined(separator: separator)
    }

    private static func weekdayText(_ day: Int) -> String {
        guard (1...7).contains(day) else { return "星期\(day)" }
        return ["周一", "周二", "周三", "周四", "周五", "周六", "周日"][day - 1]
    }

    private static func periodText(_ periods: [Int]) -> String {
        periods.isEmpty ? "未知" : periods.map(String.init).joined(separator: ",")
    }

    private static func stableID(domain: CampusAILocalKnowledgeDomain, sourceID: String) -> String {
        "\(domain.rawValue)-\(sourceID)"
            .replacingOccurrences(of: #"[^A-Za-z0-9._-]+"#, with: "-", options: .regularExpression)
    }
}

nonisolated struct CampusAICitation: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var url: String
    var siteName: String?
    var snippet: String?
    var summary: String?
    var publishedAt: String?
    var attachments: [CampusAIDeliverableAttachment]

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case url
        case siteName
        case siteNameSnake = "site_name"
        case snippet
        case summary
        case publishedAt
        case publishedAtSnake = "published_at"
        case attachments
    }

    init(
        id: String = UUID().uuidString,
        title: String,
        url: String,
        siteName: String? = nil,
        snippet: String? = nil,
        summary: String? = nil,
        publishedAt: String? = nil,
        attachments: [CampusAIDeliverableAttachment] = []
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.siteName = siteName
        self.snippet = snippet
        self.summary = summary
        self.publishedAt = publishedAt
        self.attachments = attachments
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        url = try container.decodeIfPresent(String.self, forKey: .url) ?? ""
        siteName = try container.decodeIfPresent(String.self, forKey: .siteName)
            ?? container.decodeIfPresent(String.self, forKey: .siteNameSnake)
        snippet = try container.decodeIfPresent(String.self, forKey: .snippet)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        publishedAt = try container.decodeIfPresent(String.self, forKey: .publishedAt)
            ?? container.decodeIfPresent(String.self, forKey: .publishedAtSnake)
        attachments = try container.decodeIfPresent([CampusAIDeliverableAttachment].self, forKey: .attachments) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(url, forKey: .url)
        try container.encodeIfPresent(siteName, forKey: .siteName)
        try container.encodeIfPresent(snippet, forKey: .snippet)
        try container.encodeIfPresent(summary, forKey: .summary)
        try container.encodeIfPresent(publishedAt, forKey: .publishedAt)
        try container.encode(attachments, forKey: .attachments)
    }
}

nonisolated enum CampusAIDeliverableFileFormat: String, Codable, CaseIterable, Hashable, Identifiable {
    case html
    case markdown
    case txt

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .html:
            return "HTML"
        case .markdown:
            return "Markdown"
        case .txt:
            return "TXT"
        }
    }

    var fileExtension: String {
        switch self {
        case .html:
            return "html"
        case .markdown:
            return "md"
        case .txt:
            return "txt"
        }
    }
}

nonisolated enum CampusAIArtifactFormatResolver {
    static func formats(for message: String) -> [CampusAIDeliverableFileFormat] {
        let text = message.lowercased()
        var formats: [CampusAIDeliverableFileFormat] = []
        if containsAny(text, ["html", "网页", "浏览器", "浏览", "网站"]) {
            formats.append(.html)
        }
        if containsAny(text, ["markdown", "md", "markdown 文件"]) {
            formats.append(.markdown)
        }
        if containsAny(text, ["txt", "文本", "纯文本"]) {
            formats.append(.txt)
        }
        return formats.isEmpty ? [.html] : CampusAIDeliverableFileFormat.allCases.filter { formats.contains($0) }
    }

    private static func containsAny(_ text: String, _ keywords: [String]) -> Bool {
        keywords.contains { text.contains($0) }
    }
}

nonisolated struct CampusAIArtifactContent: Codable, Hashable {
    var html: String?
    var markdown: String?
    var text: String?

    init(html: String? = nil, markdown: String? = nil, text: String? = nil) {
        self.html = html
        self.markdown = markdown
        self.text = text
    }

    func content(for format: CampusAIDeliverableFileFormat) -> String? {
        switch format {
        case .html:
            return html?.nonEmptyTrimmed
        case .markdown:
            return markdown?.nonEmptyTrimmed
        case .txt:
            return text?.nonEmptyTrimmed
        }
    }

    var availableFormats: [CampusAIDeliverableFileFormat] {
        CampusAIDeliverableFileFormat.allCases.filter { content(for: $0) != nil }
    }
}

nonisolated struct CampusAIDeliverableAttachment: Identifiable, Codable, Hashable {
    var title: String
    var url: String
    var fileType: String

    var id: String { url }

    enum CodingKeys: String, CodingKey {
        case title
        case url
        case fileType
        case fileTypeSnake = "file_type"
    }

    init(title: String, url: String, fileType: String) {
        self.title = title
        self.url = url
        self.fileType = fileType
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        url = try container.decodeIfPresent(String.self, forKey: .url) ?? ""
        fileType = try container.decodeIfPresent(String.self, forKey: .fileType)
            ?? container.decodeIfPresent(String.self, forKey: .fileTypeSnake)
            ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(url, forKey: .url)
        try container.encode(fileType, forKey: .fileType)
    }
}

nonisolated struct CampusAIDeliverableSource: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var url: String
    var siteName: String?
    var summary: String?
    var excerpt: String?
    var trustScore: Double
    var attachments: [CampusAIDeliverableAttachment]

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case url
        case siteName
        case siteNameSnake = "site_name"
        case summary
        case excerpt
        case trustScore
        case trustScoreSnake = "trust_score"
        case attachments
    }

    init(
        id: String = UUID().uuidString,
        title: String,
        url: String,
        siteName: String? = nil,
        summary: String? = nil,
        excerpt: String? = nil,
        trustScore: Double = 0,
        attachments: [CampusAIDeliverableAttachment] = []
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.siteName = siteName
        self.summary = summary
        self.excerpt = excerpt
        self.trustScore = trustScore
        self.attachments = attachments
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        url = try container.decodeIfPresent(String.self, forKey: .url) ?? ""
        siteName = try container.decodeIfPresent(String.self, forKey: .siteName)
            ?? container.decodeIfPresent(String.self, forKey: .siteNameSnake)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        excerpt = try container.decodeIfPresent(String.self, forKey: .excerpt)
        trustScore = try container.decodeIfPresent(Double.self, forKey: .trustScore)
            ?? container.decodeIfPresent(Double.self, forKey: .trustScoreSnake)
            ?? 0
        attachments = (try container.decodeIfPresent([CampusAIDeliverableAttachment].self, forKey: .attachments) ?? [])
            .filter { !$0.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(url, forKey: .url)
        try container.encodeIfPresent(siteName, forKey: .siteName)
        try container.encodeIfPresent(summary, forKey: .summary)
        try container.encodeIfPresent(excerpt, forKey: .excerpt)
        try container.encode(trustScore, forKey: .trustScore)
        try container.encode(attachments, forKey: .attachments)
    }
}

nonisolated struct CampusAIDeliverable: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var query: String
    var summary: String
    var generatedAt: String
    var sources: [CampusAIDeliverableSource]
    var formats: [CampusAIDeliverableFileFormat]
    var content: CampusAIArtifactContent?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case query
        case summary
        case generatedAt
        case generatedAtSnake = "generated_at"
        case sources
        case formats
        case content
    }

    init(
        id: String = UUID().uuidString,
        title: String,
        query: String,
        summary: String,
        generatedAt: String,
        sources: [CampusAIDeliverableSource],
        formats: [CampusAIDeliverableFileFormat] = CampusAIDeliverableFileFormat.allCases,
        content: CampusAIArtifactContent? = nil
    ) {
        self.id = id
        self.title = title
        self.query = query
        self.summary = summary
        self.generatedAt = generatedAt
        self.sources = sources
        self.formats = formats
        self.content = content
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        query = try container.decodeIfPresent(String.self, forKey: .query) ?? ""
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
        generatedAt = try container.decodeIfPresent(String.self, forKey: .generatedAt)
            ?? container.decodeIfPresent(String.self, forKey: .generatedAtSnake)
            ?? ""
        sources = (try container.decodeIfPresent([CampusAIDeliverableSource].self, forKey: .sources) ?? [])
            .filter { !$0.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        content = try container.decodeIfPresent(CampusAIArtifactContent.self, forKey: .content)
        let rawFormats = try container.decodeIfPresent([String].self, forKey: .formats) ?? []
        formats = rawFormats.compactMap { CampusAIDeliverableFileFormat(rawValue: $0.lowercased()) }
        if formats.isEmpty {
            formats = content?.availableFormats ?? CampusAIDeliverableFileFormat.allCases
        }
        if formats.isEmpty {
            formats = CampusAIDeliverableFileFormat.allCases
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(query, forKey: .query)
        try container.encode(summary, forKey: .summary)
        try container.encode(generatedAt, forKey: .generatedAt)
        try container.encode(sources, forKey: .sources)
        try container.encode(formats.map(\.rawValue), forKey: .formats)
        try container.encodeIfPresent(content, forKey: .content)
    }
}

nonisolated enum CampusAIDeliverableFileBuilder {
    static func cacheRoot(fileManager: FileManager = .default) throws -> URL {
        let caches = try fileManager.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return caches.appendingPathComponent("CampusAIArtifacts", isDirectory: true)
    }

    static func writeFile(
        for deliverable: CampusAIDeliverable,
        messageID: UUID,
        format: CampusAIDeliverableFileFormat,
        rootDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> URL {
        let root: URL
        if let rootDirectory {
            root = rootDirectory
        } else {
            root = try cacheRoot(fileManager: fileManager)
        }
        let directory = root.appendingPathComponent(messageID.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let fileName = sanitizedFileStem(deliverable.title.nonEmptyTrimmed ?? "CampusAIArtifacts")
            + "."
            + format.fileExtension
        let fileURL = directory.appendingPathComponent(fileName, isDirectory: false)
        try content(for: deliverable, format: format).write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    static func removeArtifacts(
        for messageID: UUID,
        rootDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) throws {
        let directory = try artifactsDirectory(
            for: messageID,
            rootDirectory: rootDirectory,
            fileManager: fileManager
        )
        guard fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.removeItem(at: directory)
    }

    static func removeAllArtifacts(
        rootDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) throws {
        let root: URL
        if let rootDirectory {
            root = rootDirectory
        } else {
            root = try cacheRoot(fileManager: fileManager)
        }
        guard fileManager.fileExists(atPath: root.path) else { return }
        try fileManager.removeItem(at: root)
    }

    static func pruneArtifacts(
        keeping messageIDs: Set<UUID>,
        rootDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) throws {
        let root: URL
        if let rootDirectory {
            root = rootDirectory
        } else {
            root = try cacheRoot(fileManager: fileManager)
        }
        guard fileManager.fileExists(atPath: root.path) else { return }
        let directories = try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        for directory in directories {
            let values = try directory.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true,
                  let id = UUID(uuidString: directory.lastPathComponent),
                  !messageIDs.contains(id)
            else { continue }
            try fileManager.removeItem(at: directory)
        }
    }

    static func content(for deliverable: CampusAIDeliverable, format: CampusAIDeliverableFileFormat) -> String {
        if let content = deliverable.content?.content(for: format) {
            return content
        }

        switch format {
        case .html:
            return htmlDocument(for: deliverable)
        case .markdown:
            return markdownDocument(for: deliverable)
        case .txt:
            return textDocument(for: deliverable)
        }
    }

    static func htmlDocument(for deliverable: CampusAIDeliverable) -> String {
        let sourceSections = deliverable.sources.enumerated().map { index, source in
            let attachments = source.attachments.isEmpty
                ? "<p class=\"muted\">未识别到附件链接。</p>"
                : """
                <ul class="attachments">
                \(source.attachments.map { attachment in
                    """
                    <li><a href="\(attributeEscape(attachment.url))">\(htmlEscape(attachment.title.nonEmptyTrimmed ?? attachment.url))</a><span>\(htmlEscape(attachment.fileType.uppercased()))</span></li>
                    """
                }.joined(separator: "\n"))
                </ul>
                """
            return """
            <section class="source">
              <h2>\(index + 1). <a href="\(attributeEscape(source.url))">\(htmlEscape(source.title.nonEmptyTrimmed ?? source.url))</a></h2>
              <p class="meta">\(htmlEscape([source.siteName?.nonEmptyTrimmed, scoreText(source.trustScore)].compactMap { $0 }.joined(separator: " · ")))</p>
              \(paragraphHTML(source.summary?.nonEmptyTrimmed ?? source.excerpt?.nonEmptyTrimmed))
              <h3>附件</h3>
              \(attachments)
            </section>
            """
        }.joined(separator: "\n")

        return """
        <!doctype html>
        <html lang="zh-CN">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>\(htmlEscape(deliverable.title.nonEmptyTrimmed ?? "学校官方资料包"))</title>
          <style>
            body { font: -apple-system-body; margin: 0; padding: 28px; color: #17201a; background: #fbfdfb; }
            main { max-width: 820px; margin: 0 auto; }
            header { border-bottom: 1px solid #dfe7df; padding-bottom: 18px; margin-bottom: 20px; }
            h1 { font-size: 28px; line-height: 1.2; margin: 0 0 12px; }
            h2 { font-size: 18px; line-height: 1.35; margin: 0 0 8px; }
            h3 { font-size: 14px; margin: 14px 0 8px; color: #4f6557; }
            p { line-height: 1.62; }
            a { color: #216e45; text-decoration-thickness: 0.08em; }
            .meta, .muted { color: #68766c; font-size: 13px; }
            .source { background: #ffffff; border: 1px solid #dfe7df; border-radius: 14px; padding: 16px; margin: 14px 0; }
            .attachments { padding-left: 20px; margin: 6px 0 0; }
            .attachments li { margin: 7px 0; }
            .attachments span { display: inline-block; margin-left: 8px; color: #68766c; font-size: 12px; }
          </style>
        </head>
        <body>
          <main>
            <header>
              <h1>\(htmlEscape(deliverable.title.nonEmptyTrimmed ?? "学校官方资料包"))</h1>
              <p class="meta">查询：\(htmlEscape(deliverable.query))</p>
              <p class="meta">生成时间：\(htmlEscape(deliverable.generatedAt))</p>
              \(paragraphHTML(deliverable.summary.nonEmptyTrimmed))
            </header>
            \(sourceSections.isEmpty ? "<p class=\"muted\">未找到可交付的官方来源。</p>" : sourceSections)
          </main>
        </body>
        </html>
        """
    }

    static func markdownDocument(for deliverable: CampusAIDeliverable) -> String {
        let sources = deliverable.sources.enumerated().map { index, source in
            let attachments = source.attachments.isEmpty
                ? "- 附件：未识别到附件链接"
                : source.attachments.map {
                    "- 附件：[\(markdownEscape($0.title.nonEmptyTrimmed ?? $0.url))](\($0.url))（\($0.fileType.uppercased())）"
                }.joined(separator: "\n")
            return """
            \(index + 1). [\(markdownEscape(source.title.nonEmptyTrimmed ?? source.url))](\(source.url))
               - 来源：\([source.siteName?.nonEmptyTrimmed, scoreText(source.trustScore)].compactMap { $0 }.joined(separator: " · "))
               - 摘要：\(markdownEscape(source.summary?.nonEmptyTrimmed ?? source.excerpt?.nonEmptyTrimmed ?? "暂无摘要"))
            \(attachments.split(separator: "\n").map { "   \($0)" }.joined(separator: "\n"))
            """
        }.joined(separator: "\n\n")

        return """
        # \(markdownEscape(deliverable.title.nonEmptyTrimmed ?? "学校官方资料包"))

        - 查询：\(markdownEscape(deliverable.query))
        - 生成时间：\(markdownEscape(deliverable.generatedAt))

        \(markdownEscape(deliverable.summary.nonEmptyTrimmed ?? "已整理官方来源和附件链接。"))

        ## 官方来源

        \(sources.isEmpty ? "未找到可交付的官方来源。" : sources)
        """
    }

    static func textDocument(for deliverable: CampusAIDeliverable) -> String {
        let sources = deliverable.sources.enumerated().map { index, source in
            let attachments = source.attachments.isEmpty
                ? "附件：未识别到附件链接"
                : source.attachments.map { "附件：\($0.title.nonEmptyTrimmed ?? $0.url) [\($0.fileType.uppercased())]\n\($0.url)" }.joined(separator: "\n")
            return """
            \(index + 1). \(source.title.nonEmptyTrimmed ?? source.url)
            \(source.url)
            \([source.siteName?.nonEmptyTrimmed, scoreText(source.trustScore)].compactMap { $0 }.joined(separator: " · "))
            \(source.summary?.nonEmptyTrimmed ?? source.excerpt?.nonEmptyTrimmed ?? "暂无摘要")
            \(attachments)
            """
        }.joined(separator: "\n\n")

        return """
        \(deliverable.title.nonEmptyTrimmed ?? "学校官方资料包")

        查询：\(deliverable.query)
        生成时间：\(deliverable.generatedAt)

        \(deliverable.summary.nonEmptyTrimmed ?? "已整理官方来源和附件链接。")

        官方来源
        \(sources.isEmpty ? "未找到可交付的官方来源。" : sources)
        """
    }

    private static func sanitizedFileStem(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
        let scalars = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let collapsed = String(scalars)
            .replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "- "))
        return String((collapsed.nonEmptyTrimmed ?? "CampusAIArtifacts").prefix(64))
    }

    private static func artifactsDirectory(
        for messageID: UUID,
        rootDirectory: URL?,
        fileManager: FileManager
    ) throws -> URL {
        let root: URL
        if let rootDirectory {
            root = rootDirectory
        } else {
            root = try cacheRoot(fileManager: fileManager)
        }
        return root.appendingPathComponent(messageID.uuidString, isDirectory: true)
    }

    private static func paragraphHTML(_ value: String?) -> String {
        guard let value else { return "" }
        return "<p>\(htmlEscape(value))</p>"
    }

    private static func scoreText(_ score: Double) -> String {
        "可信度 \(Int((max(0, min(score, 1)) * 100).rounded()))%"
    }

    private static func htmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func attributeEscape(_ value: String) -> String {
        htmlEscape(value)
    }

    private static func markdownEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
    }
}

nonisolated enum CampusAILocalArtifactBuilder {
    static func deliverables(for request: CampusAIRequest, answer: String) -> [CampusAIDeliverable] {
        guard request.capabilities.artifactGenerationEnabled,
              shouldGenerateArtifact(for: request.message),
              !request.localRetrieval.results.isEmpty
        else {
            return []
        }

        let sources = request.localRetrieval.results.prefix(12).map { result in
            CampusAIDeliverableSource(
                id: "local-\(result.id)",
                title: result.title.nonEmptyTrimmed ?? result.domain.title,
                url: "leafy://local/\(result.domain.rawValue)/\(result.sourceID)",
                siteName: "Leafy \(result.domain.title)",
                summary: result.summary.nonEmptyTrimmed,
                excerpt: nil,
                trustScore: 1,
                attachments: []
            )
        }
        guard !sources.isEmpty else { return [] }

        return [
            CampusAIDeliverable(
                id: "local-deliverable-\(request.requestID.uuidString)",
                title: artifactTitle(for: request.message),
                query: request.message,
                summary: artifactSummary(answer: answer),
                generatedAt: ISO8601DateFormatter().string(from: Date()),
                sources: sources,
                formats: CampusAIArtifactFormatResolver.formats(for: request.message)
            )
        ]
    }

    private static func shouldGenerateArtifact(for message: String) -> Bool {
        let text = message.lowercased()
        return [
            "资料包",
            "交付",
            "导出",
            "生成文件",
            "整理成文件",
            "html",
            "markdown",
            "txt",
            "md 文件",
            "文档"
        ].contains { text.contains($0) }
    }

    private static func artifactTitle(for message: String) -> String {
        let base = message
            .replacingOccurrences(of: #"[\r\n\t]+"#, with: " ", options: .regularExpression)
            .clampedForAIContext(32)
        return "\(base.nonEmptyTrimmed ?? "本地资料")资料包"
    }

    private static func artifactSummary(answer: String) -> String {
        answer.nonEmptyTrimmed?.clampedForAIContext(240) ?? "已根据相关资料整理为可打开的本地文件。"
    }
}

nonisolated struct CampusAIAgentTraceStep: Identifiable, Codable, Hashable {
    var id: String
    var kind: String
    var title: String
    var detail: String?
    var status: String
    var tool: String?
    var role: String?
    var timestamp: String?
}

nonisolated struct CampusAIAgentToolEvent: Codable, Hashable {
    var name: String
    var status: String
    var detail: String?
    var resultCount: Int?

    enum CodingKeys: String, CodingKey {
        case name
        case status
        case detail
        case resultCount
        case resultCountSnake = "result_count"
    }

    init(name: String, status: String, detail: String? = nil, resultCount: Int? = nil) {
        self.name = name
        self.status = status
        self.detail = detail
        self.resultCount = resultCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? ""
        detail = try container.decodeIfPresent(String.self, forKey: .detail)
        resultCount = try container.decodeIfPresent(Int.self, forKey: .resultCount)
            ?? container.decodeIfPresent(Int.self, forKey: .resultCountSnake)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(detail, forKey: .detail)
        try container.encodeIfPresent(resultCount, forKey: .resultCount)
    }
}

nonisolated struct CampusAISearchResultPreview: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var url: String
    var siteName: String?
}

nonisolated enum CampusAIAgentPresentation {
    static func toolStatusText(_ tool: CampusAIAgentToolEvent) -> String {
        let title = toolTitle(for: tool.name)

        switch tool.status {
        case "running":
            return "\(title)正在调用"
        case "completed":
            if let resultCount = tool.resultCount, resultCount > 0 {
                return "\(title)调用完成，找到 \(resultCount) 条结果"
            }
            return "\(title)调用完成"
        case "failed":
            return "\(title)调用失败，继续生成回答"
        case "skipped":
            return "\(title)已跳过"
        default:
            return title
        }
    }

    static func sanitizedStatusText(_ text: String) -> String {
        var result = text
        let replacements = [
            "official_search": "搜索工具",
            "web_search": "搜索工具",
            "read_web_page": "网页读取工具",
            "read_pdf": "PDF 读取工具"
        ]
        for (internalName, displayName) in replacements {
            result = result.replacingOccurrences(of: internalName, with: displayName)
        }
        result = result.replacingOccurrences(of: "搜索工具完成", with: "搜索工具调用完成")
        return result
    }

    private static func toolTitle(for name: String) -> String {
        switch name {
        case "official_search", "web_search", "official.document.search":
            return "搜索工具"
        case "read_web_page":
            return "网页读取工具"
        case "read_pdf":
            return "PDF 读取工具"
        case "completion.plan":
            return "整理工具"
        case "delegate.subtask":
            return "子任务"
        default:
            return "工具"
        }
    }
}

nonisolated struct CampusAIMessageAgentMetadata: Codable, Hashable {
    var statusText: String?
    var citations: [CampusAICitation]
    var searchResults: [CampusAISearchResultPreview]
    var agentTrace: [CampusAIAgentTraceStep]
    var deliverables: [CampusAIDeliverable]
    var artifactState: CampusAIArtifactGenerationState
    var artifactErrorMessage: String?

    static let empty = CampusAIMessageAgentMetadata()

    enum CodingKeys: String, CodingKey {
        case statusText
        case statusTextSnake = "status_text"
        case citations
        case searchResults
        case searchResultsSnake = "search_results"
        case agentTrace
        case agentTraceSnake = "agent_trace"
        case deliverables
        case artifactState
        case artifactStateSnake = "artifact_state"
        case artifactErrorMessage
        case artifactErrorMessageSnake = "artifact_error_message"
    }

    init(
        statusText: String? = nil,
        citations: [CampusAICitation] = [],
        searchResults: [CampusAISearchResultPreview] = [],
        agentTrace: [CampusAIAgentTraceStep] = [],
        deliverables: [CampusAIDeliverable] = [],
        artifactState: CampusAIArtifactGenerationState = .none,
        artifactErrorMessage: String? = nil
    ) {
        self.statusText = statusText
        self.citations = citations
        self.searchResults = searchResults
        self.agentTrace = agentTrace
        self.deliverables = deliverables
        self.artifactState = artifactState
        self.artifactErrorMessage = artifactErrorMessage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        statusText = try container.decodeIfPresent(String.self, forKey: .statusText)
            ?? container.decodeIfPresent(String.self, forKey: .statusTextSnake)
        citations = try container.decodeIfPresent([CampusAICitation].self, forKey: .citations) ?? []
        searchResults = try container.decodeIfPresent([CampusAISearchResultPreview].self, forKey: .searchResults)
            ?? container.decodeIfPresent([CampusAISearchResultPreview].self, forKey: .searchResultsSnake)
            ?? []
        agentTrace = try container.decodeIfPresent([CampusAIAgentTraceStep].self, forKey: .agentTrace)
            ?? container.decodeIfPresent([CampusAIAgentTraceStep].self, forKey: .agentTraceSnake)
            ?? []
        deliverables = try container.decodeIfPresent([CampusAIDeliverable].self, forKey: .deliverables) ?? []
        artifactState = try container.decodeIfPresent(CampusAIArtifactGenerationState.self, forKey: .artifactState)
            ?? container.decodeIfPresent(CampusAIArtifactGenerationState.self, forKey: .artifactStateSnake)
            ?? (deliverables.isEmpty ? .none : .ready)
        artifactErrorMessage = try container.decodeIfPresent(String.self, forKey: .artifactErrorMessage)
            ?? container.decodeIfPresent(String.self, forKey: .artifactErrorMessageSnake)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(statusText, forKey: .statusText)
        try container.encode(citations, forKey: .citations)
        try container.encode(searchResults, forKey: .searchResults)
        try container.encode(agentTrace, forKey: .agentTrace)
        try container.encode(deliverables, forKey: .deliverables)
        try container.encode(artifactState, forKey: .artifactState)
        try container.encodeIfPresent(artifactErrorMessage, forKey: .artifactErrorMessage)
    }
}

nonisolated struct CampusAIResponse: Codable, Hashable {
    var answer: String
    var reasoning: String
    var finishReason: String?
    var suggestedTitle: String?
    var summary: String?
    var actions: [CampusAIActionDraft]
    var citations: [CampusAICitation]
    var agentTrace: [CampusAIAgentTraceStep]
    var deliverables: [CampusAIDeliverable]
    var artifactState: CampusAIArtifactGenerationState
    var artifactErrorMessage: String?

    enum CodingKeys: String, CodingKey {
        case answer
        case reasoning
        case finishReason = "finish_reason"
        case suggestedTitle = "suggested_title"
        case summary
        case actions
        case citations
        case agentTrace
        case agentTraceSnake = "agent_trace"
        case deliverables
        case artifactState
        case artifactStateSnake = "artifact_state"
        case artifactErrorMessage
        case artifactErrorMessageSnake = "artifact_error_message"
    }

    init(
        answer: String,
        reasoning: String = "",
        finishReason: String? = nil,
        suggestedTitle: String? = nil,
        summary: String? = nil,
        actions: [CampusAIActionDraft] = [],
        citations: [CampusAICitation] = [],
        agentTrace: [CampusAIAgentTraceStep] = [],
        deliverables: [CampusAIDeliverable] = [],
        artifactState: CampusAIArtifactGenerationState = .none,
        artifactErrorMessage: String? = nil
    ) {
        self.answer = answer
        self.reasoning = reasoning
        self.finishReason = finishReason
        self.suggestedTitle = suggestedTitle
        self.summary = summary
        self.actions = CampusAIActionValidation.validated(actions)
        self.citations = citations.filter { !$0.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        self.agentTrace = agentTrace
        self.deliverables = deliverables
        self.artifactState = artifactState
        self.artifactErrorMessage = artifactErrorMessage
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
        citations = (try container.decodeIfPresent([CampusAICitation].self, forKey: .citations) ?? [])
            .filter { !$0.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        agentTrace = try container.decodeIfPresent([CampusAIAgentTraceStep].self, forKey: .agentTrace)
            ?? container.decodeIfPresent([CampusAIAgentTraceStep].self, forKey: .agentTraceSnake)
            ?? []
        deliverables = try container.decodeIfPresent([CampusAIDeliverable].self, forKey: .deliverables) ?? []
        artifactState = try container.decodeIfPresent(CampusAIArtifactGenerationState.self, forKey: .artifactState)
            ?? container.decodeIfPresent(CampusAIArtifactGenerationState.self, forKey: .artifactStateSnake)
            ?? (deliverables.isEmpty ? .none : .ready)
        artifactErrorMessage = try container.decodeIfPresent(String.self, forKey: .artifactErrorMessage)
            ?? container.decodeIfPresent(String.self, forKey: .artifactErrorMessageSnake)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(answer, forKey: .answer)
        try container.encode(reasoning, forKey: .reasoning)
        try container.encodeIfPresent(finishReason, forKey: .finishReason)
        try container.encodeIfPresent(suggestedTitle, forKey: .suggestedTitle)
        try container.encodeIfPresent(summary, forKey: .summary)
        try container.encode(actions, forKey: .actions)
        try container.encode(citations, forKey: .citations)
        try container.encode(agentTrace, forKey: .agentTrace)
        try container.encode(deliverables, forKey: .deliverables)
        try container.encode(artifactState, forKey: .artifactState)
        try container.encodeIfPresent(artifactErrorMessage, forKey: .artifactErrorMessage)
    }
}

nonisolated struct CampusAIQuotaSnapshot: Codable, Hashable {
    var planSource: String
    var limit: Int
    var used: Int
    var remaining: Int
    var resetAt: String
    var status: String
    var dailyLimit: Int
    var dailyUsed: Int
    var dailyRemaining: Int
    var dailyResetAt: String
    var periodLimit: Int?
    var periodUsed: Int?
    var periodRemaining: Int?
    var periodResetAt: String?

    enum CodingKeys: String, CodingKey {
        case planSource = "plan_source"
        case limit
        case used
        case remaining
        case resetAt = "reset_at"
        case status
        case dailyLimit = "daily_limit"
        case dailyUsed = "daily_used"
        case dailyRemaining = "daily_remaining"
        case dailyResetAt = "daily_reset_at"
        case periodLimit = "period_limit"
        case periodUsed = "period_used"
        case periodRemaining = "period_remaining"
        case periodResetAt = "period_reset_at"
    }

    init(
        planSource: String,
        limit: Int,
        used: Int,
        remaining: Int,
        resetAt: String,
        status: String,
        dailyLimit: Int? = nil,
        dailyUsed: Int? = nil,
        dailyRemaining: Int? = nil,
        dailyResetAt: String? = nil,
        periodLimit: Int? = nil,
        periodUsed: Int? = nil,
        periodRemaining: Int? = nil,
        periodResetAt: String? = nil
    ) {
        self.planSource = planSource
        self.limit = limit
        self.used = used
        self.remaining = remaining
        self.resetAt = resetAt
        self.status = status
        self.dailyLimit = dailyLimit ?? limit
        self.dailyUsed = dailyUsed ?? used
        self.dailyRemaining = dailyRemaining ?? remaining
        self.dailyResetAt = dailyResetAt ?? resetAt
        self.periodLimit = periodLimit
        self.periodUsed = periodUsed
        self.periodRemaining = periodRemaining
        self.periodResetAt = periodResetAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        planSource = try container.decodeIfPresent(String.self, forKey: .planSource) ?? "free"
        limit = try container.decodeIfPresent(Int.self, forKey: .limit) ?? 10
        used = try container.decodeIfPresent(Int.self, forKey: .used) ?? 0
        remaining = try container.decodeIfPresent(Int.self, forKey: .remaining) ?? max(limit - used, 0)
        resetAt = try container.decodeIfPresent(String.self, forKey: .resetAt) ?? ""
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? planSource
        dailyLimit = try container.decodeIfPresent(Int.self, forKey: .dailyLimit) ?? limit
        dailyUsed = try container.decodeIfPresent(Int.self, forKey: .dailyUsed) ?? used
        dailyRemaining = try container.decodeIfPresent(Int.self, forKey: .dailyRemaining) ?? remaining
        dailyResetAt = try container.decodeIfPresent(String.self, forKey: .dailyResetAt) ?? resetAt
        periodLimit = try container.decodeIfPresent(Int.self, forKey: .periodLimit)
        periodUsed = try container.decodeIfPresent(Int.self, forKey: .periodUsed)
        periodRemaining = try container.decodeIfPresent(Int.self, forKey: .periodRemaining)
        periodResetAt = try container.decodeIfPresent(String.self, forKey: .periodResetAt)
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
            countdowns: CustomScheduleStore.load(),
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
        countdowns: [CustomScheduleEvent],
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
                .filter { $0.startsAt >= todayStart }
                .sorted { $0.startsAt < $1.startsAt }
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
        countdowns: [CustomScheduleEvent],
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
    init(countdown: CustomScheduleEvent) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        self.init(title: countdown.title, targetDate: formatter.string(from: countdown.startsAt))
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
            return "Leafy AI 服务暂时不可用，请稍后再试。"
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
    case agentStatus(String)
    case agentStep(CampusAIAgentTraceStep)
    case agentTool(CampusAIAgentToolEvent)
    case agentSearchResults([CampusAISearchResultPreview])
    case agentCitation(CampusAICitation)
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
        case "agent_status":
            let text = payload.text ?? ""
            return text.isEmpty ? [] : [.agentStatus(text)]
        case "agent_step":
            guard let step = payload.step else { return [] }
            return [.agentStep(step)]
        case "agent_tool":
            guard let tool = payload.tool else { return [] }
            return [.agentTool(tool)]
        case "agent_citation":
            guard let citation = payload.citation else { return [] }
            return [.agentCitation(citation)]
        case "agent_search_results":
            guard let results = payload.results, !results.isEmpty else { return [] }
            return [.agentSearchResults(results)]
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
                        summary: payload.summary,
                        actions: payload.actions ?? [],
                        citations: payload.citations ?? [],
                        agentTrace: payload.agentTrace ?? payload.agentTraceSnake ?? [],
                        deliverables: payload.deliverables ?? []
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
    let actions: [CampusAIActionDraft]?
    let citations: [CampusAICitation]?
    let agentTrace: [CampusAIAgentTraceStep]?
    let agentTraceSnake: [CampusAIAgentTraceStep]?
    let deliverables: [CampusAIDeliverable]?
    let step: CampusAIAgentTraceStep?
    let tool: CampusAIAgentToolEvent?
    let citation: CampusAICitation?
    let results: [CampusAISearchResultPreview]?
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
        case actions
        case citations
        case agentTrace
        case agentTraceSnake = "agent_trace"
        case deliverables
        case step
        case tool
        case citation
        case results
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
    let maxTokens: Int?
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

nonisolated struct CampusAIActionPlannerPayload: Encodable, Hashable {
    let model: String
    let messages: [Message]
    let stream: Bool
    let temperature: Double
    let maxTokens: Int
    let user: String?

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case stream
        case temperature
        case maxTokens = "max_tokens"
        case user
    }

    struct Message: Encodable, Hashable {
        let role: String
        let content: String
    }
}

nonisolated private struct CampusAIActionPlannerProviderResponse: Decodable {
    let choices: [Choice]?

    struct Choice: Decodable {
        let message: Message?
    }

    struct Message: Decodable {
        let content: String?
    }
}

nonisolated private struct CampusAIActionPlannerResult: Decodable {
    let actions: [CampusAIActionDraft]
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
        settings: CampusAIUserSettings = .defaultValue,
        outputMode: CampusAIOutputMode = .automatic
    ) async throws -> CampusAIResponse {
        var accumulatedAnswer = ""
        var accumulatedReasoning = ""
        var finalResponse: CampusAIResponse?
        for try await event in stream(
            message: message,
            context: context,
            recentMessages: recentMessages,
            settings: settings,
            outputMode: outputMode
        ) {
            switch event {
            case .delta(let text):
                accumulatedAnswer += text
            case .reasoningDelta(let text):
                accumulatedReasoning += text
            case .quota:
                break
            case .agentStatus, .agentStep, .agentTool, .agentSearchResults, .agentCitation:
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
        return response
    }

    func stream(
        message: String,
        context: CampusAIContextPayload,
        recentMessages: [CampusAIChatMessage],
        settings: CampusAIUserSettings = .defaultValue,
        outputMode: CampusAIOutputMode = .automatic
    ) -> AsyncThrowingStream<CampusAIStreamEvent, Error> {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: CampusAIServiceError.emptyMessage)
            }
        }
        let normalizedSettings = settings.normalizedForLocalRuntime
        let capabilities = CampusAICapabilitySet(settings: normalizedSettings)
        let localRetrieval = capabilities.localSearchEnabled
            ? CampusAILocalKnowledgeIndex.search(query: trimmed, context: context)
            : .empty(query: trimmed)
        let request = CampusAIRequest(
            message: trimmed,
            context: context,
            recentMessages: recentMessages,
            model: normalizedSettings.serviceMode == .leafyManaged
                ? CampusAIModelCatalog.flash.modelIdentifier
                : normalizedSettings.selectedModel.modelIdentifier,
            userSystemPrompt: normalizedSettings.effectiveSystemPrompt,
            contextSettings: normalizedSettings.contextSettings,
            agentMode: .auto,
            webSearchEnabled: capabilities.webSearchEnabled,
            capabilities: capabilities,
            localRetrieval: localRetrieval,
            outputMode: outputMode
        )
        return streamInvoke(request, normalizedSettings)
    }

    private static func invokeStream(
        _ request: CampusAIRequest,
        settings: CampusAIUserSettings
    ) -> AsyncThrowingStream<CampusAIStreamEvent, Error> {
        let normalizedSettings = settings.normalizedForLocalRuntime
        if normalizedSettings.serviceMode == .leafyManaged {
            return invokeManagedStream(request, settings: normalizedSettings)
        }
        if CampusAIResearchIntent.shouldRun(request) {
            return CampusAIResearchAgent.invokeStream(request, settings: normalizedSettings)
        }
        return invokeDirectStream(request, settings: normalizedSettings)
    }

    static func invokeDirectStream(
        _ request: CampusAIRequest,
        settings: CampusAIUserSettings
    ) -> AsyncThrowingStream<CampusAIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let shouldCreateArtifact = CampusAIArtifactIntentResolver.shouldGenerateArtifact(
                        message: request.message,
                        mode: request.outputMode
                    )
                    let usesDirectAgent = shouldRunDirectAgent(request) || shouldCreateArtifact
                    var directAgentTrace: [CampusAIAgentTraceStep] = []
                    if usesDirectAgent {
                        let planningStep = directAgentStep(
                            id: "direct-agent-planner",
                            title: "任务拆解",
                            detail: "使用自备 API Key 进行非联网 agent 规划。",
                            status: "completed"
                        )
                        directAgentTrace.append(planningStep)
                        continuation.yield(.agentStatus("正在拆解任务"))
                        continuation.yield(.agentStep(planningStep))
                    }

                    let apiKey = try CampusAIAPIKeyResolver().resolve(for: settings)
                    let urlRequest = try makeChatCompletionsRequest(
                        for: request,
                        baseURLString: settings.selectedProvider.baseURLString,
                        apiKey: apiKey
                    )
                    let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
                    var finalResponse: CampusAIResponse?
                    let yieldProviderEvents: ([CampusAIStreamEvent]) -> Void = { events in
                        for event in events {
                            if case .done(let response) = event {
                                finalResponse = response
                            } else {
                                continuation.yield(event)
                            }
                        }
                    }
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
                                yieldProviderEvents(try parser.append(chunk))
                                chunk.removeAll(keepingCapacity: true)
                            }
                        }

                        if !chunk.isEmpty {
                            yieldProviderEvents(try parser.append(chunk))
                        }

                        yieldProviderEvents(try parser.finish())
                    } else {
                        let body = try await providerBody(from: bytes)
                        yieldProviderEvents(try providerEvents(from: body))
                    }
                    if var finalResponse {
                        if usesDirectAgent {
                            let synthesisStep = directAgentStep(
                                id: "direct-agent-synthesis",
                                title: "整合回答",
                                detail: "结合本机上下文生成回答。",
                                status: "completed"
                            )
                            directAgentTrace.append(synthesisStep)
                            continuation.yield(.agentStep(synthesisStep))
                            continuation.yield(.agentStatus(shouldCreateArtifact ? "正在整理成品" : "正在整理回答"))
                            if shouldCreateArtifact {
                                continuation.yield(.agentTool(.init(name: "completion.plan", status: "running")))
                            }
                        }
                        if shouldCreateArtifact {
                            finalResponse.artifactState = .generating
                            CampusAIDiagnostics.artifact(.generating, requestID: request.requestID)
                        }
                        do {
                            let completionPlan = try await directCompletionPlan(
                                request: request,
                                answer: finalResponse.answer,
                                settings: settings,
                                apiKey: apiKey
                            )
                            finalResponse.actions = completionPlan.actions
                            if shouldCreateArtifact {
                                guard let artifact = completionPlan.artifact,
                                      let deliverable = CampusAIArtifactAssembler.deliverable(
                                        from: artifact,
                                        request: request
                                      )
                                else {
                                    throw CampusAICompletionPlanError.artifactMissing
                                }
                                finalResponse.deliverables = [deliverable]
                                finalResponse.artifactState = .ready
                                finalResponse.artifactErrorMessage = nil
                                CampusAIDiagnostics.artifact(.ready, requestID: request.requestID)
                            }
                        } catch {
                            CampusAIDiagnostics.failure(error, stage: "completion.plan", requestID: request.requestID)
                            finalResponse.actions = []
                            if shouldCreateArtifact {
                                finalResponse.artifactState = .failed
                                finalResponse.artifactErrorMessage = error.localizedDescription
                                CampusAIDiagnostics.artifact(.failed, requestID: request.requestID)
                            }
                        }
                        if usesDirectAgent {
                            let shouldPublishActionEvents = CampusAICompletionPlanEventPolicy
                                .shouldPublishActionEvents(actionCount: finalResponse.actions.count)
                            if shouldPublishActionEvents {
                                let actionStep = directAgentStep(
                                    id: "direct-agent-action-plan",
                                    title: "动作规划",
                                    detail: "已生成 \(finalResponse.actions.count) 个待确认动作。",
                                    status: "completed",
                                    tool: "completion.plan"
                                )
                                directAgentTrace.append(actionStep)
                                continuation.yield(.agentStep(actionStep))
                            }
                            if shouldCreateArtifact || shouldPublishActionEvents {
                                continuation.yield(.agentTool(.init(
                                    name: "completion.plan",
                                    status: "completed",
                                    resultCount: finalResponse.actions.count + finalResponse.deliverables.count
                                )))
                            }
                            finalResponse.agentTrace = mergeAgentTrace(
                                finalResponse.agentTrace,
                                directAgentTrace
                            )
                        }
                        continuation.yield(.done(finalResponse))
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
                        let message = managedHTTPErrorMessage(statusCode: httpResponse.statusCode, body: body)
                        if httpResponse.statusCode == 402 {
                            throw CampusAIServiceError.quotaExhausted(message)
                        }
                        throw CampusAIServiceError.providerRejected(message)
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

    static func shouldRunDirectAgent(_ request: CampusAIRequest) -> Bool {
        guard request.agentMode == .auto else { return false }
        let text = request.message.lowercased()
        return [
            "拆解",
            "规划",
            "计划",
            "比较",
            "分析",
            "结合",
            "安排",
            "方案",
            "多步",
            "提醒",
            "重要日期",
            "打开"
        ].contains { text.contains($0) }
    }

    private static func directAgentStep(
        id: String,
        title: String,
        detail: String,
        status: String,
        tool: String? = nil,
        role: String? = nil
    ) -> CampusAIAgentTraceStep {
        CampusAIAgentTraceStep(
            id: id,
            kind: tool == nil ? "agent" : "tool",
            title: title,
            detail: detail,
            status: status,
            tool: tool,
            role: role,
            timestamp: ISO8601DateFormatter().string(from: Date())
        )
    }

    private static func mergeAgentTrace(
        _ existing: [CampusAIAgentTraceStep],
        _ additional: [CampusAIAgentTraceStep]
    ) -> [CampusAIAgentTraceStep] {
        var seen = Set(existing.map(\.id))
        var merged = existing
        for step in additional where !seen.contains(step.id) {
            seen.insert(step.id)
            merged.append(step)
        }
        return merged
    }

    static func makeActionPlannerRequest(
        for request: CampusAIRequest,
        answer: String,
        baseURLString: String,
        apiKey: String
    ) throws -> URLRequest {
        let url = try chatCompletionsURL(baseURLString: baseURLString)
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try providerJSONEncoder().encode(actionPlannerPayload(for: request, answer: answer))
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
            capabilities: request.capabilities,
            localRetrieval: request.localRetrieval,
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
                .init(
                    role: "system",
                    content: systemPrompt(
                        userPrompt: request.userSystemPrompt,
                        preparesArtifact: CampusAIArtifactIntentResolver.shouldGenerateArtifact(
                            message: request.message,
                            mode: request.outputMode
                        )
                    )
                ),
                .init(role: "user", content: userContentString)
            ],
            stream: true,
            thinking: .enabled,
            streamOptions: .includeUsage,
            temperature: 0.2,
            maxTokens: nil,
            user: nil
        )
    }

    static func actionPlannerPayload(
        for request: CampusAIRequest,
        answer: String
    ) throws -> CampusAIActionPlannerPayload {
        let userContent = CampusAIActionPlannerUserContent(
            message: request.message,
            answer: answer,
            context: request.context,
            contextSettings: request.contextSettings,
            capabilities: request.capabilities,
            localRetrieval: request.localRetrieval,
            shouldGenerateArtifact: CampusAIArtifactIntentResolver.shouldGenerateArtifact(
                message: request.message,
                mode: request.outputMode
            )
        )
        guard let userContentString = String(data: try providerJSONEncoder().encode(userContent), encoding: .utf8) else {
            throw CampusAIServiceError.invalidProviderResponse
        }

        return CampusAIActionPlannerPayload(
            model: request.model,
            messages: [
                .init(role: "system", content: actionPlannerSystemPrompt()),
                .init(role: "user", content: userContentString)
            ],
            stream: false,
            temperature: 0,
            maxTokens: CampusAIArtifactIntentResolver.shouldGenerateArtifact(
                message: request.message,
                mode: request.outputMode
            ) ? 4_000 : 700,
            user: nil
        )
    }

    static func systemPrompt(userPrompt: String, preparesArtifact: Bool = false) -> String {
        let customPrompt = userPrompt.nonEmptyTrimmed.map { String($0.prefix(3000)) }
        return [
            "你是 Leafy 的通用 AI 助手，当前是测试功能。",
            "回答要直接、具体、可执行；能给结论就先给结论，不要反复解释内部数据来源。",
            "可以回答通用问题；当用户问题与已提供的课程、考试、学习、提醒或个人事项相关时，再结合这些本机上下文给出更具体的建议。不要为了使用本机数据而牵强关联，也不要把不确定内容说成事实。",
            "如果输入包含 local_retrieval，优先使用其中最相关的结果；不要把它作为工程细节反复解释给用户。",
            "缺少关键信息时，用一句话说明缺什么，并给出用户下一步能做的选择。",
            "不要声称读取了未提供的数据，不要声称读取了用户上传文件正文、图片像素、OCR、PDF、Word、PPT、表格或本地文件路径。",
            "不要推断私信、身份资料、未提供的远端内容或后台登录后的内容。",
            "医疗台账只能做整理、提醒、流程梳理和材料核对，不提供诊断、治疗、用药或医疗决策建议。",
            "回复必须是中文 Markdown，并保持适合手机阅读的块级结构。先给结论；不同主题必须换段或使用短标题；三项以上并列信息必须使用列表；不要用 emoji、连续加粗或挤在同一段中的序号模拟结构。不要输出 JSON，不要输出动作草稿。",
            preparesArtifact
                ? "本次会另行生成完整成品。主回答只用一到三句话说明已理解需求、将交付什么，不要重复完整计划、报告、清单或表格。"
                : nil,
            customPrompt.map { "用户自定义偏好：\n\($0)" }
        ].compactMap { $0 }.joined(separator: "\n")
    }

    static func actionPlannerSystemPrompt() -> String {
        [
            "你是 MyLeafy 的交付规划器，只能输出 JSON，不能输出代码块、解释或多余文本。",
            "根据用户问题、AI 已生成回答和本机上下文，一次返回最多 3 个待确认动作，以及可选的 Artifact 成品。",
            "输出根对象必须是 {\"actions\":[],\"artifact\":null}。当 should_generate_artifact 为 true 时，artifact 必须是 {\"title\":\"...\",\"summary\":\"...\",\"markdown\":\"...\"}；否则 artifact 必须为 null。",
            "Artifact 必须是完整、可直接阅读的中文 Markdown 成品。可使用标题、列表、表格、引用、Mermaid 或 KaTeX；不要在 Artifact 中编造来源。",
            "Artifact 的 title、summary 和正文由你生成；来源、数据范围和本机条目引用由 App 在本地附加，不要输出 sources 字段。",
            "可以使用 local_retrieval 中的 routeHint 和 sourceID 判断动作目标；缺少明确目标 ID 时不要编造编辑或删除动作。",
            "只有用户明确想打开页面、设置重要日期、设置课表提醒，或回答中明显需要这一步时才生成动作；否则返回 {\"actions\":[]}。",
            "支持 kind：openAcademicRoute、createCountdown、createTimetableReminder。",
            "openAcademicRoute.payload.route 必须来自 supported_actions 中的 allowed_values.route。",
            "用户明确想查看、添加或管理考试、考场、考试时间、考试安排时，生成 openAcademicRoute 到 examSchedule。",
            "用户想新建、添加或管理日程/提醒，但缺少创建课表提醒所需的周次、星期、节次时，生成 openAcademicRoute：普通日程、事项、待办、提醒、重要日期或自定日程管理用 customCountdowns，推送或报告用 scheduleReports。",
            "createCountdown 兼容旧字段名，语义是创建重要日期；payload 必须包含 countdownTitle 和 targetDate，targetDate 使用 yyyy-MM-dd。",
            "createTimetableReminder.payload 必须包含 week、dayOfWeek、period、title；dayOfWeek 为 1 到 7，minutesBefore 必须大于等于 0。",
            "不要生成删除、修改成绩或课表原始数据、医疗决策、社区发帖评论、远程抓取、后台登录等动作。",
            "输出格式必须是 {\"actions\":[{\"kind\":\"...\",\"title\":\"...\",\"detail\":\"...\",\"payload\":{...}}],\"artifact\":null}，或将 artifact 替换为完整对象。"
        ].joined(separator: "\n")
    }

    private static func directCompletionPlan(
        request: CampusAIRequest,
        answer: String,
        settings: CampusAIUserSettings,
        apiKey: String
    ) async throws -> CampusAICompletionPlan {
        let urlRequest = try makeActionPlannerRequest(
            for: request,
            answer: answer,
            baseURLString: settings.selectedProvider.baseURLString,
            apiKey: apiKey
        )
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CampusAIServiceError.invalidProviderResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw CampusAIServiceError.providerRejected("成品整理服务返回了 \(httpResponse.statusCode) 错误。")
        }
        let providerResponse = try providerJSONDecoder().decode(CampusAIActionPlannerProviderResponse.self, from: data)
        guard let content = providerResponse.choices?
            .compactMap({ $0.message?.content?.nonEmptyTrimmed })
            .first
        else {
            throw CampusAIServiceError.invalidProviderResponse
        }
        return try CampusAICompletionPlanParser.parse(content)
    }

    static func fallbackActionDrafts(
        for request: CampusAIRequest,
        answer: String = ""
    ) -> [CampusAIActionDraft] {
        let text = [request.message, answer]
            .joined(separator: "\n")
            .lowercased()
        let hasCreateIntent = ["新建", "添加", "创建", "设置", "安排"].contains { text.contains($0) }
        let hasOpenIntent = ["查看", "打开", "查询", "管理"].contains { text.contains($0) }
        let hasScheduleIntent = ["日程", "提醒", "事项", "待办", "安排"].contains { text.contains($0) }
        let hasExamIntent = text.contains("考试") || text.contains("考场")
        guard (hasCreateIntent || hasOpenIntent) && (hasScheduleIntent || hasExamIntent) else { return [] }

        let route: CampusAIAcademicRouteID
        if text.contains("推送") || text.contains("报告") {
            route = .scheduleReports
        } else if text.contains("考试") || text.contains("考场") {
            route = .examSchedule
        } else {
            route = .customCountdowns
        }
        return [
            CampusAIActionDraft(
                kind: .openAcademicRoute,
                title: "打开\(route.title)",
                detail: actionDetail(for: route),
                payload: CampusAIActionPayload(route: route.rawValue)
            )
        ]
    }

    private static func actionDetail(for route: CampusAIAcademicRouteID) -> String {
        switch route {
        case .examSchedule:
            return "前往考试安排继续查看或管理考试。"
        case .scheduleReports:
            return "前往日程推送继续设置报告。"
        case .customCountdowns:
            return "前往自定日程继续创建或管理日程。"
        default:
            return "前往\(route.title)继续处理。"
        }
    }

    static func actionPlannerActions(fromProviderResponseData data: Data) throws -> [CampusAIActionDraft] {
        let response = try providerJSONDecoder().decode(CampusAIActionPlannerProviderResponse.self, from: data)
        guard let content = response.choices?.compactMap({ $0.message?.content }).first(where: { !$0.isEmpty }) else {
            return []
        }
        return actionPlannerActions(fromContent: content)
    }

    static func actionPlannerActions(fromContent content: String) -> [CampusAIActionDraft] {
        let candidates = actionPlannerJSONCandidates(from: content)
        let decoder = providerJSONDecoder()
        for candidate in candidates {
            let data = Data(candidate.utf8)
            if let result = try? decoder.decode(CampusAIActionPlannerResult.self, from: data) {
                return Array(CampusAIActionValidation.validated(result.actions).prefix(3))
            }
            if let actions = try? decoder.decode([CampusAIActionDraft].self, from: data) {
                return Array(CampusAIActionValidation.validated(actions).prefix(3))
            }
        }
        return []
    }

    private static func actionPlannerJSONCandidates(from content: String) -> [String] {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let unfenced: String
        if trimmed.hasPrefix("```") {
            let lines = trimmed
                .replacingOccurrences(of: "\r\n", with: "\n")
                .split(separator: "\n", omittingEmptySubsequences: false)
            unfenced = lines
                .dropFirst()
                .dropLast(lines.last?.trimmingCharacters(in: .whitespacesAndNewlines) == "```" ? 1 : 0)
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            unfenced = trimmed
        }

        var candidates = [unfenced]
        if let start = unfenced.firstIndex(of: "{"), let end = unfenced.lastIndex(of: "}"), start <= end {
            candidates.append(String(unfenced[start...end]))
        }
        if let start = unfenced.firstIndex(of: "["), let end = unfenced.lastIndex(of: "]"), start <= end {
            candidates.append(String(unfenced[start...end]))
        }
        var seen = Set<String>()
        return candidates.filter { candidate in
            guard !candidate.isEmpty, !seen.contains(candidate) else { return false }
            seen.insert(candidate)
            return true
        }
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

    private static func providerJSONDecoder() -> JSONDecoder {
        JSONDecoder()
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
            return statusCode == 402 ? error : "Leafy AI 服务返回了 \(statusCode) 错误：\(error)"
        }
        if trimmedBody.isEmpty {
            return "Leafy AI 服务返回了 \(statusCode) 错误。"
        }
        return "Leafy AI 服务返回了 \(statusCode) 错误：\(trimmedBody)"
    }
}

nonisolated private struct CampusAIProviderUserContent: Encodable {
    let message: String
    let context: CampusAIContextPayload
    let contextSettings: CampusAIContextSettings
    let capabilities: CampusAICapabilitySet
    let localRetrieval: CampusAILocalRetrievalPayload
    let recentMessages: [RecentMessage]

    enum CodingKeys: String, CodingKey {
        case message
        case context
        case contextSettings = "context_settings"
        case capabilities
        case localRetrieval = "local_retrieval"
        case recentMessages = "recent_messages"
    }

    struct RecentMessage: Encodable, Hashable {
        let role: String
        let text: String
    }
}

nonisolated private struct CampusAIActionPlannerUserContent: Encodable {
    let message: String
    let answer: String
    let context: CampusAIContextPayload
    let contextSettings: CampusAIContextSettings
    let capabilities: CampusAICapabilitySet
    let localRetrieval: CampusAILocalRetrievalPayload
    let shouldGenerateArtifact: Bool
    let supportedActions: [CampusAIToolSupportedAction]
    let safetyBoundary: [String]

    enum CodingKeys: String, CodingKey {
        case message
        case answer
        case context
        case contextSettings = "context_settings"
        case capabilities
        case localRetrieval = "local_retrieval"
        case shouldGenerateArtifact = "should_generate_artifact"
        case supportedActions = "supported_actions"
        case safetyBoundary = "safety_boundary"
    }

    init(
        message: String,
        answer: String,
        context: CampusAIContextPayload,
        contextSettings: CampusAIContextSettings,
        capabilities: CampusAICapabilitySet,
        localRetrieval: CampusAILocalRetrievalPayload,
        shouldGenerateArtifact: Bool
    ) {
        self.message = message
        self.answer = answer
        self.context = context
        self.contextSettings = contextSettings
        self.capabilities = capabilities
        self.localRetrieval = localRetrieval
        self.shouldGenerateArtifact = shouldGenerateArtifact
        supportedActions = CampusAIToolRegistry.supportedActions()
        safetyBoundary = [
            "所有动作都只生成待确认草稿，不会自动执行。",
            "不要生成修改成绩或课表原始数据、医疗决策、社区发帖评论、远程抓取、后台登录等动作。",
            "编辑或删除必须有 local_retrieval.sourceID 等明确目标 ID；缺少目标 ID 时改生成 openAcademicRoute 或返回空 actions。",
            "删除类动作需要二次确认；当前 schema 未提供删除 kind 时不要输出删除动作。",
            "缺少必要 payload 字段或字段无法从上下文确定时，返回空 actions。"
        ]
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
    let agentMode: CampusAIAgentMode
    let webSearchEnabled: Bool
    let capabilities: CampusAICapabilitySet
    let localRetrieval: CampusAILocalRetrievalPayload

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
        case agentMode = "agent_mode"
        case webSearchEnabled = "web_search_enabled"
        case capabilities
        case localRetrieval = "local_retrieval"
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
        self.agentMode = request.agentMode
        self.webSearchEnabled = request.webSearchEnabled
        self.capabilities = request.capabilities
        self.localRetrieval = request.localRetrieval
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
