import Foundation
import os

@MainActor
struct CampusAIConversationProjection {
    static let empty = CampusAIConversationProjection(
        selectedConversationID: nil,
        conversations: [],
        messages: [],
        actionRecords: []
    )

    let conversation: CampusAIConversation?
    let messages: [CampusAIMessage]

    private let actionRecordsByMessageID: [String: [CampusAIActionRecord]]

    init(
        selectedConversationID: UUID?,
        conversations: [CampusAIConversation],
        messages: [CampusAIMessage],
        actionRecords: [CampusAIActionRecord]
    ) {
        let state = LeafyPerformanceSignposter.leafyAI.beginInterval("conversation-projection")
        defer { LeafyPerformanceSignposter.leafyAI.endInterval("conversation-projection", state) }

        if let selectedConversationID,
           let selected = conversations.first(where: { $0.id == selectedConversationID }) {
            conversation = selected
        } else {
            conversation = conversations.first
        }

        guard let conversation else {
            self.messages = []
            actionRecordsByMessageID = [:]
            return
        }

        let conversationKey = conversation.id.uuidString
        self.messages = messages.filter { $0.conversationID == conversationKey }
        actionRecordsByMessageID = Dictionary(
            grouping: actionRecords.lazy.filter { $0.conversationID == conversationKey },
            by: \.messageID
        )
    }

    func actionRecords(for message: CampusAIMessage) -> [CampusAIActionRecord] {
        actionRecordsByMessageID[message.id.uuidString] ?? []
    }
}
