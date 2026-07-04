import Foundation

struct ExamArrangement: Identifiable, Codable, Hashable {
    let id: Int
    let courseID: String
    let name: String
    let date: String
    let start: String
    let end: String
    let location: String

    var startsAt: Date? {
        DateFormatters.examStart.date(from: "\(date) \(start)")
    }

    var endsAt: Date? {
        DateFormatters.examStart.date(from: "\(date) \(end)")
    }

    var isStarted: Bool {
        guard let startsAt else { return false }
        return startsAt <= Date()
    }
}

struct TeachingPlanSection: Identifiable, Codable, Hashable {
    var id: String { term }
    let term: String
    let courses: [TeachingPlanCourse]

    var totalCredits: Double {
        courses.reduce(0) { $0 + $1.credit }
    }
}

struct TeachingPlanCourse: Identifiable, Codable, Hashable {
    let id: Int
    let period: String
    let name: String
    let unit: String
    let credit: Double
    let duration: String
    let type: String
    let exam: String
}

struct GradeRankingRecord: Identifiable, Codable, Hashable {
    let term: String
    let rankingRange: String
    let rank: Int?
    let totalCount: Int?
    let percentile: Double?
    let metricText: String
    let rawFields: [String: String]

    var id: String {
        [
            term,
            rankingRange,
            metricText,
            rank.map(String.init) ?? "",
            totalCount.map(String.init) ?? ""
        ].joined(separator: "|")
    }

    var displayRank: String {
        guard let rank else { return "--" }
        if let totalCount {
            return "\(rank) / \(totalCount)"
        }
        return "\(rank)"
    }

    var displayPercentile: String {
        guard let percentile else { return "--" }
        return L10n.text("前 %.0f%%", percentile * 100)
    }

    var isOverall: Bool {
        term == "全部学期"
            || term == "总排名"
            || rawFields["记录类型"] == "总排名"
            || rawFields["范围"] == "全部学期"
    }

    var isPeriodRecord: Bool {
        !isOverall
    }
}

struct GradeCreditBucket: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let credits: Double

    init(id: String? = nil, name: String, credits: Double) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = cleanName.isEmpty ? L10n.text("未分类") : cleanName
        self.name = displayName
        self.credits = max(credits, 0)
        self.id = id ?? displayName
    }
}

struct GradeCreditSummary: Codable, Hashable {
    let totalCredits: Double
    let requiredCredits: Double
    let professionalElectiveCredits: Double
    let professionalMajorElectiveCredits: Double
    let professionalCrossMajorElectiveCredits: Double
    let publicElectiveCredits: Double
    let officialGPA: Double?
    let officialWeightedAverage: Double?
    let officialCreditPoint: Double?
    let publicElectiveBuckets: [GradeCreditBucket]
    let rawFields: [String: String]

    var hasCreditTotals: Bool {
        totalCredits > 0
            || requiredCredits > 0
            || professionalElectiveCredits > 0
            || professionalMajorElectiveCredits > 0
            || professionalCrossMajorElectiveCredits > 0
            || publicElectiveCredits > 0
            || !publicElectiveBuckets.isEmpty
    }

    var publicCoveredBuckets: [GradeCreditBucket] {
        publicElectiveBuckets.filter { $0.credits > 0 }
    }

    var publicMissingBucketNames: [String] {
        publicElectiveBuckets
            .filter { $0.credits <= 0 }
            .map(\.name)
    }

    func mergedForCache(with existing: GradeCreditSummary?) -> GradeCreditSummary {
        guard let existing else { return self }

        let creditSource: GradeCreditSummary
        if hasCreditTotals {
            creditSource = self
        } else if existing.hasCreditTotals {
            creditSource = existing
        } else {
            creditSource = self
        }

        return GradeCreditSummary(
            totalCredits: creditSource.totalCredits,
            requiredCredits: creditSource.requiredCredits,
            professionalElectiveCredits: creditSource.professionalElectiveCredits,
            professionalMajorElectiveCredits: creditSource.professionalMajorElectiveCredits,
            professionalCrossMajorElectiveCredits: creditSource.professionalCrossMajorElectiveCredits,
            publicElectiveCredits: creditSource.publicElectiveCredits,
            officialGPA: officialGPA ?? existing.officialGPA,
            officialWeightedAverage: officialWeightedAverage ?? existing.officialWeightedAverage,
            officialCreditPoint: officialCreditPoint ?? existing.officialCreditPoint,
            publicElectiveBuckets: creditSource.publicElectiveBuckets,
            rawFields: existing.rawFields.merging(rawFields) { _, new in new }
        )
    }
}

enum GraduationCreditKind: String, Codable, Hashable {
    case total
    case publicElective
    case professionalElective
    case other

    var displayName: String {
        switch self {
        case .total:
            return L10n.text("总学分")
        case .publicElective:
            return L10n.text("公选课")
        case .professionalElective:
            return L10n.text("专选课")
        case .other:
            return L10n.text("其他类别")
        }
    }

    static func classify(_ text: String) -> GraduationCreditKind {
        let compact = text
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .lowercased()

        if compact.contains("总学分") || compact == "合计" || compact == "总计" {
            return .total
        }

        let publicMarkers = ["公共选修", "通识选修", "校选", "公选"]
        if publicMarkers.contains(where: compact.contains) {
            return .publicElective
        }

        let professionalMarkers = ["专业选修", "专业任选", "专业限选", "专选"]
        if professionalMarkers.contains(where: compact.contains) {
            return .professionalElective
        }

        return .other
    }
}

struct GraduationCreditRequirement: Identifiable, Codable, Hashable {
    let id: String
    let category: String
    let kind: GraduationCreditKind
    let courseName: String
    let requiredCredits: Double
    let plannedCredits: Double
    let isAggregate: Bool

    init(
        id: String,
        category: String,
        kind: GraduationCreditKind? = nil,
        courseName: String,
        requiredCredits: Double,
        plannedCredits: Double,
        isAggregate: Bool
    ) {
        let cleanCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCourseName = courseName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.id = id
        self.category = cleanCategory.isEmpty ? L10n.text("未分类") : cleanCategory
        self.kind = kind ?? GraduationCreditKind.classify(cleanCategory + cleanCourseName)
        self.courseName = cleanCourseName
        self.requiredCredits = requiredCredits
        self.plannedCredits = plannedCredits
        self.isAggregate = isAggregate
    }

    var displayCategory: String {
        switch kind {
        case .total, .publicElective, .professionalElective:
            return kind.displayName
        case .other:
            return category
        }
    }
}

struct TrainingProgramDocument: Identifiable, Codable, Hashable {
    var id: String { title }
    let title: String
    let sections: [TrainingProgramSection]
    let creditRequirements: [GraduationCreditRequirement]
}

struct TrainingProgramSection: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let body: String
}

struct GraduationCreditCategoryProgress: Identifiable, Hashable {
    let category: String
    let kind: GraduationCreditKind
    let requiredCredits: Double
    let completedCredits: Double
    let completedCourseCount: Int
    let estimatedRemainingCourses: Int?
    let completedBuckets: [GradeCreditBucket]
    let missingBucketNames: [String]

    var id: String { "\(kind.rawValue)-\(category)" }

    var remainingCredits: Double {
        max(requiredCredits - completedCredits, 0)
    }

    var completionRatio: Double? {
        guard requiredCredits > 0 else { return nil }
        return min(completedCredits / requiredCredits, 1)
    }

    var isSatisfied: Bool {
        requiredCredits > 0 && completedCredits + 0.001 >= requiredCredits
    }
}

struct GraduationCreditProgress: Hashable {
    let totalRequiredCredits: Double
    let totalCompletedCredits: Double
    let categories: [GraduationCreditCategoryProgress]
    let sourceRequirementCount: Int

    var totalRemainingCredits: Double {
        max(totalRequiredCredits - totalCompletedCredits, 0)
    }

    var totalCompletionRatio: Double? {
        guard totalRequiredCredits > 0 else { return nil }
        return min(totalCompletedCredits / totalRequiredCredits, 1)
    }

    var unresolvedCategories: [GraduationCreditCategoryProgress] {
        categories.filter {
            !$0.isSatisfied
                && $0.requiredCredits > 0
                && ($0.kind == .publicElective || $0.kind == .professionalElective)
        }
    }

    var hasRequirements: Bool {
        sourceRequirementCount > 0 && totalRequiredCredits > 0
    }
}

enum GraduationCreditProgressCalculator {
    static func calculate(
        requirements: [GraduationCreditRequirement],
        grades: [Grade],
        creditSummary: GradeCreditSummary? = nil
    ) -> GraduationCreditProgress {
        let passedGrades = EffectiveGradeCourseResolver.resolve(from: grades).compactMap { course -> PassedGradeCredit? in
            guard course.isPassed else {
                return nil
            }

            return PassedGradeCredit(
                name: course.name,
                credit: course.credit,
                kind: GraduationCreditKind.classify(course.type + course.name),
                category: fallbackCompletedCategory(type: course.type, courseName: course.name)
            )
        }

        let totalCompleted = creditSummary?.hasCreditTotals == true
            ? creditSummary?.totalCredits ?? 0
            : passedGrades.reduce(0) { $0 + $1.credit }
        let courseRequirements = requirements.filter { !$0.isAggregate && !$0.courseName.isEmpty }
        let aggregateRequirements = requirements.filter(\.isAggregate)
        let explicitTotal = aggregateRequirements
            .filter { $0.kind == .total }
            .map(\.requiredCredits)
            .max()

        let categoryRequirements = groupedCategoryRequirements(from: requirements)
        let totalRequired = explicitTotal
            ?? categoryRequirements.reduce(0) { $0 + $1.requiredCredits }
            .nonZero
            ?? requirements.reduce(0) { $0 + max($1.requiredCredits, $1.plannedCredits) }

        var requirementByCourseName: [String: GraduationCreditRequirement] = [:]
        for requirement in courseRequirements {
            let key = normalizedCourseName(requirement.courseName)
            if requirementByCourseName[key] == nil {
                requirementByCourseName[key] = requirement
            }
        }
        var completedByCategory: [String: (credits: Double, courses: Int)] = [:]

        for grade in passedGrades {
            let matchedRequirement = requirementByCourseName[normalizedCourseName(grade.name)]
            let displayCategory = matchedRequirement?.displayCategory ?? grade.category
            let key = categoryKey(kind: matchedRequirement?.kind ?? grade.kind, category: displayCategory)
            let current = completedByCategory[key] ?? (0, 0)
            completedByCategory[key] = (current.credits + grade.credit, current.courses + 1)
        }

        if let creditSummary, creditSummary.hasCreditTotals {
            let publicKey = categoryKey(kind: .publicElective, category: GraduationCreditKind.publicElective.displayName)
            completedByCategory[publicKey] = (
                creditSummary.publicElectiveCredits,
                estimatedCourseCount(
                    credits: creditSummary.publicElectiveCredits,
                    fallback: passedGrades.filter { $0.kind == .publicElective }.count
                )
            )

            let professionalKey = categoryKey(kind: .professionalElective, category: GraduationCreditKind.professionalElective.displayName)
            completedByCategory[professionalKey] = (
                creditSummary.professionalMajorElectiveCredits,
                estimatedCourseCount(
                    credits: creditSummary.professionalMajorElectiveCredits,
                    fallback: passedGrades.filter { $0.kind == .professionalElective }.count
                )
            )
        }

        let categories = categoryRequirements.map { requirement in
            let key = categoryKey(kind: requirement.kind, category: requirement.category)
            let completed = completedByCategory[key] ?? (0, 0)
            let remaining = max(requirement.requiredCredits - completed.credits, 0)
            let averageCredit = averageCourseCredit(
                for: requirement,
                completedCredits: completed.credits,
                completedCourses: completed.courses,
                courseRequirements: courseRequirements
            )
            let remainingCourses = remaining > 0 ? Int(ceil(remaining / averageCredit)) : 0

            return GraduationCreditCategoryProgress(
                category: requirement.category,
                kind: requirement.kind,
                requiredCredits: requirement.requiredCredits,
                completedCredits: completed.credits,
                completedCourseCount: completed.courses,
                estimatedRemainingCourses: remaining > 0 ? max(remainingCourses, 1) : 0,
                completedBuckets: requirement.kind == .publicElective ? (creditSummary?.publicCoveredBuckets ?? []) : [],
                missingBucketNames: requirement.kind == .publicElective ? (creditSummary?.publicMissingBucketNames ?? []) : []
            )
        }
        .sorted { lhs, rhs in
            if lhs.kind != rhs.kind {
                return sortOrder(lhs.kind) < sortOrder(rhs.kind)
            }
            return lhs.category.localizedCompare(rhs.category) == .orderedAscending
        }

        return GraduationCreditProgress(
            totalRequiredCredits: totalRequired,
            totalCompletedCredits: totalCompleted,
            categories: categories,
            sourceRequirementCount: requirements.count
        )
    }

    private struct PassedGradeCredit {
        let name: String
        let credit: Double
        let kind: GraduationCreditKind
        let category: String
    }

    private struct CategoryRequirement {
        let category: String
        let kind: GraduationCreditKind
        let requiredCredits: Double
    }

    private static func groupedCategoryRequirements(from requirements: [GraduationCreditRequirement]) -> [CategoryRequirement] {
        let nonTotal = requirements.filter { $0.kind != .total }
        let aggregate = nonTotal.filter(\.isAggregate)
        let source = aggregate.isEmpty ? nonTotal : aggregate
        var grouped: [String: CategoryRequirement] = [:]

        for requirement in source {
            let category = requirement.displayCategory
            let key = categoryKey(kind: requirement.kind, category: category)
            let credits = max(requirement.requiredCredits, requirement.plannedCredits)
            guard credits > 0 else { continue }

            if let current = grouped[key] {
                grouped[key] = CategoryRequirement(
                    category: current.category,
                    kind: current.kind,
                    requiredCredits: requirement.isAggregate ? max(current.requiredCredits, credits) : current.requiredCredits + credits
                )
            } else {
                grouped[key] = CategoryRequirement(
                    category: category,
                    kind: requirement.kind,
                    requiredCredits: credits
                )
            }
        }

        return Array(grouped.values)
    }

    private static func averageCourseCredit(
        for requirement: CategoryRequirement,
        completedCredits: Double,
        completedCourses: Int,
        courseRequirements: [GraduationCreditRequirement]
    ) -> Double {
        if completedCourses > 0 {
            return max(completedCredits / Double(completedCourses), 0.5)
        }

        let matchedCredits = courseRequirements
            .filter { $0.displayCategory == requirement.category }
            .map { max($0.requiredCredits, $0.plannedCredits) }
            .filter { $0 > 0 }

        if !matchedCredits.isEmpty {
            return max(matchedCredits.reduce(0, +) / Double(matchedCredits.count), 0.5)
        }

        return 2.0
    }

    private static func estimatedCourseCount(credits: Double, fallback: Int) -> Int {
        if fallback > 0 {
            return fallback
        }

        guard credits > 0 else { return 0 }
        return max(Int(ceil(credits / 2.0)), 1)
    }

    private static func fallbackCompletedCategory(type: String, courseName: String) -> String {
        let kind = GraduationCreditKind.classify(type + courseName)
        if kind == .publicElective || kind == .professionalElective {
            return kind.displayName
        }

        let trimmedType = type.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedType.isEmpty ? kind.displayName : trimmedType
    }

    private static func categoryKey(kind: GraduationCreditKind, category: String) -> String {
        "\(kind.rawValue)|\(category)"
    }

    private static func normalizedCourseName(_ name: String) -> String {
        name
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "　", with: "")
            .replacingOccurrences(of: "（", with: "(")
            .replacingOccurrences(of: "）", with: ")")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
    }

    private static func sortOrder(_ kind: GraduationCreditKind) -> Int {
        switch kind {
        case .publicElective:
            return 0
        case .professionalElective:
            return 1
        case .other:
            return 2
        case .total:
            return 3
        }
    }

}

private extension Double {
    var nonZero: Double? {
        self > 0 ? self : nil
    }
}

struct CountdownEvent: Identifiable, Hashable {
    enum Kind: String {
        case exam = "考试"
        case semester = "学期"
        case custom = "重要日期"
    }

    let id: String
    let title: String
    let targetDate: Date
    let kind: Kind

    var isExpired: Bool {
        targetDate <= Date()
    }
}

nonisolated struct CustomScheduleEvent: Identifiable, Codable, Hashable {
    let id: String
    var title: String
    var startsAt: Date
    var endsAt: Date?
    var location: String?
    var note: String?
    var minutesBefore: Int

    init(
        id: String = UUID().uuidString,
        title: String,
        startsAt: Date,
        endsAt: Date? = nil,
        location: String = "",
        note: String = "",
        minutesBefore: Int = 0
    ) {
        self.id = id
        self.title = title
        self.startsAt = startsAt
        self.endsAt = endsAt.flatMap { $0 > startsAt ? $0 : nil }
        self.location = Self.normalizedOptionalText(location)
        self.note = Self.normalizedOptionalText(note)
        self.minutesBefore = max(0, minutesBefore)
    }

    init(id: String = UUID().uuidString, title: String, targetDate: Date) {
        self.init(id: id, title: title, startsAt: targetDate)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case startsAt
        case targetDate
        case endsAt
        case location
        case note
        case minutesBefore
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        let decodedStart = try container.decodeIfPresent(Date.self, forKey: .startsAt)
            ?? container.decode(Date.self, forKey: .targetDate)
        startsAt = decodedStart
        let decodedEnd = try container.decodeIfPresent(Date.self, forKey: .endsAt)
        endsAt = decodedEnd.flatMap { $0 > decodedStart ? $0 : nil }
        location = Self.normalizedOptionalText(try container.decodeIfPresent(String.self, forKey: .location) ?? "")
        note = Self.normalizedOptionalText(try container.decodeIfPresent(String.self, forKey: .note) ?? "")
        minutesBefore = max(0, try container.decodeIfPresent(Int.self, forKey: .minutesBefore) ?? 0)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(startsAt, forKey: .startsAt)
        try container.encodeIfPresent(endsAt, forKey: .endsAt)
        try container.encodeIfPresent(location, forKey: .location)
        try container.encodeIfPresent(note, forKey: .note)
        try container.encode(minutesBefore, forKey: .minutesBefore)
    }

    var targetDate: Date {
        get { startsAt }
        set { startsAt = newValue }
    }

    var locationText: String {
        location?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    var noteText: String {
        note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func normalizedOptionalText(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

typealias CustomCountdownEvent = CustomScheduleEvent

struct TimetableCountdownProjection: Identifiable, Hashable {
    let eventID: String
    let title: String
    let targetDate: Date
    let week: Int
    let dayOfWeek: Int
    let period: Int

    var id: String {
        "\(eventID)-\(week)-\(dayOfWeek)-\(period)"
    }
}

struct TimetableExamProjection: Identifiable, Hashable {
    let examID: Int
    let name: String
    let startsAt: Date
    let startText: String
    let location: String
    let week: Int
    let dayOfWeek: Int
    let period: Int

    var id: String {
        "\(examID)-\(week)-\(dayOfWeek)-\(period)"
    }
}

extension ExamArrangement {
    var timetableProjection: TimetableExamProjection? {
        guard let startsAt else { return nil }

        let calendar = Calendar.current
        let semesterStart = calendar.startOfDay(for: SemesterConfig.startOfSemesterDate)
        let targetDay = calendar.startOfDay(for: startsAt)
        let dayOffset = calendar.dateComponents([.day], from: semesterStart, to: targetDay).day ?? 0
        guard dayOffset >= 0, dayOffset < SemesterConfig.supportedWeeks * 7 else {
            return nil
        }

        let schedule = SemesterConfig.weekAndDay(for: startsAt)
        let period = TimetablePeriodSchedule.period(containing: startsAt)?.period
            ?? TimetablePeriodSchedule.periodForFocus(containing: startsAt)?.period
            ?? 1

        return TimetableExamProjection(
            examID: id,
            name: name,
            startsAt: startsAt,
            startText: start,
            location: location,
            week: schedule.week,
            dayOfWeek: schedule.day,
            period: period
        )
    }
}

extension CustomScheduleEvent {
    var timetableProjection: TimetableCountdownProjection? {
        let calendar = Calendar.current
        let semesterStart = calendar.startOfDay(for: SemesterConfig.startOfSemesterDate)
        let targetDay = calendar.startOfDay(for: startsAt)
        let dayOffset = calendar.dateComponents([.day], from: semesterStart, to: targetDay).day ?? 0
        guard dayOffset >= 0, dayOffset < SemesterConfig.supportedWeeks * 7 else {
            return nil
        }

        let schedule = SemesterConfig.weekAndDay(for: startsAt)
        let period = TimetablePeriodSchedule.period(containing: startsAt)?.period
            ?? TimetablePeriodSchedule.periodForFocus(containing: startsAt)?.period
            ?? 1

        return TimetableCountdownProjection(
            eventID: id,
            title: title,
            targetDate: startsAt,
            week: schedule.week,
            dayOfWeek: schedule.day,
            period: period
        )
    }
}

extension Notification.Name {
    static let customScheduleEventsDidChange = Notification.Name("customScheduleEventsDidChange")
    static let customCountdownEventsDidChange = Notification.Name("customCountdownEventsDidChange")
    static let schoolExamScheduleDidChange = Notification.Name("schoolExamScheduleDidChange")
}

enum CustomScheduleStore {
    private struct LegacyCountdownEvent: Codable {
        let id: String
        let title: String
        let targetDate: Date
    }

    private static let storageKey = "customScheduleEvents.v1"
    private static let legacyCountdownStorageKey = "customCountdownEvents"

    static func load(defaults: UserDefaults = .standard) -> [CustomScheduleEvent] {
        if let data = defaults.data(forKey: storageKey),
           let events = try? JSONDecoder().decode([CustomScheduleEvent].self, from: data) {
            return events
        }

        let migrated = migratedLegacyEvents(defaults: defaults)
        if !migrated.isEmpty {
            save(migrated, defaults: defaults)
        }
        return migrated
    }

    static func save(_ events: [CustomScheduleEvent], defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(events) else { return }
        defaults.set(data, forKey: storageKey)
        NotificationCenter.default.post(name: .customScheduleEventsDidChange, object: nil)
        NotificationCenter.default.post(name: .customCountdownEventsDidChange, object: nil)
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: storageKey)
        defaults.removeObject(forKey: legacyCountdownStorageKey)
        NotificationCenter.default.post(name: .customScheduleEventsDidChange, object: nil)
        NotificationCenter.default.post(name: .customCountdownEventsDidChange, object: nil)
    }

    static func storageKeysForTesting() -> (current: String, legacy: String) {
        (storageKey, legacyCountdownStorageKey)
    }

    private static func migratedLegacyEvents(defaults: UserDefaults) -> [CustomScheduleEvent] {
        guard let legacyData = defaults.data(forKey: legacyCountdownStorageKey) else { return [] }

        if let legacyEvents = try? JSONDecoder().decode([LegacyCountdownEvent].self, from: legacyData) {
            return legacyEvents.map {
                CustomScheduleEvent(id: $0.id, title: $0.title, startsAt: $0.targetDate)
            }
        }

        return (try? JSONDecoder().decode([CustomScheduleEvent].self, from: legacyData)) ?? []
    }
}

enum CustomCountdownStore {
    static func load(defaults: UserDefaults = .standard) -> [CustomCountdownEvent] {
        CustomScheduleStore.load(defaults: defaults)
    }

    static func save(_ events: [CustomCountdownEvent], defaults: UserDefaults = .standard) {
        CustomScheduleStore.save(events, defaults: defaults)
    }

    static func clear(defaults: UserDefaults = .standard) {
        CustomScheduleStore.clear(defaults: defaults)
    }
}

nonisolated struct EmptyClassroom: Identifiable, Codable, Hashable, Sendable {
    var id: String { "\(building)-\(room)" }
    let building: String
    let room: String
}

nonisolated enum ClassroomUsageStatus: String, Codable, Hashable, Sendable {
    case available
    case occupied
    case unknown
}

nonisolated struct ClassroomUsageSlot: Identifiable, Codable, Hashable, Sendable {
    var id: Int { period }
    let period: Int
    let status: ClassroomUsageStatus

    var available: Bool {
        status == .available
    }

    init(period: Int, status: ClassroomUsageStatus) {
        self.period = period
        self.status = status
    }

    init(period: Int, available: Bool) {
        self.init(period: period, status: available ? .available : .occupied)
    }

    enum CodingKeys: String, CodingKey {
        case period
        case status
        case available
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        period = try container.decode(Int.self, forKey: .period)
        if let status = try container.decodeIfPresent(ClassroomUsageStatus.self, forKey: .status) {
            self.status = status
        } else {
            let available = try container.decode(Bool.self, forKey: .available)
            self.status = available ? .available : .occupied
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(period, forKey: .period)
        try container.encode(status, forKey: .status)
    }
}

struct CalendarAsset: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let url: URL
}

enum SchoolDataCache {
    private static let examScheduleKey = "schoolCache.examSchedule"
    private static let teachingPlanKey = "schoolCache.teachingPlan"
    private static let gradeRankingsKey = "schoolCache.gradeRankings"
    private static let gradeCreditSummaryKey = "schoolCache.gradeCreditSummary"
    private static let graduationRequirementsKey = "schoolCache.graduationRequirements"
    private static let trainingProgramKey = "schoolCache.trainingProgram"
    private static let emptyClassroomPrefix = "schoolCache.emptyClassrooms"
    private static let classroomUsagePrefix = "schoolCache.classroomUsage"
    private static let lastExamSyncKey = "schoolCache.lastExamScheduleSyncAt"
    private static let lastTeachingPlanSyncKey = "schoolCache.lastTeachingPlanSyncAt"
    private static let lastGradeDetailsSyncKey = "schoolCache.lastGradeDetailsSyncAt"
    private static let lastGradeRankingsSyncKey = "schoolCache.lastGradeRankingsSyncAt"
    private static let lastGraduationRequirementsSyncKey = "schoolCache.lastGraduationRequirementsSyncAt"
    private static let lastEmptyClassroomSyncKey = "schoolCache.lastEmptyClassroomSyncAt"

    static func loadExamSchedule() -> [ExamArrangement] {
        load([ExamArrangement].self, forKey: examScheduleKey) ?? []
    }

    static func saveExamSchedule(_ exams: [ExamArrangement], notifies: Bool = true) {
        save(exams, forKey: examScheduleKey)
        UserDefaults.standard.set(Date(), forKey: scoped(lastExamSyncKey))
        if notifies {
            NotificationCenter.default.post(name: .schoolExamScheduleDidChange, object: nil)
            SchoolDataRefreshNotifier.post(.exams)
        }
    }

    static func loadTeachingPlan() -> [TeachingPlanSection] {
        load([TeachingPlanSection].self, forKey: teachingPlanKey) ?? []
    }

    static func saveTeachingPlan(_ sections: [TeachingPlanSection], notifies: Bool = true) {
        save(sections, forKey: teachingPlanKey)
        UserDefaults.standard.set(Date(), forKey: scoped(lastTeachingPlanSyncKey))
        if notifies {
            SchoolDataRefreshNotifier.post(.teachingPlan)
        }
    }

    static func loadGradeRankings() -> [GradeRankingRecord] {
        load([GradeRankingRecord].self, forKey: gradeRankingsKey) ?? []
    }

    static func saveGradeRankings(_ rankings: [GradeRankingRecord], notifies: Bool = true) {
        save(rankings, forKey: gradeRankingsKey)
        UserDefaults.standard.set(Date(), forKey: scoped(lastGradeRankingsSyncKey))
        if notifies {
            SchoolDataRefreshNotifier.post(.gradeSupplemental)
        }
    }

    static func loadGradeCreditSummary() -> GradeCreditSummary? {
        load(GradeCreditSummary.self, forKey: gradeCreditSummaryKey)
    }

    static func markGradeDetailsSynced(at date: Date = Date()) {
        UserDefaults.standard.set(date, forKey: scoped(lastGradeDetailsSyncKey))
    }

    static func saveGradeCreditSummary(_ summary: GradeCreditSummary, notifies: Bool = true) {
        save(summary.mergedForCache(with: loadGradeCreditSummary()), forKey: gradeCreditSummaryKey)
        if notifies {
            SchoolDataRefreshNotifier.post(.gradeSupplemental)
        }
    }

    static func loadGraduationRequirements() -> [GraduationCreditRequirement] {
        load([GraduationCreditRequirement].self, forKey: graduationRequirementsKey) ?? []
    }

    static func saveGraduationRequirements(_ requirements: [GraduationCreditRequirement], notifies: Bool = true) {
        save(requirements, forKey: graduationRequirementsKey)
        UserDefaults.standard.set(Date(), forKey: scoped(lastGraduationRequirementsSyncKey))
        if notifies {
            SchoolDataRefreshNotifier.post(.trainingProgram)
        }
    }

    static func loadTrainingProgram() -> TrainingProgramDocument? {
        load(TrainingProgramDocument.self, forKey: trainingProgramKey)
    }

    static func saveTrainingProgram(_ document: TrainingProgramDocument, notifies: Bool = true) {
        save(document, forKey: trainingProgramKey)
        saveGraduationRequirements(document.creditRequirements, notifies: false)
        if notifies {
            SchoolDataRefreshNotifier.post(.trainingProgram)
        }
    }

    static func loadEmptyClassrooms(date: Date, start: Int, end: Int) -> [EmptyClassroom] {
        load([EmptyClassroom].self, forKey: emptyClassroomsKey(date: date, start: start, end: end)) ?? []
    }

    static func saveEmptyClassrooms(_ rooms: [EmptyClassroom], date: Date, start: Int, end: Int) {
        save(rooms, forKey: emptyClassroomsKey(date: date, start: start, end: end))
        UserDefaults.standard.set(Date(), forKey: scoped(lastEmptyClassroomSyncKey))
    }

    static func loadClassroomUsage(date: Date, building: String, room: String) -> [ClassroomUsageSlot] {
        load([ClassroomUsageSlot].self, forKey: classroomUsageKey(date: date, building: building, room: room)) ?? []
    }

    static func saveClassroomUsage(_ usage: [ClassroomUsageSlot], date: Date, building: String, room: String) {
        save(usage, forKey: classroomUsageKey(date: date, building: building, room: room))
        UserDefaults.standard.set(Date(), forKey: scoped(lastEmptyClassroomSyncKey))
    }

    static func lastSyncDate(for kind: SchoolCacheKind) -> Date? {
        migrateLegacyValues()
        switch kind {
        case .examSchedule:
            return UserDefaults.standard.object(forKey: scoped(lastExamSyncKey)) as? Date
        case .teachingPlan:
            return UserDefaults.standard.object(forKey: scoped(lastTeachingPlanSyncKey)) as? Date
        case .gradeDetails:
            return UserDefaults.standard.object(forKey: scoped(lastGradeDetailsSyncKey)) as? Date
        case .gradeRankings:
            return UserDefaults.standard.object(forKey: scoped(lastGradeRankingsSyncKey)) as? Date
        case .graduationRequirements:
            return UserDefaults.standard.object(forKey: scoped(lastGraduationRequirementsSyncKey)) as? Date
        case .classrooms:
            return UserDefaults.standard.object(forKey: scoped(lastEmptyClassroomSyncKey)) as? Date
        }
    }

    static func clearDiscoverCaches() {
        let defaults = UserDefaults.standard
        fixedKeys.forEach { defaults.removeObject(forKey: scoped($0)) }

        let scopedEmptyClassroomPrefix = scoped(emptyClassroomPrefix)
        let scopedClassroomUsagePrefix = scoped(classroomUsagePrefix)
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix(scopedEmptyClassroomPrefix) || key.hasPrefix(scopedClassroomUsagePrefix) {
            defaults.removeObject(forKey: key)
        }
    }

    private static func emptyClassroomsKey(date: Date, start: Int, end: Int) -> String {
        "\(emptyClassroomPrefix).\(DateFormatters.queryDate.string(from: date)).\(start).\(end)"
    }

    private static func classroomUsageKey(date: Date, building: String, room: String) -> String {
        "\(classroomUsagePrefix).\(DateFormatters.queryDate.string(from: date)).\(building).\(room)"
    }

    private static func load<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        migrateLegacyValues()
        guard let data = UserDefaults.standard.data(forKey: scoped(key)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func save<T: Encodable>(_ value: T, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: scoped(key))
    }

    private static var fixedKeys: [String] {
        [
            examScheduleKey,
            teachingPlanKey,
            gradeRankingsKey,
            gradeCreditSummaryKey,
            graduationRequirementsKey,
            trainingProgramKey,
            lastExamSyncKey,
            lastTeachingPlanSyncKey,
            lastGradeDetailsSyncKey,
            lastGradeRankingsSyncKey,
            lastGraduationRequirementsSyncKey,
            lastEmptyClassroomSyncKey
        ]
    }

    private static func scoped(_ key: String) -> String {
        CampusScopedDefaults.key(key)
    }

    private static func migrateLegacyValues() {
        CampusScopedDefaults.migrateLegacyValuesIfNeeded(
            keys: fixedKeys,
            prefixes: [emptyClassroomPrefix, classroomUsagePrefix],
            migrationID: "schoolDataCache"
        )
    }
}

enum SchoolCacheKind {
    case examSchedule
    case teachingPlan
    case gradeDetails
    case gradeRankings
    case graduationRequirements
    case classrooms
}

enum DateFormatters {
    static let examStart: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    static let chineseDay: DateFormatter = localizedFormatter(chineseFormat: "M月d日")

    static let queryDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static let header: DateFormatter = localizedFormatter(chineseFormat: "M月d日 EEEE")

    static let headerWithTime: DateFormatter = localizedFormatter(chineseFormat: "M月d日 EEEE HH:mm")

    static let timeOnly: DateFormatter = localizedFormatter(chineseFormat: "HH:mm")

    /// `yyyy年M月d日 EEEE` — full date with weekday (timetable header).
    static let fullDateWithWeekday: DateFormatter = localizedFormatter(chineseFormat: "yyyy年M月d日 EEEE")

    private static func localizedFormatter(chineseFormat: String) -> DateFormatter {
        let language = AppLanguagePreference.current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language.localeIdentifier)
        formatter.dateFormat = chineseFormat
        return formatter
    }
}
