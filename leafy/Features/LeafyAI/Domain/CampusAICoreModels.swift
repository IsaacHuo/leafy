nonisolated enum CampusAIMessageRole: String, Codable, Hashable {
    case user
    case assistant
}

nonisolated private extension String {
    var nonEmptyTrimmed: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

nonisolated enum CampusAIActionStatus: String, Codable, Hashable {
    case pending
    case completed
    case cancelled
    case failed
}

nonisolated enum CampusAIActionKind: String, Codable, Hashable {
    case openAcademicRoute
    case createSchedule
    case createCountdown
    case createTimetableReminder

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        switch rawValue {
        case Self.openAcademicRoute.rawValue, "open_academic_route":
            self = .openAcademicRoute
        case Self.createSchedule.rawValue, "create_schedule":
            self = .createSchedule
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
    var startsAt: String?
    var endsAt: String?
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
        startsAt: String? = nil,
        endsAt: String? = nil,
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
        self.startsAt = startsAt
        self.endsAt = endsAt
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
        case startsAt
        case startsAtSnake = "starts_at"
        case endsAt
        case endsAtSnake = "ends_at"
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
        startsAt = try container.decodeIfPresent(String.self, forKey: .startsAt)
            ?? container.decodeIfPresent(String.self, forKey: .startsAtSnake)
        endsAt = try container.decodeIfPresent(String.self, forKey: .endsAt)
            ?? container.decodeIfPresent(String.self, forKey: .endsAtSnake)
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
        try container.encodeIfPresent(startsAt, forKey: .startsAt)
        try container.encodeIfPresent(endsAt, forKey: .endsAt)
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
        case .createSchedule:
            return validateSchedule(draft)
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

    static func scheduleStartDate(for draft: CampusAIActionDraft) -> Date? {
        parseDateTime(draft.payload.startsAt)
    }

    static func scheduleEndDate(for draft: CampusAIActionDraft) -> Date? {
        parseDateTime(draft.payload.endsAt)
    }

    private static func validateOpenRoute(_ draft: CampusAIActionDraft) -> CampusAIActionDraft? {
        guard let routeID = routeID(for: draft) else { return nil }
        var normalized = draft
        normalized.title = normalized.title.nonEmptyTrimmed ?? "打开\(routeID.title)"
        normalized.payload.route = routeID.rawValue
        return normalized
    }

    private static func validateSchedule(_ draft: CampusAIActionDraft) -> CampusAIActionDraft? {
        var normalized = draft
        normalized.title = normalized.title.nonEmptyTrimmed ?? "添加日程"
        normalized.payload.title = normalized.payload.title?.nonEmptyTrimmed
        normalized.payload.location = normalized.payload.location?.nonEmptyTrimmed
        normalized.payload.note = normalized.payload.note?.nonEmptyTrimmed
        normalized.payload.minutesBefore = max(0, normalized.payload.minutesBefore ?? 0)
        if normalized.payload.startsAt != nil, scheduleStartDate(for: normalized) == nil {
            normalized.payload.startsAt = nil
        }
        if let end = scheduleEndDate(for: normalized),
           let start = scheduleStartDate(for: normalized),
           end <= start {
            normalized.payload.endsAt = nil
        }
        return normalized
    }

    private static func validateCountdown(_ draft: CampusAIActionDraft) -> CampusAIActionDraft? {
        let title = draft.payload.countdownTitle?.nonEmptyTrimmed ?? draft.payload.title?.nonEmptyTrimmed
        guard let title, parseDate(draft.payload.targetDate) != nil else {
            return nil
        }
        var normalized = draft
        normalized.title = normalized.title.nonEmptyTrimmed ?? "添加日程"
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

    private static func parseDateTime(_ value: String?) -> Date? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        if let date = ISO8601DateFormatter().date(from: value) {
            return date
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone.current
        for format in ["yyyy-MM-dd HH:mm", "yyyy-MM-dd'T'HH:mm"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
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
        title: "添加日程",
        detail: "使用兼容动作打开统一日程表单。",
        systemImageName: "calendar.badge.clock",
        actionKind: .createCountdown,
        toolName: nil,
        requiresConfirmation: true
    )

    static let createSchedule = CampusAIToolDescriptor(
        id: CampusAIActionKind.createSchedule.rawValue,
        title: "添加日程",
        detail: "填写日期、时间和可选的地点、备注后保存日程。",
        systemImageName: "calendar.badge.plus",
        actionKind: .createSchedule,
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
            createSchedule,
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
                kind: CampusAIActionKind.createSchedule.rawValue,
                requiredPayloadFields: [],
                allowedValues: [
                    "startsAt": ["ISO 8601，包含本地时区"],
                    "endsAt": ["ISO 8601，包含本地时区"]
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
        includesGrades: false,
        includesExamsAndPlans: true,
        includesLearningWorkspace: false,
        includesPostgraduateAndCareer: false,
        includesHonorsFitnessQuality: false,
        includesMedicalLedger: false,
        includesCommunityCache: false
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

    private static let storageKey = "campusAI.userSettings.v5"
    private static let unsafeDefaultsStorageKey = "campusAI.userSettings.v4"
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

        if let data = userDefaults.data(forKey: unsafeDefaultsStorageKey),
           var settings = try? JSONDecoder().decode(CampusAIUserSettings.self, from: data) {
            // v4 defaulted every personal scope on. Reset once instead of
            // guessing which scopes the user knowingly enabled.
            settings.contextSettings = .defaultValue
            let migrated = migrateDefaultPrompt(in: settings.normalizedForLocalRuntime)
            save(migrated, userDefaults: userDefaults)
            userDefaults.removeObject(forKey: unsafeDefaultsStorageKey)
            return migrated
        }

        if let data = userDefaults.data(forKey: previousStorageKey),
           var settings = try? JSONDecoder().decode(CampusAIUserSettings.self, from: data) {
            settings.serviceMode = .leafyManaged
            settings.contextSettings = .defaultValue
            let migrated = migrateDefaultPrompt(in: settings)
            save(migrated, userDefaults: userDefaults)
            userDefaults.removeObject(forKey: previousStorageKey)
            return migrated
        }

        if let data = userDefaults.data(forKey: olderStorageKey),
           var settings = try? JSONDecoder().decode(CampusAIUserSettings.self, from: data) {
            settings.serviceMode = .leafyManaged
            settings.webSearchEnabled = true
            settings.contextSettings = .defaultValue
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
            contextSettings: .defaultValue
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
        userDefaults.removeObject(forKey: unsafeDefaultsStorageKey)
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
    let actionPlanningRequested: Bool

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
        case actionPlanningRequested
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
        outputMode: CampusAIOutputMode = .automatic,
        actionPlanningRequested: Bool = false
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
        self.actionPlanningRequested = actionPlanningRequested
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
        actionPlanningRequested = try container.decodeIfPresent(Bool.self, forKey: .actionPlanningRequested) ?? false
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
        try container.encode(actionPlanningRequested, forKey: .actionPlanningRequested)
    }
}
import Foundation
