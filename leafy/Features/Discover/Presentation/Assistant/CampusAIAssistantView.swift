import SwiftData
import SwiftUI

struct CampusAIAssistantView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appNavigation: AppNavigationCoordinator
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @AppStorage(Self.experimentalNoticeAcknowledgedKey) private var experimentalNoticeAcknowledged = false
    @FocusState private var isComposerFocused: Bool
    @Query(sort: \CampusAIConversation.updatedAt, order: .reverse) private var conversations: [CampusAIConversation]
    @Query(sort: \CampusAIMessage.createdAt, order: .forward) private var messages: [CampusAIMessage]
    @Query(sort: \CampusAIActionRecord.createdAt, order: .forward) private var actionRecords: [CampusAIActionRecord]

    var service = CampusAIService()

    @State private var selectedConversationID: UUID?
    @State private var draftText = ""
    @State private var outputMode: CampusAIOutputMode = .automatic
    @State private var chatSession = CampusAIChatSession()
    @State private var pendingRegenerationUserMessageID: UUID?
    @State private var discardedStreamMessageIDs: Set<UUID> = []
    @State private var userSettings = CampusAISettingsStore.load()
    @State private var activeSheet: CampusAISheetDestination?
    @State private var activeAlert: CampusAIAlert?
    @State private var operationAlert: LeafyOperationAlert?
    @State private var visibleSuggestionPrompts = Self.randomSuggestionPrompts()
    @State private var configuredProviderIDs: Set<CampusAIProviderID> = []
    @State private var artifactCompletionSignal = 0

    private var hasAPIKey: Bool {
        configuredProviderIDs.contains(userSettings.selectedProviderID)
    }

    private var isSending: Bool { chatSession.isSending }

    private var selectedConversation: CampusAIConversation? {
        if let selectedConversationID,
           let selected = conversations.first(where: { $0.id == selectedConversationID }) {
            return selected
        }
        return conversations.first
    }

    private var selectedConversationKey: String? {
        selectedConversation?.id.uuidString
    }

    private var selectedMessages: [CampusAIMessage] {
        guard let key = selectedConversationKey else { return [] }
        return messages.filter { $0.conversationID == key }
    }

    private func actionRecords(for message: CampusAIMessage) -> [CampusAIActionRecord] {
        actionRecords.filter {
            $0.conversationID == message.conversationID &&
                $0.messageID == message.id.uuidString
        }
    }

    private var contextPayload: CampusAIContextPayload {
        CampusAIContextBuilder.build(modelContext: modelContext, settings: userSettings.contextSettings)
    }

    var body: some View {
        NavigationStack {
            conversationScroll
                .background(AppTheme.cardElevated)
                .navigationTitle("Leafy")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            isComposerFocused = false
                            activeSheet = .history
                        } label: {
                            Label("历史记录", systemImage: "line.3.horizontal")
                        }
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: startNewConversation) {
                            Label("新建对话", systemImage: "square.and.pencil")
                        }
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    CampusAIComposerBar(
                        draftText: $draftText,
                        outputMode: $outputMode,
                        isFocused: $isComposerFocused,
                        isSending: isSending,
                        canSend: canSend,
                        hasAPIKey: hasAPIKey,
                        configureAPIKey: openAPIKeySetup,
                        submit: submitDraft,
                        cancelStreaming: cancelStreaming
                    )
                }
        }
        .onAppear {
            selectInitialConversationIfNeeded()
            presentExperimentalNoticeIfNeeded()
            refreshConfiguredProviders()
            pruneOrphanedDeliverableArtifacts()
        }
        .onChange(of: conversations.map(\.id)) { _, _ in
            selectInitialConversationIfNeeded()
        }
        .sheet(item: $activeSheet, onDismiss: handleSheetDismissal) { destination in
            switch destination {
            case .history:
                CampusAIHistorySheet(
                    conversations: conversations,
                    selectedConversationID: selectedConversation?.id,
                    selectConversation: { selectedConversationID = $0.id },
                    deleteConversation: deleteConversation,
                    clearHistory: clearAllHistory,
                    openSettings: { activeSheet = .settings }
                )
            case .settings:
                CampusAISettingsView(settings: $userSettings)
            case .apiKey:
                NavigationStack {
                    CampusAIAPIKeySetupView(
                        settings: $userSettings,
                        focusesOnAppear: true,
                        onAPIKeyChanged: refreshConfiguredProviders
                    )
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("取消") { activeSheet = nil }
                        }
                    }
                }
            case .actionEditor(let presentation):
                CampusAIActionEditorSheet(presentation: presentation) { draft in
                    Task {
                        await confirmActionEditor(presentation, draft: draft)
                    }
                }
            }
        }
        .alert(item: $activeAlert) { alert in
            switch alert {
            case .experimentalNotice:
                return Alert(
                    title: Text("Leafy AI 仍在实验阶段"),
                    message: Text("AI 问答功能还在测试中，回复可能会有错误、遗漏或过时内容。涉及课程、考试、成绩、医疗、手续等事项，请以学校官方系统和最新通知为准。"),
                    dismissButton: .default(Text("我知道了")) {
                        experimentalNoticeAcknowledged = true
                    }
                )
            }
        }
        .leafyOperationAlert($operationAlert)
        .sensoryFeedback(.success, trigger: artifactCompletionSignal)
    }

    private var conversationScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: AppSpacing.card) {
                    if selectedMessages.isEmpty {
                        CampusAIEmptyConversationPanel(
                            prompts: visibleSuggestionPrompts,
                            hasAPIKey: hasAPIKey,
                            configureAPIKey: openAPIKeySetup,
                            selectPrompt: { prompt in
                                draftText = prompt
                                isComposerFocused = true
                            }
                        )
                            .padding(.top, 80)
                    } else {
                        ForEach(selectedMessages) { message in
                            CampusAIMessageRow(
                                message: message,
                                actions: actionRecords(for: message),
                                isStreaming: isSending
                                    && selectedMessages.last?.id == message.id
                                    && message.roleRawValue == CampusAIMessageRole.assistant.rawValue,
                                executeAction: { action in
                                    Task {
                                        await executeActionRecord(action)
                                    }
                                },
                                cancelAction: cancelActionRecord,
                                regenerate: {
                                    regenerateResponse(for: message)
                                }
                            )
                                .transition(.opacity)
                                .id(message.id)
                        }
                    }

                    if isSending, selectedMessages.last?.roleRawValue == CampusAIMessageRole.user.rawValue {
                        CampusAITypingRow()
                            .id("campus-ai-typing")
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("campus-ai-bottom")
                }
                .leafyAdaptiveContentWidth(maxWidth: 820, horizontalPadding: AppSpacing.page)
                .padding(.top, AppSpacing.card)
                .padding(.bottom, AppSpacing.card)
                .animation(
                    accessibilityReduceMotion ? nil : .easeOut(duration: 0.18),
                    value: selectedMessages.map(\.id)
                )
            }
            .campusAIKeyboardDismissBehavior()
            .onChange(of: selectedMessages.map(\.id)) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: selectedMessages.map(\.text)) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: selectedMessages.map(\.agentMetadataJSON)) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: isSending) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: selectedConversationID) { _, _ in
                scrollToBottom(proxy, animated: false)
            }
        }
    }

    private var canSend: Bool {
        hasAPIKey && !isSending && !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static let suggestionPrompts = [
        "明天有哪些课？",
        "最近考试怎么复习？",
        "还有哪些学业风险？",
        "这周哪些课要预习？",
        "今天适合复习什么？",
        "先复习哪几门课？",
        "公选课还差多少？",
        "本周哪天最忙？",
        "期末节奏怎么排？",
        "帮我找自习时间。"
    ]

    private static func randomSuggestionPrompts() -> [String] {
        Array(suggestionPrompts.shuffled().prefix(3))
    }

    private static let experimentalNoticeAcknowledgedKey = "campusAI.experimentalNoticeAcknowledged.v1"

    private func selectInitialConversationIfNeeded() {
        if let selectedConversationID,
           conversations.contains(where: { $0.id == selectedConversationID }) {
            return
        }
        selectedConversationID = conversations.first?.id
    }

    private func startNewConversation() {
        cancelStreaming()
        let conversation = CampusAIConversation()
        modelContext.insert(conversation)
        selectedConversationID = conversation.id
        visibleSuggestionPrompts = Self.randomSuggestionPrompts()
        persistModelContext(operation: "conversation.create")
        if hasAPIKey {
            isComposerFocused = true
        } else {
            openAPIKeySetup()
        }
    }

    private func presentExperimentalNoticeIfNeeded() {
        guard !experimentalNoticeAcknowledged else { return }
        activeAlert = .experimentalNotice
    }

    private func refreshConfiguredProviders() {
        configuredProviderIDs = CampusAIKeychainStore.configuredProviderIDs()
        userSettings = userSettings.normalizedForLocalRuntime
    }

    private func openAPIKeySetup() {
        isComposerFocused = false
        activeSheet = .apiKey
    }

    private func submitDraft() {
        guard !isSending,
              !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        chatSession.start { streamRunID in
            await sendCurrentDraft(streamRunID: streamRunID)
        }
    }

    private func cancelStreaming() {
        chatSession.cancel()
    }

    @MainActor
    private func sendCurrentDraft(streamRunID: UUID) async {
        let text = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, hasAPIKey else {
            if !hasAPIKey { openAPIKeySetup() }
            return
        }
        let requestSettings = userSettings.normalizedForLocalRuntime
        let requestOutputMode = outputMode
        let reusableUserMessage = pendingRegenerationUserMessageID.flatMap { messageID in
            messages.first(where: { $0.id == messageID && $0.roleRawValue == CampusAIMessageRole.user.rawValue })
        }
        pendingRegenerationUserMessageID = nil
        outputMode = .automatic

        let conversation = selectedConversation ?? {
            let newConversation = CampusAIConversation()
            modelContext.insert(newConversation)
            selectedConversationID = newConversation.id
            return newConversation
        }()

        let conversationKey = conversation.id.uuidString
        let context = CampusAIContextBuilder.build(modelContext: modelContext, settings: requestSettings.contextSettings)
        let userMessage = reusableUserMessage ?? CampusAIMessage(
            conversationID: conversationKey,
            roleRawValue: CampusAIMessageRole.user.rawValue,
            text: text
        )
        if reusableUserMessage == nil {
            modelContext.insert(userMessage)
        }
        conversation.updatedAt = Date()
        if conversation.title == "新的对话" {
            conversation.title = Self.conversationTitle(from: text)
        }
        draftText = ""
        guard persistModelContext(operation: "message.user.insert") else {
            return
        }

        let recentMessages = messages
            .filter { $0.conversationID == conversationKey && $0.createdAt <= userMessage.createdAt }
            .suffix(10)
            .compactMap(CampusAIChatMessage.init(message:))
        let assistantMessage = CampusAIMessage(
            conversationID: conversationKey,
            roleRawValue: CampusAIMessageRole.assistant.rawValue,
            text: ""
        )
        modelContext.insert(assistantMessage)
        guard persistModelContext(operation: "message.assistant.insert") else {
            modelContext.delete(assistantMessage)
            return
        }
        chatSession.markStreaming(conversationID: conversation.id, messageID: assistantMessage.id)

        defer {
            chatSession.finish(runID: streamRunID, messageID: assistantMessage.id)
            discardedStreamMessageIDs.remove(assistantMessage.id)
        }

        do {
            var streamedAnswer = ""
            var agentMetadata = CampusAIMessageAgentMetadata.empty
            var lastSaveAt = Date.distantPast
            for try await event in service.stream(
                message: text,
                context: context,
                recentMessages: Array(recentMessages),
                settings: requestSettings,
                outputMode: requestOutputMode
            ) {
                try Task.checkCancellation()
                switch event {
                case .delta(let delta):
                    streamedAnswer += delta
                    assistantMessage.text = streamedAnswer
                    conversation.updatedAt = Date()
                    if Date().timeIntervalSince(lastSaveAt) > 0.35 {
                        persistModelContext(operation: "message.stream.checkpoint", showsAlert: false)
                        lastSaveAt = Date()
                    }
                case .reasoningDelta:
                    break
                case .quota:
                    break
                case .agentStatus(let status):
                    chatSession.update(statusText: status)
                    agentMetadata.statusText = status
                    if status.contains("成品") {
                        agentMetadata.artifactState = .generating
                    }
                    persistAgentMetadata(agentMetadata, for: assistantMessage)
                case .agentStep(let step):
                    if !agentMetadata.agentTrace.contains(where: { $0.id == step.id }) {
                        agentMetadata.agentTrace.append(step)
                    }
                    persistAgentMetadata(agentMetadata, for: assistantMessage)
                case .agentTool(let tool):
                    agentMetadata.statusText = Self.agentToolStatusText(tool)
                    persistAgentMetadata(agentMetadata, for: assistantMessage)
                case .agentCitation(let citation):
                    if !agentMetadata.citations.contains(where: { $0.url == citation.url }) {
                        agentMetadata.citations.append(citation)
                    }
                    persistAgentMetadata(agentMetadata, for: assistantMessage)
                case .done(let response):
                    if streamedAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       let answer = response.answer.nonEmptyTrimmed {
                        streamedAnswer = answer
                        assistantMessage.text = answer
                    }
                    if let notice = Self.completionNotice(for: response.finishReason),
                       !assistantMessage.text.contains(notice) {
                        assistantMessage.text = [
                            assistantMessage.text.trimmingCharacters(in: .whitespacesAndNewlines),
                            "> \(notice)"
                        ].filter { !$0.isEmpty }.joined(separator: "\n\n")
                    }
                    if let suggestedTitle = response.suggestedTitle?.nonEmptyTrimmed {
                        conversation.title = Self.conversationTitle(from: suggestedTitle)
                    }
                    if let summary = response.summary?.nonEmptyTrimmed {
                        conversation.summary = summary
                    }
                    agentMetadata.statusText = nil
                    if !response.citations.isEmpty {
                        agentMetadata.citations = response.citations
                    }
                    if !response.agentTrace.isEmpty {
                        agentMetadata.agentTrace = response.agentTrace
                    }
                    if !response.deliverables.isEmpty {
                        agentMetadata.deliverables = response.deliverables
                    }
                    agentMetadata.artifactState = response.artifactState
                    agentMetadata.artifactErrorMessage = response.artifactErrorMessage
                    persistAgentMetadata(agentMetadata, for: assistantMessage)
                    if response.artifactState == .ready {
                        artifactCompletionSignal += 1
                    }
                    persistActionRecords(
                        response.actions,
                        conversationID: conversationKey,
                        messageID: assistantMessage.id.uuidString
                    )
                case .error(let message):
                    throw CampusAIServiceError.providerRejected(message)
                }
            }
            if assistantMessage.text.nonEmptyTrimmed == nil {
                assistantMessage.text = "我暂时没有整理出有效回答。"
            }
            conversation.contextDigest = contextDigest(context)
            conversation.updatedAt = Date()
            persistModelContext(operation: "message.complete")
        } catch is CancellationError {
            guard !discardedStreamMessageIDs.contains(assistantMessage.id) else { return }
            if assistantMessage.text.nonEmptyTrimmed == nil {
                assistantMessage.text = "已停止生成。"
            } else {
                assistantMessage.text += "\n\n> 已停止生成。"
            }
            conversation.updatedAt = Date()
            persistModelContext(operation: "message.cancel")
        } catch {
            if assistantMessage.text.nonEmptyTrimmed != nil {
                assistantMessage.text = [
                    assistantMessage.text.trimmingCharacters(in: .whitespacesAndNewlines),
                    "> 生成中断：\(error.localizedDescription)"
                ].filter { !$0.isEmpty }.joined(separator: "\n\n")
            } else {
                assistantMessage.text = "Leafy 暂时不可用：\(error.localizedDescription)"
            }
            conversation.updatedAt = Date()
            persistModelContext(operation: "message.failure")
            operationAlert = .failure(error.localizedDescription)
        }
    }

    private func regenerateResponse(for message: CampusAIMessage) {
        guard !isSending,
              message.roleRawValue == CampusAIMessageRole.assistant.rawValue,
              let index = selectedMessages.firstIndex(where: { $0.id == message.id }),
              let userMessage = selectedMessages[..<index].last(where: {
                  $0.roleRawValue == CampusAIMessageRole.user.rawValue
              })
        else { return }

        let metadata = message.agentMetadata
        outputMode = metadata.artifactState == .none && metadata.deliverables.isEmpty ? .automatic : .artifact
        for action in actionRecords(for: message) {
            modelContext.delete(action)
        }
        do {
            try CampusAIDeliverableFileBuilder.removeArtifacts(for: message.id)
        } catch {
            CampusAIDiagnostics.failure(error, stage: "artifact.cleanup", requestID: message.id)
        }
        modelContext.delete(message)
        guard persistModelContext(operation: "message.regenerate.prepare") else { return }

        pendingRegenerationUserMessageID = userMessage.id
        draftText = userMessage.text
        submitDraft()
    }

    private func deleteConversation(_ conversation: CampusAIConversation) {
        let key = conversation.id.uuidString
        if chatSession.activeConversationID == conversation.id {
            if let activeStreamMessageID = chatSession.activeMessageID {
                discardedStreamMessageIDs.insert(activeStreamMessageID)
            }
            cancelStreaming()
        }
        for action in actionRecords where action.conversationID == key {
            modelContext.delete(action)
        }
        for message in messages where message.conversationID == key {
            discardedStreamMessageIDs.insert(message.id)
            do {
                try CampusAIDeliverableFileBuilder.removeArtifacts(for: message.id)
            } catch {
                CampusAIDiagnostics.failure(error, stage: "artifact.cleanup", requestID: message.id)
            }
            modelContext.delete(message)
        }
        modelContext.delete(conversation)
        if selectedConversationID == conversation.id {
            selectedConversationID = conversations.first(where: { $0.id != conversation.id })?.id
        }
        persistModelContext(operation: "conversation.delete")
    }

    private func persistActionRecords(
        _ drafts: [CampusAIActionDraft],
        conversationID: String,
        messageID: String
    ) {
        guard !drafts.isEmpty else { return }
        guard !actionRecords.contains(where: { $0.conversationID == conversationID && $0.messageID == messageID }) else {
            return
        }
        let encoder = JSONEncoder()
        for draft in CampusAIActionValidation.validated(drafts).prefix(3) {
            do {
                let payloadData = try encoder.encode(draft.payload)
                guard let payloadJSON = String(data: payloadData, encoding: .utf8) else {
                    throw CampusAIServiceError.invalidProviderResponse
                }
                modelContext.insert(
                    CampusAIActionRecord(
                        conversationID: conversationID,
                        messageID: messageID,
                        kindRawValue: draft.kind.rawValue,
                        title: draft.title,
                        detail: draft.detail,
                        payloadJSON: payloadJSON,
                        statusRawValue: CampusAIActionStatus.pending.rawValue
                    )
                )
            } catch {
                CampusAIDiagnostics.persistenceFailure(error, operation: "action.encode")
                operationAlert = .failure("动作保存失败，请重试生成。")
                return
            }
        }
    }

    private func persistAgentMetadata(
        _ metadata: CampusAIMessageAgentMetadata,
        for message: CampusAIMessage
    ) {
        do {
            let data = try JSONEncoder().encode(metadata)
            guard let json = String(data: data, encoding: .utf8) else {
                throw CampusAIServiceError.invalidProviderResponse
            }
            message.agentMetadataJSON = json
            persistModelContext(operation: "message.metadata", showsAlert: false)
        } catch {
            CampusAIDiagnostics.persistenceFailure(error, operation: "message.metadata.encode")
            operationAlert = .failure("成品状态保存失败，请重试。")
        }
    }

    @MainActor
    private func cancelActionRecord(_ record: CampusAIActionRecord) {
        guard record.status == .pending else { return }
        record.statusRawValue = CampusAIActionStatus.cancelled.rawValue
        record.updatedAt = Date()
        persistModelContext(operation: "action.cancel")
    }

    @MainActor
    private func executeActionRecord(_ record: CampusAIActionRecord) async {
        guard record.status == .pending else { return }
        guard let draft = record.actionDraft,
              let validated = CampusAIActionValidation.validate(draft)
        else {
            markAction(record, status: .failed)
            operationAlert = .failure("动作内容无效，无法执行。")
            return
        }

        do {
            switch validated.kind {
            case .openAcademicRoute:
                try executeOpenAcademicRoute(validated)
                markAction(record, status: .completed)
            case .createCountdown:
                activeSheet = .actionEditor(CampusAIActionEditorPresentation(record: record, draft: validated))
            case .createTimetableReminder:
                activeSheet = .actionEditor(CampusAIActionEditorPresentation(record: record, draft: validated))
            }
        } catch {
            markAction(record, status: .failed)
            operationAlert = .failure(error.localizedDescription)
        }
    }

    @MainActor
    private func confirmActionEditor(
        _ presentation: CampusAIActionEditorPresentation,
        draft: CampusAIActionDraft
    ) async {
        guard presentation.record.status == .pending else {
            activeSheet = nil
            return
        }
        guard let validated = CampusAIActionValidation.validate(draft) else {
            operationAlert = .failure("动作内容无效，无法执行。")
            return
        }

        do {
            switch validated.kind {
            case .openAcademicRoute:
                try executeOpenAcademicRoute(validated)
            case .createCountdown:
                try executeCreateCountdown(validated)
            case .createTimetableReminder:
                try await executeCreateTimetableReminder(validated)
            }
            markAction(presentation.record, status: .completed)
            activeSheet = nil
        } catch {
            markAction(presentation.record, status: .failed)
            activeSheet = nil
            operationAlert = .failure(error.localizedDescription)
        }
    }

    private func handleSheetDismissal() {
        refreshConfiguredProviders()
        if hasAPIKey {
            isComposerFocused = true
        }
    }

    private func executeOpenAcademicRoute(_ draft: CampusAIActionDraft) throws {
        guard let routeID = CampusAIActionValidation.routeID(for: draft) else {
            throw CampusAIActionExecutionError.invalidPayload
        }
        appNavigation.openAcademicDetailRoute(routeID.detailRoute)
        operationAlert = .success("已打开\(routeID.title)。")
    }

    private func executeCreateCountdown(_ draft: CampusAIActionDraft) throws {
        guard let title = draft.payload.countdownTitle?.nonEmptyTrimmed,
              let targetDate = CampusAIActionValidation.countdownDate(for: draft)
        else {
            throw CampusAIActionExecutionError.invalidPayload
        }
        var events = CustomScheduleStore.load()
        events.append(CustomScheduleEvent(title: title, startsAt: targetDate))
        CustomScheduleStore.save(events)
        operationAlert = .success("已创建重要日期：\(title)。")
    }

    @MainActor
    private func executeCreateTimetableReminder(_ draft: CampusAIActionDraft) async throws {
        guard let week = draft.payload.week,
              let dayOfWeek = draft.payload.dayOfWeek,
              let period = draft.payload.period,
              let title = draft.payload.title?.nonEmptyTrimmed
        else {
            throw CampusAIActionExecutionError.invalidPayload
        }
        let endPeriod = draft.payload.endPeriod.flatMap { $0 >= period ? $0 : nil }
        let cellKey = TimetableCellReminder.cellKey(week: week, dayOfWeek: dayOfWeek, period: period)
        let descriptor = FetchDescriptor<TimetableCellReminder>(
            predicate: #Predicate { reminder in
                reminder.cellKey == cellKey
            }
        )
        let existingReminders = try modelContext.fetch(descriptor)
        let reminder: TimetableCellReminder
        if let existing = existingReminders.first {
            TimetableNotificationManager.cancelReminder(for: existing)
            existing.week = week
            existing.dayOfWeek = dayOfWeek
            existing.period = period
            existing.endPeriod = endPeriod
            existing.cellKey = cellKey
            existing.title = title
            existing.location = TimetableCellReminder.normalizedOptionalText(draft.payload.location ?? "")
            existing.note = TimetableCellReminder.normalizedOptionalText(draft.payload.note ?? "")
            existing.startsAt = TimetablePeriodSchedule.startDate(week: week, dayOfWeek: dayOfWeek, period: period)
            existing.endsAt = TimetablePeriodSchedule.endDate(week: week, dayOfWeek: dayOfWeek, period: endPeriod ?? period)
            existing.minutesBefore = max(0, draft.payload.minutesBefore ?? 0)
            existing.updatedAt = Date()
            reminder = existing
        } else {
            let newReminder = TimetableCellReminder(
                week: week,
                dayOfWeek: dayOfWeek,
                period: period,
                endPeriod: endPeriod,
                title: title,
                location: draft.payload.location ?? "",
                note: draft.payload.note ?? "",
                startsAt: TimetablePeriodSchedule.startDate(week: week, dayOfWeek: dayOfWeek, period: period),
                endsAt: TimetablePeriodSchedule.endDate(week: week, dayOfWeek: dayOfWeek, period: endPeriod ?? period),
                minutesBefore: max(0, draft.payload.minutesBefore ?? 0)
            )
            modelContext.insert(newReminder)
            reminder = newReminder
        }

        for duplicate in existingReminders.dropFirst() {
            TimetableNotificationManager.cancelReminder(for: duplicate)
            modelContext.delete(duplicate)
        }

        try modelContext.save()
        do {
            let scheduled = try await TimetableNotificationManager.applyReminder(for: reminder)
            operationAlert = .success(
                scheduled
                    ? "已创建课表提醒：\(title)。"
                    : "已创建课表提醒：\(title)。"
            )
        } catch {
            operationAlert = .success("已创建课表提醒：\(title)。通知注册失败，可稍后在系统设置中检查通知权限。")
        }
    }

    private func markAction(_ record: CampusAIActionRecord, status: CampusAIActionStatus) {
        record.statusRawValue = status.rawValue
        record.updatedAt = Date()
        persistModelContext(operation: "action.update")
    }

    private func clearAllHistory() {
        if chatSession.isSending || chatSession.activeMessageID != nil {
            if let activeStreamMessageID = chatSession.activeMessageID {
                discardedStreamMessageIDs.insert(activeStreamMessageID)
            }
            cancelStreaming()
        }
        do {
            try CampusAIDeliverableFileBuilder.removeAllArtifacts()
        } catch {
            CampusAIDiagnostics.failure(error, stage: "artifact.cleanup.all")
            operationAlert = .failure("部分成品缓存清理失败，聊天记录仍会继续清除。")
        }
        for action in actionRecords {
            modelContext.delete(action)
        }
        for message in messages {
            discardedStreamMessageIDs.insert(message.id)
            modelContext.delete(message)
        }
        for conversation in conversations {
            modelContext.delete(conversation)
        }
        selectedConversationID = nil
        persistModelContext(operation: "history.clear")
    }

    private func pruneOrphanedDeliverableArtifacts() {
        let retainedMessageIDs = Set(messages.map(\.id))
        Task.detached {
            do {
                try CampusAIDeliverableFileBuilder.pruneArtifacts(keeping: retainedMessageIDs)
            } catch {
                CampusAIDiagnostics.failure(error, stage: "artifact.prune")
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool = true) {
        let action = {
            proxy.scrollTo("campus-ai-bottom", anchor: .bottom)
        }
        if animated && !accessibilityReduceMotion {
            withAnimation(.easeOut(duration: 0.22), action)
        } else {
            action()
        }
    }

    @discardableResult
    private func persistModelContext(operation: String, showsAlert: Bool = true) -> Bool {
        do {
            try modelContext.save()
            return true
        } catch {
            CampusAIDiagnostics.persistenceFailure(error, operation: operation)
            if showsAlert {
                operationAlert = .failure("本机保存失败，请重试。")
            }
            return false
        }
    }

    private func contextDigest(_ context: CampusAIContextPayload) -> String {
        [
            "week:\(context.currentWeek)",
            "courses:\(context.timetable.allCourses.count)",
            "grades:\(context.grades.courseCount)",
            "exams:\(context.exams.count)",
            "learning:\(context.learningWorkspace.projects.count + context.learningWorkspace.tasks.count)",
            "medical:\(context.medicalLedger.entries.count)"
        ].joined(separator: "|")
    }

    private static func conversationTitle(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 10 else { return trimmed.isEmpty ? "新的对话" : trimmed }
        return String(trimmed.prefix(9)) + "…"
    }

    private static func historyTitle(from text: String) -> String {
        conversationTitle(from: text)
    }

    private static func completionNotice(for finishReason: String?) -> String? {
        switch finishReason?.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "length":
            return "生成到达长度上限，已保留当前内容。"
        case "content_filter":
            return "部分内容触发了供应商安全策略，已保留可显示内容。"
        case "insufficient_system_resource":
            return "供应商资源暂时不足，已保留当前内容。"
        default:
            return nil
        }
    }

    private static func agentToolStatusText(_ tool: CampusAIAgentToolEvent) -> String {
        let title = CampusAIToolRegistry.descriptor(forToolName: tool.name)?.title
            ?? managedToolTitle(for: tool.name)

        switch tool.status {
        case "running":
            return "\(title)进行中"
        case "completed":
            if let resultCount = tool.resultCount, resultCount > 0 {
                return "\(title)完成，找到 \(resultCount) 条结果"
            }
            return "\(title)完成"
        case "failed":
            return "\(title)失败，继续生成回答"
        case "skipped":
            return "\(title)已跳过"
        default:
            return title
        }
    }

    private static func managedToolTitle(for name: String) -> String {
        switch name {
        case "completion.plan":
            return "整理成品与动作"
        case "official.document.search":
            return "官方资料检索"
        case "delegate.subtask":
            return "子任务"
        default:
            return name.nonEmptyTrimmed ?? "工具"
        }
    }
}

private enum CampusAISheetDestination: Identifiable {
    case history
    case settings
    case apiKey
    case actionEditor(CampusAIActionEditorPresentation)

    var id: String {
        switch self {
        case .history:
            return "history"
        case .settings:
            return "settings"
        case .apiKey:
            return "apiKey"
        case .actionEditor(let presentation):
            return "actionEditor-\(presentation.id.uuidString)"
        }
    }
}

private enum CampusAIAlert: Identifiable {
    case experimentalNotice

    var id: String {
        switch self {
        case .experimentalNotice:
            return "experimentalNotice"
        }
    }
}

private enum CampusAIActionExecutionError: LocalizedError {
    case invalidPayload

    var errorDescription: String? {
        switch self {
        case .invalidPayload:
            return "动作内容无效，无法执行。"
        }
    }
}

private extension CampusAIChatMessage {
    init?(message: CampusAIMessage) {
        guard let role = CampusAIMessageRole(rawValue: message.roleRawValue),
              let text = message.text.nonEmptyTrimmed
        else {
            return nil
        }
        self.init(role: role, text: text)
    }
}

private extension View {
    @ViewBuilder
    func campusAIKeyboardDismissBehavior() -> some View {
        #if os(iOS)
        scrollDismissesKeyboard(.interactively)
        #else
        self
        #endif
    }

}

private extension String {
    var nonEmptyTrimmed: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
