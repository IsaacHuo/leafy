import Foundation

struct CampusAIArtifactLibraryItem: Identifiable, Hashable {
    let id: String
    let messageID: UUID
    let conversationID: UUID?
    let conversationTitle: String
    let deliverable: CampusAIDeliverable
    let generatedAt: Date
}

enum CampusAIArtifactLibraryIndex {
    static func items(
        messages: [CampusAIMessage],
        conversations: [CampusAIConversation]
    ) -> [CampusAIArtifactLibraryItem] {
        let conversationLookup = Dictionary(
            uniqueKeysWithValues: conversations.map { ($0.id.uuidString, $0) }
        )
        let formatter = ISO8601DateFormatter()

        return messages.flatMap { message -> [CampusAIArtifactLibraryItem] in
            let metadata = message.agentMetadata
            guard metadata.artifactState != .failed else { return [] }
            let conversation = conversationLookup[message.conversationID]

            return metadata.deliverables.compactMap { deliverable in
                guard let rawMarkdown = deliverable.content?.markdown,
                      let markdown = rawMarkdown.nonEmptyTrimmed
                else { return nil }
                var normalizedDeliverable = deliverable
                normalizedDeliverable.content = CampusAIArtifactContent(markdown: markdown)
                return CampusAIArtifactLibraryItem(
                    id: "\(message.id.uuidString):\(deliverable.id)",
                    messageID: message.id,
                    conversationID: conversation?.id,
                    conversationTitle: conversation?.title.nonEmptyTrimmed ?? "已删除的对话",
                    deliverable: normalizedDeliverable,
                    generatedAt: formatter.date(from: deliverable.generatedAt) ?? message.createdAt
                )
            }
        }
        .sorted {
            if $0.generatedAt == $1.generatedAt {
                return $0.id > $1.id
            }
            return $0.generatedAt > $1.generatedAt
        }
    }
}

enum CampusAIWorkspaceSearch {
    static func conversations(
        _ conversations: [CampusAIConversation],
        query: String
    ) -> [CampusAIConversation] {
        guard let query = query.nonEmptyTrimmed else { return [] }
        return conversations.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
                $0.summary.localizedCaseInsensitiveContains(query)
        }
    }

    static func artifacts(
        _ artifacts: [CampusAIArtifactLibraryItem],
        query: String
    ) -> [CampusAIArtifactLibraryItem] {
        guard let query = query.nonEmptyTrimmed else { return [] }
        return artifacts.filter {
            $0.deliverable.title.localizedCaseInsensitiveContains(query) ||
                $0.deliverable.summary.localizedCaseInsensitiveContains(query)
        }
    }
}

private extension String {
    var nonEmptyTrimmed: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
