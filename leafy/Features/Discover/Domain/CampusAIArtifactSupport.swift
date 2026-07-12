import Foundation
import OSLog

nonisolated enum CampusAIOutputMode: String, Codable, Hashable, Sendable {
    case automatic
    case artifact
}

nonisolated enum CampusAIArtifactGenerationState: String, Codable, Hashable, Sendable {
    case none
    case generating
    case ready
    case failed
}

nonisolated struct CampusAIArtifactDraft: Codable, Hashable, Sendable {
    var title: String
    var summary: String
    var markdown: String

    init(title: String, summary: String, markdown: String) {
        self.title = title
        self.summary = summary
        self.markdown = markdown
    }

    var validated: CampusAIArtifactDraft? {
        guard let title = title.nonEmptyTrimmed,
              let summary = summary.nonEmptyTrimmed,
              let markdown = markdown.nonEmptyTrimmed
        else { return nil }
        return CampusAIArtifactDraft(
            title: String(title.prefix(100)),
            summary: String(summary.prefix(280)),
            markdown: String(markdown.prefix(30_000))
        )
    }
}

nonisolated struct CampusAICompletionPlan: Codable, Hashable {
    var actions: [CampusAIActionDraft]
    var artifact: CampusAIArtifactDraft?

    init(actions: [CampusAIActionDraft] = [], artifact: CampusAIArtifactDraft? = nil) {
        self.actions = Array(CampusAIActionValidation.validated(actions).prefix(3))
        self.artifact = artifact?.validated
    }
}

nonisolated enum CampusAIArtifactExportFormat: String, CaseIterable, Identifiable, Hashable, Sendable {
    case html
    case markdown
    case plainText

    var id: String { rawValue }

    var title: String {
        switch self {
        case .html: return "HTML"
        case .markdown: return "Markdown"
        case .plainText: return "纯文本"
        }
    }

    var systemImage: String {
        switch self {
        case .html: return "chevron.left.forwardslash.chevron.right"
        case .markdown: return "text.document"
        case .plainText: return "doc.plaintext"
        }
    }

    var fileExtension: String {
        switch self {
        case .html: return "html"
        case .markdown: return "md"
        case .plainText: return "txt"
        }
    }
}

nonisolated enum CampusAIArtifactIntentResolver {
    private static let artifactIntentPhrases = [
        "计划", "规划", "方案", "报告", "清单", "表格", "流程图", "路线图", "复习表",
        "学习安排", "时间安排", "执行步骤", "行动项", "备忘录", "总结文档", "整理成文档",
        "生成文档", "做成表格", "做成清单", "给我一份", "输出一份"
    ]

    static func shouldGenerateArtifact(message: String, mode: CampusAIOutputMode) -> Bool {
        if mode == .artifact { return true }
        let normalized = message
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return artifactIntentPhrases.contains { normalized.contains($0) }
    }
}

nonisolated enum CampusAICompletionPlanParser {
    static func parse(_ content: String) throws -> CampusAICompletionPlan {
        let decoder = JSONDecoder()
        for candidate in jsonCandidates(from: content) {
            guard let data = candidate.data(using: .utf8) else { continue }
            if let plan = try? decoder.decode(CampusAICompletionPlan.self, from: data) {
                return CampusAICompletionPlan(actions: plan.actions, artifact: plan.artifact)
            }
            if let actions = try? decoder.decode([CampusAIActionDraft].self, from: data) {
                return CampusAICompletionPlan(actions: actions)
            }
        }
        throw CampusAICompletionPlanError.invalidResponse
    }

    private static func jsonCandidates(from content: String) -> [String] {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let unfenced: String
        if trimmed.hasPrefix("```") {
            let lines = trimmed
                .replacingOccurrences(of: "\r\n", with: "\n")
                .split(separator: "\n", omittingEmptySubsequences: false)
            let dropsClosingFence = lines.last?.trimmingCharacters(in: .whitespacesAndNewlines) == "```"
            unfenced = lines
                .dropFirst()
                .dropLast(dropsClosingFence ? 1 : 0)
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            unfenced = trimmed
        }

        var candidates = [unfenced]
        if let start = unfenced.firstIndex(of: "{"), let end = unfenced.lastIndex(of: "}"), start <= end {
            candidates.append(String(unfenced[start...end]))
        }
        var seen = Set<String>()
        return candidates.filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}

nonisolated enum CampusAICompletionPlanError: LocalizedError {
    case invalidResponse
    case artifactMissing

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "成品整理结果无法解析，请重试。"
        case .artifactMissing:
            return "这次没有生成成品内容，请重试。"
        }
    }
}

nonisolated enum CampusAIArtifactAssembler {
    static func deliverable(
        from draft: CampusAIArtifactDraft,
        request: CampusAIRequest,
        generatedAt: Date = Date()
    ) -> CampusAIDeliverable? {
        guard let draft = draft.validated else { return nil }
        let sources = request.localRetrieval.results.prefix(12).map { result in
            CampusAIDeliverableSource(
                id: "local-\(result.id)",
                title: result.title.nonEmptyTrimmed ?? result.domain.title,
                url: "leafy://local/\(result.domain.rawValue)/\(result.sourceID)",
                siteName: "Leafy 本机数据",
                summary: result.summary.nonEmptyTrimmed,
                trustScore: 1
            )
        }
        return CampusAIDeliverable(
            title: draft.title,
            query: request.message,
            summary: draft.summary,
            generatedAt: ISO8601DateFormatter().string(from: generatedAt),
            sources: sources,
            formats: [.html, .markdown, .txt],
            content: CampusAIArtifactContent(markdown: draft.markdown)
        )
    }
}

nonisolated enum CampusAIDiagnostics {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.myleafy.app",
        category: "CampusAI"
    )

    static func stage(_ name: String, requestID: UUID, duration: Duration? = nil) {
        if let duration {
            logger.info("stage=\(name, privacy: .public) request=\(requestID.uuidString, privacy: .public) duration=\(String(describing: duration), privacy: .public)")
        } else {
            logger.info("stage=\(name, privacy: .public) request=\(requestID.uuidString, privacy: .public)")
        }
    }

    static func artifact(_ state: CampusAIArtifactGenerationState, requestID: UUID) {
        logger.info("artifact=\(state.rawValue, privacy: .public) request=\(requestID.uuidString, privacy: .public)")
    }

    static func failure(_ error: Error, stage: String, requestID: UUID? = nil) {
        let request = requestID?.uuidString ?? "none"
        logger.error("stage=\(stage, privacy: .public) request=\(request, privacy: .public) error=\(String(describing: type(of: error)), privacy: .public)")
    }

    static func persistenceFailure(_ error: Error, operation: String) {
        logger.error("persistence=\(operation, privacy: .public) error=\(String(describing: type(of: error)), privacy: .public)")
    }
}

nonisolated private extension String {
    var nonEmptyTrimmed: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
