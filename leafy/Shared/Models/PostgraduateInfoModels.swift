import Foundation

nonisolated enum PostgraduateSourceKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case admissionNotice = "admission_notice"
    case majorCatalog = "major_catalog"
    case scoreLine = "score_line"
    case enrollmentPlan = "enrollment_plan"
    case bibliography = "bibliography"
    case retest = "retest"
    case registration = "registration"
    case other

    var id: String { rawValue }

    static func normalized(_ rawValue: String) -> PostgraduateSourceKind {
        PostgraduateSourceKind(rawValue: rawValue) ?? .other
    }
}

nonisolated enum PostgraduateSourceTrustLevel: String, Codable, CaseIterable, Identifiable, Sendable {
    case official
    case curated
    case verifiedUser = "verified_user"

    var id: String { rawValue }

    static func normalized(_ rawValue: String) -> PostgraduateSourceTrustLevel {
        PostgraduateSourceTrustLevel(rawValue: rawValue) ?? .curated
    }
}

nonisolated struct PostgraduateSource: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let title: String
    let summary: String
    let sourceURLString: String
    let sourceKindRawValue: String
    let trustLevelRawValue: String
    let school: String?
    let unit: String?
    let major: String?
    let examYear: Int?
    let publishedAt: String?
    let verifiedAt: String?
    let status: String
    let createdAt: String?
    let updatedAt: String?

    var sourceURL: URL? {
        URL(string: sourceURLString)
    }

    var sourceKind: PostgraduateSourceKind {
        PostgraduateSourceKind.normalized(sourceKindRawValue)
    }

    var trustLevel: PostgraduateSourceTrustLevel {
        PostgraduateSourceTrustLevel.normalized(trustLevelRawValue)
    }

    var scopeText: String {
        let parts = [
            school,
            unit,
            major,
            examYear.map { "\($0)" }
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? "通用信息" : parts.joined(separator: " · ")
    }

    var isBJFUSpecific: Bool {
        let text = [title, summary, sourceURLString, school, unit]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
        return text.contains("北京林业大学") || text.contains("bjfu")
    }

    var sortDate: Date {
        PostgraduateDateParser.date(from: verifiedAt)
            ?? PostgraduateDateParser.date(from: publishedAt)
            ?? PostgraduateDateParser.date(from: updatedAt)
            ?? .distantPast
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case summary
        case sourceURLString = "source_url"
        case sourceKindRawValue = "source_kind"
        case trustLevelRawValue = "trust_level"
        case school
        case unit
        case major
        case examYear = "exam_year"
        case publishedAt = "published_at"
        case verifiedAt = "verified_at"
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

nonisolated enum PostgraduateSourceMatcher {
    static func sortedSources(
        for target: PostgraduateTarget,
        from sources: [PostgraduateSource],
        includingGeneral: Bool = true
    ) -> [PostgraduateSource] {
        sources
            .map { (source: $0, score: score(source: $0, target: target, includingGeneral: includingGeneral)) }
            .filter { $0.score > 0 }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                if lhs.source.trustLevel.rank != rhs.source.trustLevel.rank {
                    return lhs.source.trustLevel.rank > rhs.source.trustLevel.rank
                }
                return lhs.source.sortDate > rhs.source.sortDate
            }
            .map(\.source)
    }

    static func score(
        source: PostgraduateSource,
        target: PostgraduateTarget,
        includingGeneral: Bool = true
    ) -> Int {
        let targetSchool = PostgraduateTarget.normalizedText(target.school)
        let targetUnit = PostgraduateTarget.normalizedText(target.unit)
        let targetMajor = PostgraduateTarget.normalizedText(target.major)
        let sourceSchool = PostgraduateTarget.normalizedText(source.school ?? "")
        let sourceUnit = PostgraduateTarget.normalizedText(source.unit ?? "")
        let sourceMajor = PostgraduateTarget.normalizedText(source.major ?? "")
        let haystack = PostgraduateTarget.normalizedText(
            [source.title, source.summary, source.school, source.unit, source.major]
                .compactMap { $0 }
                .joined(separator: " ")
        )

        var score = 0
        score += fieldScore(source: sourceSchool, target: targetSchool, exact: 60, partial: 30)
        score += fieldScore(source: sourceMajor, target: targetMajor, exact: 60, partial: 30)
        score += fieldScore(source: sourceUnit, target: targetUnit, exact: 20, partial: 10)

        if !targetSchool.isEmpty, haystack.contains(targetSchool) { score += 10 }
        if !targetMajor.isEmpty, haystack.contains(targetMajor) { score += 10 }

        let isGeneral = sourceSchool.isEmpty && sourceUnit.isEmpty && sourceMajor.isEmpty
        if let examYear = source.examYear {
            if examYear == target.examYear, score > 0 || isGeneral {
                score += 40
            } else if score > 0 {
                score -= 10
            }
        } else if score > 0 {
            score += 4
        }

        let isYearlessGeneral = isGeneral && source.examYear == nil
        if score == 0, includingGeneral, isYearlessGeneral {
            return 1
        }

        return max(score, 0)
    }

    private static func fieldScore(source: String, target: String, exact: Int, partial: Int) -> Int {
        guard !source.isEmpty, !target.isEmpty else { return 0 }
        if source == target { return exact }
        if source.contains(target) || target.contains(source) { return partial }
        return 0
    }
}

private nonisolated enum PostgraduateDateParser {
    static func date(from value: String?) -> Date? {
        guard let value else { return nil }
        return ISO8601DateFormatter().date(from: value)
    }
}

private nonisolated extension PostgraduateSourceTrustLevel {
    var rank: Int {
        switch self {
        case .official:
            return 3
        case .curated:
            return 2
        case .verifiedUser:
            return 1
        }
    }
}
