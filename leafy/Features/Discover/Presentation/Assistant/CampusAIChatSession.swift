import Foundation
import Observation

@MainActor
@Observable
final class CampusAIChatSession {
    enum Stage: Equatable {
        case idle
        case analyzingLocalData
        case streamingAnswer
        case planningActions
        case assemblingArtifact
    }

    private(set) var isSending = false
    private(set) var stage: Stage = .idle
    private(set) var activeRunID: UUID?
    private(set) var activeConversationID: UUID?
    private(set) var activeMessageID: UUID?
    private var activeTask: Task<Void, Never>?

    func start(_ operation: @escaping @MainActor (UUID) async -> Void) {
        guard activeTask == nil, !isSending else { return }
        let runID = UUID()
        activeRunID = runID
        isSending = true
        stage = .analyzingLocalData
        activeTask = Task {
            await operation(runID)
            completeRun(runID)
        }
    }

    func markStreaming(conversationID: UUID, messageID: UUID) {
        isSending = true
        activeConversationID = conversationID
        activeMessageID = messageID
        stage = .streamingAnswer
    }

    func update(statusText: String) {
        if statusText.contains("卡片") {
            stage = .assemblingArtifact
        } else if statusText.contains("动作") || statusText.contains("规划") {
            stage = .planningActions
        } else if statusText.contains("本机") || statusText.contains("分析") {
            stage = .analyzingLocalData
        }
    }

    func finish(runID: UUID, messageID: UUID) {
        completeRun(runID)
        if activeMessageID == messageID {
            activeConversationID = nil
            activeMessageID = nil
        }
    }

    func cancel() {
        activeTask?.cancel()
        activeTask = nil
        activeRunID = nil
        isSending = false
        stage = .idle
    }

    private func completeRun(_ runID: UUID) {
        guard activeRunID == runID else { return }
        activeTask = nil
        activeRunID = nil
        isSending = false
        stage = .idle
    }
}
