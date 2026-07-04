import SwiftData
import SwiftUI
import WebKit

struct CampusAIAssistantView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appNavigation: AppNavigationCoordinator
    @Environment(\.leafyControlScale) private var leafyControlScale
    @Environment(\.leafyThemeColorPreference) private var themeColorPreference
    @AppStorage(Self.experimentalNoticeAcknowledgedKey) private var experimentalNoticeAcknowledged = false
    @FocusState private var isComposerFocused: Bool
    @Query(sort: \CampusAIConversation.updatedAt, order: .reverse) private var conversations: [CampusAIConversation]
    @Query(sort: \CampusAIMessage.createdAt, order: .forward) private var messages: [CampusAIMessage]
    @Query(sort: \CampusAIActionRecord.createdAt, order: .forward) private var actionRecords: [CampusAIActionRecord]

    var service = CampusAIService()

    @State private var selectedConversationID: UUID?
    @State private var draftText = ""
    @State private var isHistoryPresented = false
    @State private var isSettingsPresented = false
    @State private var isSending = false
    @State private var activeStreamTask: Task<Void, Never>?
    @State private var activeStreamRunID: UUID?
    @State private var activeStreamConversationID: UUID?
    @State private var activeStreamMessageID: UUID?
    @State private var discardedStreamMessageIDs: Set<UUID> = []
    @State private var userSettings = CampusAISettingsStore.load()
    @State private var isClearHistoryConfirmationPresented = false
    @State private var conversationPendingDeletion: CampusAIConversation?
    @State private var operationAlert: LeafyOperationAlert?
    @State private var isExperimentalNoticePresented = false
    @State private var visibleSuggestionPrompts = Self.randomSuggestionPrompts()
    @State private var configuredProviderIDs: Set<CampusAIProviderID> = []
    @State private var quotaSnapshot: CampusAIQuotaSnapshot?
    @State private var actionEditor: CampusAIActionEditorPresentation?

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

    private var conversationDeletionBinding: Binding<Bool> {
        Binding(
            get: { conversationPendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    conversationPendingDeletion = nil
                }
            }
        )
    }

    var body: some View {
        ZStack(alignment: .leading) {
            chatSurface

            if isHistoryPresented {
                historyOverlay
            }

            clearHistoryAlertHost
        }
        .background(AppTheme.cardElevated)
        .onAppear {
            selectInitialConversationIfNeeded()
            presentExperimentalNoticeIfNeeded()
            refreshConfiguredProviders()
            refreshManagedQuotaIfNeeded()
            pruneOrphanedDeliverableArtifacts()
        }
        .onChange(of: conversations.map(\.id)) { _, _ in
            selectInitialConversationIfNeeded()
        }
        .sheet(isPresented: $isSettingsPresented, onDismiss: {
            refreshConfiguredProviders()
            refreshManagedQuotaIfNeeded()
        }) {
            CampusAISettingsView(settings: $userSettings)
        }
        .sheet(item: $actionEditor) { presentation in
            CampusAIActionEditorSheet(presentation: presentation) { draft in
                Task {
                    await confirmActionEditor(presentation, draft: draft)
                }
            }
        }
        .alert("Leafy AI 仍在实验阶段", isPresented: $isExperimentalNoticePresented) {
            Button("我知道了") {
                experimentalNoticeAcknowledged = true
            }
        } message: {
            Text("AI 问答功能还在测试中，回复可能会有错误、遗漏或过时内容。涉及课程、考试、成绩、医疗、手续等事项，请以学校官方系统和最新通知为准。")
        }
        .confirmationDialog(
            "删除这个对话？",
            isPresented: conversationDeletionBinding,
            titleVisibility: .visible
        ) {
            Button("删除对话", role: .destructive) {
                if let conversationPendingDeletion {
                    deleteConversation(conversationPendingDeletion)
                }
                conversationPendingDeletion = nil
            }
            Button("取消", role: .cancel) {
                conversationPendingDeletion = nil
            }
        } message: {
            Text("这只会删除当前设备上的这条 Leafy 聊天记录。")
        }
        .leafyOperationAlert($operationAlert)
        .animation(.spring(response: 0.28, dampingFraction: 0.9), value: isHistoryPresented)
    }

    private var chatSurface: some View {
        VStack(spacing: 0) {
            topBar
            Divider().opacity(0.24)
            conversationScroll
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            composerBar
        }
    }

    private var clearHistoryAlertHost: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .alert("清空全部对话？", isPresented: $isClearHistoryConfirmationPresented) {
                Button("取消", role: .cancel) {}
                Button("清空全部历史", role: .destructive) {
                    clearAllHistory()
                }
            } message: {
                Text("这只会删除当前设备上的 Leafy 聊天记录。")
            }
    }

    private var topBar: some View {
        LeafyGlassGroup(spacing: AppSpacing.micro) {
            HStack(spacing: AppSpacing.compact) {
                Button {
                    isHistoryPresented = true
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("打开历史记录")
                .leafyGlassSurface(in: Circle(), isInteractive: true)

                Button {
                    isSettingsPresented = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("打开 Leafy 设置")
                .leafyGlassSurface(in: Circle(), isInteractive: true)

                serviceModeSelector

                Spacer(minLength: AppSpacing.micro)

                Button {
                    startNewConversation()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("新建对话")
                .leafyGlassSurface(in: Circle(), isInteractive: true)
            }
        }
        .padding(.horizontal, AppSpacing.page)
        .padding(.top, AppSpacing.micro)
        .padding(.bottom, AppSpacing.micro)
        .background(AppTheme.cardElevated)
    }

    private var serviceModeSelector: some View {
        Menu {
            Button {
                selectServiceMode(.leafyManaged)
            } label: {
                Label(
                    CampusAIServiceMode.leafyManaged.title,
                    systemImage: userSettings.serviceMode == .leafyManaged ? "checkmark" : "sparkles"
                )
            }

            Button {
                selectServiceMode(.ownAPIKey)
            } label: {
                Label(
                    CampusAIServiceMode.ownAPIKey.title,
                    systemImage: userSettings.serviceMode == .ownAPIKey ? "checkmark" : "key.fill"
                )
            }
            .disabled(!configuredProviderIDs.contains(userSettings.selectedProviderID))
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(userSettings.serviceMode.shortTitle)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(AppTheme.tertiaryText)
                }

                if userSettings.serviceMode == .leafyManaged, let quotaSnapshot {
                    Text("剩余 \(quotaSnapshot.displayText)")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(AppTheme.primaryText)
            .padding(.horizontal, 12)
            .frame(maxWidth: 132, alignment: .leading)
            .frame(height: 38)
            .leafyGlassSurface(in: Capsule(), isInteractive: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("当前 AI 服务 \(userSettings.serviceMode.title)")
    }

    private var conversationScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: AppSpacing.card) {
                    if selectedMessages.isEmpty {
                        emptyConversationView
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
                                cancelAction: cancelActionRecord
                            )
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
            }
            .campusAIKeyboardDismissBehavior()
            .onChange(of: selectedMessages.map(\.id)) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: selectedMessages.map(\.text)) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: selectedMessages.map(\.reasoningText)) { _, _ in
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

    private var emptyConversationView: some View {
        VStack(spacing: AppSpacing.card) {
            VStack(spacing: AppSpacing.compact) {
                Image(systemName: "sparkles")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(AppTheme.accent(for: themeColorPreference))
                    .frame(width: 58, height: 58)
                    .background(
                        AppTheme.accent(for: themeColorPreference).opacity(0.12),
                        in: Circle()
                    )

                Text("Leafy")
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText)

                Text("问问课表、考试、成绩或培养方案。Leafy 会尽量只基于当前设备上的学业数据回答。")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 360)
            }

            VStack(spacing: AppSpacing.micro) {
                ForEach(visibleSuggestionPrompts, id: \.self) { prompt in
                    CampusAISuggestionRow(title: prompt) {
                        draftText = prompt
                        isComposerFocused = true
                    }
                }
            }
            .frame(maxWidth: 520)
        }
        .frame(maxWidth: .infinity)
    }

    private var composerBar: some View {
        LeafyGlassGroup(spacing: AppSpacing.micro) {
            HStack(alignment: .bottom, spacing: 10) {
                webSearchToggleButton
                    .padding(.leading, 8)
                    .padding(.bottom, 7)

                TextField("功能仍在测试，不作功能保证。", text: $draftText, axis: .vertical)
                    .focused($isComposerFocused)
                    .lineLimit(1...5)
                    .textFieldStyle(.plain)
                    .submitLabel(.send)
                    .onSubmit {
                        submitDraft()
                    }
                    .padding(.leading, 2)
                    .padding(.trailing, 8)
                    .padding(.vertical, 14)

                Button {
                    if isSending {
                        cancelStreaming()
                    } else {
                        submitDraft()
                    }
                } label: {
                    Image(systemName: isSending ? "stop.fill" : "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle((canSend || isSending) ? AppTheme.textOnAccent(for: themeColorPreference) : AppTheme.tertiaryText)
                        .frame(width: 34, height: 34)
                        .background(
                            (canSend || isSending) ? AppTheme.accent(for: themeColorPreference) : AppTheme.accent(for: themeColorPreference).opacity(0.16),
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canSend && !isSending)
                .padding(.trailing, 8)
                .padding(.bottom, 7)
                .accessibilityLabel(isSending ? "停止生成" : "发送给 Leafy")
            }
            .leafyGlassSurface(
                in: RoundedRectangle(cornerRadius: 24, style: .continuous),
                fallbackFill: AppTheme.cardElevated.opacity(0.92)
            )
        }
        .padding(.horizontal, AppSpacing.page)
        .padding(.top, AppSpacing.micro)
        .padding(.bottom, AppSpacing.compact)
    }

    private var webSearchToggleButton: some View {
        Button {
            toggleWebSearchForComposer()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: isWebSearchActive ? "globe.asia.australia.fill" : "globe")
                    .font(.system(size: 15, weight: .semibold))

                if isWebSearchActive {
                    Text("联网")
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(isWebSearchActive ? AppTheme.textOnAccent(for: themeColorPreference) : AppTheme.secondaryText)
            .frame(height: 34)
            .padding(.horizontal, isWebSearchActive ? 10 : 0)
            .frame(minWidth: 34)
            .background(
                isWebSearchActive
                    ? AppTheme.accent(for: themeColorPreference)
                    : AppTheme.softFill.opacity(userSettings.serviceMode == .leafyManaged ? 0.95 : 0.48),
                in: Capsule()
            )
            .opacity(userSettings.serviceMode == .leafyManaged ? 1 : 0.58)
        }
        .buttonStyle(.plain)
        .disabled(userSettings.serviceMode != .leafyManaged || isSending)
        .accessibilityLabel(isWebSearchActive ? "关闭联网搜索" : "开启联网搜索")
        .accessibilityValue(isWebSearchActive ? "已开启" : "已关闭")
    }

    private var isWebSearchActive: Bool {
        userSettings.serviceMode == .leafyManaged && userSettings.webSearchEnabled
    }

    private var historyOverlay: some View {
        GeometryReader { proxy in
            let horizontalInset = AppSpacing.compact
            let panelWidth = min(proxy.size.width * 0.5, proxy.size.width - horizontalInset * 2)
            let topInset = proxy.safeAreaInsets.top + AppSpacing.compact
            let bottomInset = proxy.safeAreaInsets.bottom + RootFloatingTabBar.reservedHeight(controlScale: leafyControlScale) + AppSpacing.micro
            let panelHeight = max(280, proxy.size.height - topInset - bottomInset)

            ZStack(alignment: .topLeading) {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture {
                        isHistoryPresented = false
                    }

                Color.clear
                    .frame(width: panelWidth, height: panelHeight)
                    .contentShape(Rectangle())
                    .onTapGesture {}
                    .padding(.leading, horizontalInset)
                    .padding(.top, topInset)
                    .zIndex(1)

                historyPanel
                    .frame(width: panelWidth, height: panelHeight)
                    .padding(.leading, horizontalInset)
                    .padding(.top, topInset)
                    .zIndex(2)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
    }

    private var historyPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: AppSpacing.micro) {
                Text("历史记录")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(1)

                Spacer(minLength: AppSpacing.micro)

                Button(role: .destructive) {
                    isComposerFocused = false
                    isClearHistoryConfirmationPresented = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(conversations.isEmpty ? AppTheme.tertiaryText : AppTheme.danger)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(conversations.isEmpty)
                .accessibilityLabel("清空历史")
                .leafyGlassSurface(in: Circle(), isInteractive: true)
                .contentShape(Circle())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppSpacing.page)
            .padding(.top, AppSpacing.page)
            .padding(.bottom, AppSpacing.compact)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if conversations.isEmpty {
                        ContentUnavailableView("暂无历史", systemImage: "clock")
                            .padding(.top, AppSpacing.card)
                    } else {
                        ForEach(conversations) { conversation in
                            historyRow(conversation)
                        }
                    }
                }
                .padding(.horizontal, AppSpacing.micro)
                .padding(.bottom, AppSpacing.card)
            }

        }
        .leafyGlassSurface(
            in: RoundedRectangle(cornerRadius: 28, style: .continuous),
            fallbackFill: AppTheme.cardElevated.opacity(0.92)
        )
        .shadow(color: .black.opacity(0.16), radius: 24, x: 8, y: 10)
    }

    private var canSend: Bool {
        !isSending && !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

    private func historyRow(_ conversation: CampusAIConversation) -> some View {
        Button {
            selectedConversationID = conversation.id
            isHistoryPresented = false
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(Self.historyTitle(from: conversation.title))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(1)

                Text(conversation.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(AppTheme.tertiaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                selectedConversation?.id == conversation.id
                    ? AppTheme.accent(for: themeColorPreference).opacity(0.12)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                conversationPendingDeletion = conversation
            } label: {
                Label("删除对话", systemImage: "trash")
            }
        }
    }

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
        try? modelContext.save()
        isComposerFocused = true
    }

    private func presentExperimentalNoticeIfNeeded() {
        guard !experimentalNoticeAcknowledged else { return }
        isExperimentalNoticePresented = true
    }

    private func selectServiceMode(_ mode: CampusAIServiceMode) {
        if mode == .ownAPIKey {
            guard configuredProviderIDs.contains(userSettings.selectedProviderID) else {
                operationAlert = .failure("请先在 Leafy 设置中填写 DeepSeek API Key。")
                return
            }
        }
        userSettings.serviceMode = mode
        CampusAISettingsStore.save(userSettings)
        refreshManagedQuotaIfNeeded()
    }

    private func toggleWebSearchForComposer() {
        guard userSettings.serviceMode == .leafyManaged, !isSending else { return }
        userSettings.webSearchEnabled.toggle()
        CampusAISettingsStore.save(userSettings)
    }

    private func refreshConfiguredProviders() {
        configuredProviderIDs = CampusAIKeychainStore.configuredProviderIDs()
        if userSettings.serviceMode == .ownAPIKey,
           !configuredProviderIDs.contains(userSettings.selectedProviderID) {
            userSettings.serviceMode = .leafyManaged
            CampusAISettingsStore.save(userSettings)
        }
    }

    private func refreshManagedQuotaIfNeeded() {
        guard userSettings.serviceMode == .leafyManaged else { return }
        Task {
            do {
                quotaSnapshot = try await CampusAIManagedEntitlementClient.sync()
            } catch {
                quotaSnapshot = nil
            }
        }
    }

    private func submitDraft() {
        guard activeStreamTask == nil,
              !isSending,
              !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        let streamRunID = UUID()
        activeStreamRunID = streamRunID
        activeStreamTask = Task {
            await sendCurrentDraft(streamRunID: streamRunID)
        }
    }

    private func cancelStreaming() {
        activeStreamTask?.cancel()
        activeStreamTask = nil
        activeStreamRunID = nil
        isSending = false
    }

    @MainActor
    private func sendCurrentDraft(streamRunID: UUID) async {
        let text = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        let requestSettings = userSettings

        let conversation = selectedConversation ?? {
            let newConversation = CampusAIConversation()
            modelContext.insert(newConversation)
            selectedConversationID = newConversation.id
            return newConversation
        }()

        let conversationKey = conversation.id.uuidString
        let context = CampusAIContextBuilder.build(modelContext: modelContext, settings: requestSettings.contextSettings)
        let userMessage = CampusAIMessage(
            conversationID: conversationKey,
            roleRawValue: CampusAIMessageRole.user.rawValue,
            text: text
        )
        modelContext.insert(userMessage)
        conversation.updatedAt = Date()
        if conversation.title == "新的对话" {
            conversation.title = Self.conversationTitle(from: text)
        }
        draftText = ""
        isSending = true
        try? modelContext.save()

        let recentMessages = (selectedMessages + [userMessage])
            .suffix(10)
            .compactMap(CampusAIChatMessage.init(message:))
        let assistantMessage = CampusAIMessage(
            conversationID: conversationKey,
            roleRawValue: CampusAIMessageRole.assistant.rawValue,
            text: ""
        )
        modelContext.insert(assistantMessage)
        try? modelContext.save()
        activeStreamConversationID = conversation.id
        activeStreamMessageID = assistantMessage.id

        defer {
            if activeStreamRunID == streamRunID {
                isSending = false
                activeStreamTask = nil
                activeStreamRunID = nil
            }
            if activeStreamMessageID == assistantMessage.id {
                activeStreamConversationID = nil
                activeStreamMessageID = nil
            }
            discardedStreamMessageIDs.remove(assistantMessage.id)
        }

        do {
            var streamedAnswer = ""
            var streamedReasoning = ""
            var agentMetadata = CampusAIMessageAgentMetadata.empty
            var lastSaveAt = Date.distantPast
            for try await event in service.stream(
                message: text,
                context: context,
                recentMessages: Array(recentMessages),
                settings: requestSettings
            ) {
                try Task.checkCancellation()
                switch event {
                case .delta(let delta):
                    streamedAnswer += delta
                    assistantMessage.text = streamedAnswer
                    conversation.updatedAt = Date()
                    if Date().timeIntervalSince(lastSaveAt) > 0.35 {
                        try? modelContext.save()
                        lastSaveAt = Date()
                    }
                case .reasoningDelta(let delta):
                    streamedReasoning += delta
                    assistantMessage.reasoningText = streamedReasoning
                    conversation.updatedAt = Date()
                    if Date().timeIntervalSince(lastSaveAt) > 0.35 {
                        try? modelContext.save()
                        lastSaveAt = Date()
                    }
                case .quota(let quota):
                    quotaSnapshot = quota
                case .agentStatus(let status):
                    agentMetadata.statusText = status
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
                    if streamedReasoning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       let reasoning = response.reasoning.nonEmptyTrimmed {
                        streamedReasoning = reasoning
                        assistantMessage.reasoningText = reasoning
                    }
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
                    persistAgentMetadata(agentMetadata, for: assistantMessage)
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
            try? modelContext.save()
        } catch is CancellationError {
            guard !discardedStreamMessageIDs.contains(assistantMessage.id) else { return }
            if assistantMessage.text.nonEmptyTrimmed == nil {
                assistantMessage.text = "已停止生成。"
            } else {
                assistantMessage.text += "\n\n> 已停止生成。"
            }
            conversation.updatedAt = Date()
            try? modelContext.save()
        } catch {
            if assistantMessage.text.nonEmptyTrimmed != nil || assistantMessage.reasoningText.nonEmptyTrimmed != nil {
                assistantMessage.text = [
                    assistantMessage.text.trimmingCharacters(in: .whitespacesAndNewlines),
                    "> 生成中断：\(error.localizedDescription)"
                ].filter { !$0.isEmpty }.joined(separator: "\n\n")
            } else {
                assistantMessage.text = "Leafy 暂时不可用：\(error.localizedDescription)"
            }
            conversation.updatedAt = Date()
            try? modelContext.save()
            operationAlert = .failure(error.localizedDescription)
        }
    }

    private func deleteConversation(_ conversation: CampusAIConversation) {
        let key = conversation.id.uuidString
        if activeStreamConversationID == conversation.id {
            if let activeStreamMessageID {
                discardedStreamMessageIDs.insert(activeStreamMessageID)
            }
            cancelStreaming()
        }
        for action in actionRecords where action.conversationID == key {
            modelContext.delete(action)
        }
        for message in messages where message.conversationID == key {
            discardedStreamMessageIDs.insert(message.id)
            try? CampusAIDeliverableFileBuilder.removeArtifacts(for: message.id)
            modelContext.delete(message)
        }
        modelContext.delete(conversation)
        if selectedConversationID == conversation.id {
            selectedConversationID = conversations.first(where: { $0.id != conversation.id })?.id
        }
        try? modelContext.save()
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
            guard let payloadData = try? encoder.encode(draft.payload),
                  let payloadJSON = String(data: payloadData, encoding: .utf8)
            else { continue }
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
        }
    }

    private func persistAgentMetadata(
        _ metadata: CampusAIMessageAgentMetadata,
        for message: CampusAIMessage
    ) {
        guard let data = try? JSONEncoder().encode(metadata),
              let json = String(data: data, encoding: .utf8)
        else { return }
        message.agentMetadataJSON = json
        try? modelContext.save()
    }

    @MainActor
    private func cancelActionRecord(_ record: CampusAIActionRecord) {
        guard record.status == .pending else { return }
        record.statusRawValue = CampusAIActionStatus.cancelled.rawValue
        record.updatedAt = Date()
        try? modelContext.save()
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
                actionEditor = CampusAIActionEditorPresentation(record: record, draft: validated)
            case .createTimetableReminder:
                actionEditor = CampusAIActionEditorPresentation(record: record, draft: validated)
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
            actionEditor = nil
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
            actionEditor = nil
        } catch {
            markAction(presentation.record, status: .failed)
            actionEditor = nil
            operationAlert = .failure(error.localizedDescription)
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
        try? modelContext.save()
    }

    private func clearAllHistory() {
        if activeStreamTask != nil || activeStreamMessageID != nil {
            if let activeStreamMessageID {
                discardedStreamMessageIDs.insert(activeStreamMessageID)
            }
            cancelStreaming()
        }
        try? CampusAIDeliverableFileBuilder.removeAllArtifacts()
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
        try? modelContext.save()
    }

    private func pruneOrphanedDeliverableArtifacts() {
        let retainedMessageIDs = Set(messages.map(\.id))
        Task.detached {
            try? CampusAIDeliverableFileBuilder.pruneArtifacts(keeping: retainedMessageIDs)
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool = true) {
        let action = {
            proxy.scrollTo("campus-ai-bottom", anchor: .bottom)
        }
        if animated {
            withAnimation(.easeOut(duration: 0.22), action)
        } else {
            action()
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
        let title: String
        switch tool.name {
        case "web.search":
            title = "联网搜索"
        case "official.document.search":
            title = "官方资料检索"
        case "delegate.subtask":
            title = "子任务"
        case "action.plan":
            title = "动作规划"
        default:
            title = "工具"
        }

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

private extension CampusAIActionRecord {
    var status: CampusAIActionStatus {
        CampusAIActionStatus(rawValue: statusRawValue) ?? .pending
    }

    var kind: CampusAIActionKind? {
        CampusAIActionKind(rawValue: kindRawValue)
    }

    var payload: CampusAIActionPayload? {
        guard let data = payloadJSON.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(CampusAIActionPayload.self, from: data)
    }

    var actionDraft: CampusAIActionDraft? {
        guard let kind, let payload else { return nil }
        return CampusAIActionDraft(
            id: id.uuidString,
            kind: kind,
            title: title,
            detail: detail,
            payload: payload
        )
    }
}

extension CampusAIMessage {
    var agentMetadata: CampusAIMessageAgentMetadata {
        guard let data = agentMetadataJSON.data(using: .utf8),
              let metadata = try? JSONDecoder().decode(CampusAIMessageAgentMetadata.self, from: data)
        else {
            return .empty
        }
        return metadata
    }
}

private struct CampusAIMessageRow: View {
    @Environment(\.leafyThemeColorPreference) private var themeColorPreference

    let message: CampusAIMessage
    let actions: [CampusAIActionRecord]
    let isStreaming: Bool
    let executeAction: (CampusAIActionRecord) -> Void
    let cancelAction: (CampusAIActionRecord) -> Void
    @State private var isReasoningExpanded = false
    @State private var isTraceExpanded = false

    private var isUser: Bool {
        message.roleRawValue == CampusAIMessageRole.user.rawValue
    }

    private var answerText: String {
        message.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var reasoningText: String {
        message.reasoningText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var agentMetadata: CampusAIMessageAgentMetadata {
        message.agentMetadata
    }

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.compact) {
            if isUser {
                Spacer(minLength: 46)
            } else {
                assistantAvatar
            }

            messageContent
                .frame(maxWidth: isUser ? 420 : 680, alignment: isUser ? .trailing : .leading)

            if !isUser {
                Spacer(minLength: 46)
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }

    @ViewBuilder
    private var messageContent: some View {
        if isUser {
            Text(message.text)
                .font(.body)
                .foregroundStyle(AppTheme.primaryText)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(
                    AppTheme.accent(for: themeColorPreference).opacity(0.16),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                )
                .multilineTextAlignment(.leading)
        } else if answerText.isEmpty && reasoningText.isEmpty {
            CampusAITypingDots()
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(AppTheme.softFill, in: Capsule())
        } else {
            VStack(alignment: .leading, spacing: 10) {
                if !reasoningText.isEmpty {
                    DisclosureGroup(isExpanded: $isReasoningExpanded) {
                        CampusAIMessageMarkdown(markdown: reasoningText, isStreaming: isStreaming)
                            .padding(.top, 4)
                    } label: {
                        Text("思考过程")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    .tint(AppTheme.secondaryText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(AppTheme.softFill.opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                if answerText.isEmpty {
                    CampusAITypingDots()
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(AppTheme.softFill, in: Capsule())
                } else {
                    CampusAIMessageMarkdown(markdown: message.text, isStreaming: isStreaming)
                }

                if let statusText = agentMetadata.statusText?.nonEmptyTrimmed, isStreaming {
                    CampusAIAgentStatusPill(text: statusText)
                }

                if !agentMetadata.citations.isEmpty || agentMetadata.deliverables.contains(where: { !$0.sources.isEmpty }) {
                    CampusAISourceAttachmentPillList(
                        citations: agentMetadata.citations,
                        deliverables: agentMetadata.deliverables
                    )
                }

                if !agentMetadata.deliverables.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(agentMetadata.deliverables) { deliverable in
                            ForEach(displayFormats(for: deliverable)) { format in
                                CampusAIDeliverableCard(
                                    deliverable: deliverable,
                                    messageID: message.id,
                                    format: format
                                )
                            }
                        }
                    }
                }

                if !agentMetadata.agentTrace.isEmpty {
                    CampusAIAgentTraceDisclosure(
                        steps: agentMetadata.agentTrace,
                        isExpanded: $isTraceExpanded
                    )
                }

                if !actions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(actions) { action in
                            CampusAIActionCard(
                                action: action,
                                executeAction: executeAction,
                                cancelAction: cancelAction
                            )
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .font(.body)
            .foregroundStyle(AppTheme.primaryText)
            .padding(.vertical, 4)
            .multilineTextAlignment(.leading)
        }
    }

    private var assistantAvatar: some View {
        Image(systemName: "sparkles")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(AppTheme.accent)
            .frame(width: 28, height: 28)
            .background(AppTheme.accent.opacity(0.12), in: Circle())
            .padding(.top, 2)
    }

    private func displayFormats(for deliverable: CampusAIDeliverable) -> [CampusAIDeliverableFileFormat] {
        let formats = deliverable.formats.isEmpty ? [.html] : deliverable.formats
        return CampusAIDeliverableFileFormat.allCases.filter { formats.contains($0) }
    }
}

private struct CampusAITypingRow: View {
    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.compact) {
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 28, height: 28)
                .background(AppTheme.accent.opacity(0.12), in: Circle())

            CampusAITypingDots()
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(AppTheme.softFill, in: Capsule())

            Spacer(minLength: 46)
        }
    }
}

private struct CampusAIAgentStatusPill: View {
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.small)
            Text(text)
                .font(.caption.weight(.medium))
                .foregroundStyle(AppTheme.secondaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(AppTheme.softFill.opacity(0.72), in: Capsule())
    }
}

private struct CampusAISourceAttachmentPillList: View {
    private struct PillItem: Identifiable, Hashable {
        enum Kind: Hashable {
            case source
            case attachment(String)
        }

        let id: String
        let title: String
        let subtitle: String?
        let url: String
        let kind: Kind

        var iconName: String {
            switch kind {
            case .source:
                return "link"
            case .attachment:
                return "paperclip"
            }
        }

        var badge: String {
            switch kind {
            case .source:
                return "来源"
            case .attachment(let fileType):
                return fileType.uppercased()
            }
        }
    }

    let citations: [CampusAICitation]
    let deliverables: [CampusAIDeliverable]

    private var items: [PillItem] {
        var result: [PillItem] = []
        var seen = Set<String>()

        for citation in citations {
            append(
                PillItem(
                    id: "citation-\(citation.id)",
                    title: citation.title.nonEmptyTrimmed ?? citation.url,
                    subtitle: citation.siteName?.nonEmptyTrimmed,
                    url: citation.url,
                    kind: .source
                ),
                to: &result,
                seen: &seen
            )
        }

        for deliverable in deliverables {
            for source in deliverable.sources {
                append(
                    PillItem(
                        id: "source-\(source.id)",
                        title: source.title.nonEmptyTrimmed ?? source.url,
                        subtitle: source.siteName?.nonEmptyTrimmed,
                        url: source.url,
                        kind: .source
                    ),
                    to: &result,
                    seen: &seen
                )

                for attachment in source.attachments {
                    append(
                        PillItem(
                            id: "attachment-\(attachment.url)",
                            title: attachment.title.nonEmptyTrimmed ?? attachment.url,
                            subtitle: source.title.nonEmptyTrimmed,
                            url: attachment.url,
                            kind: .attachment(attachment.fileType.nonEmptyTrimmed ?? "附件")
                        ),
                        to: &result,
                        seen: &seen
                    )
                }
            }
        }

        return Array(result.prefix(12))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(items) { item in
                pill(item)
            }
        }
    }

    @ViewBuilder
    private func pill(_ item: PillItem) -> some View {
        if let url = URL(string: item.url), ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            Link(destination: url) {
                pillContent(item)
            }
        } else {
            pillContent(item)
        }
    }

    private func pillContent(_ item: PillItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: item.iconName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(1)

                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Text(item.badge)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(AppTheme.cardElevated.opacity(0.8), in: Capsule())
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.softFill.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func append(_ item: PillItem, to result: inout [PillItem], seen: inout Set<String>) {
        let key = "\(item.url)|\(item.title)|\(item.badge)"
        guard !seen.contains(key), !item.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        seen.insert(key)
        result.append(item)
    }
}

private struct CampusAIDeliverableCard: View {
    let deliverable: CampusAIDeliverable
    let messageID: UUID
    let format: CampusAIDeliverableFileFormat

    @State private var previewItem: CampusAIDeliverablePreviewItem?
    @State private var fileError: String?

    var body: some View {
        Button {
            open(format)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: iconName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 30, height: 30)
                    .background(AppTheme.accent.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(deliverable.title.nonEmptyTrimmed ?? "学校官方资料包")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(deliverable.summary.nonEmptyTrimmed ?? "已整理官方来源和附件链接。")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                HStack(spacing: 5) {
                    Text(format.displayTitle)
                        .font(.caption2.weight(.bold))
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                }
                .foregroundStyle(AppTheme.accent)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(AppTheme.accent.opacity(0.12), in: Capsule())
            }
        }
        .buttonStyle(.plain)
        .padding(13)
        .background(AppTheme.softFill.opacity(0.72), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .sheet(item: $previewItem) { item in
            CampusAIDeliverablePreviewSheet(item: item)
        }
        .alert("无法生成资料包", isPresented: fileErrorBinding) {
            Button("好", role: .cancel) {}
        } message: {
            Text(fileError ?? "请稍后重试。")
        }
    }

    private var fileErrorBinding: Binding<Bool> {
        Binding(
            get: { fileError != nil },
            set: { isPresented in
                if !isPresented {
                    fileError = nil
                }
            }
        )
    }

    private func open(_ format: CampusAIDeliverableFileFormat) {
        do {
            let url = try CampusAIDeliverableFileBuilder.writeFile(
                for: deliverable,
                messageID: messageID,
                format: format
            )
            previewItem = CampusAIDeliverablePreviewItem(
                title: format.displayTitle,
                format: format,
                url: url
            )
        } catch {
            fileError = error.localizedDescription
        }
    }

    private var iconName: String {
        switch format {
        case .html:
            return "safari"
        case .markdown:
            return "doc.richtext"
        case .txt:
            return "doc.text"
        }
    }
}

private struct CampusAIDeliverablePreviewItem: Identifiable {
    let id = UUID()
    let title: String
    let format: CampusAIDeliverableFileFormat
    let url: URL
}

private struct CampusAIActionEditorPresentation: Identifiable {
    let id: UUID
    let record: CampusAIActionRecord
    let draft: CampusAIActionDraft

    init(record: CampusAIActionRecord, draft: CampusAIActionDraft) {
        self.id = record.id
        self.record = record
        self.draft = draft
    }
}

private struct CampusAIActionEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let presentation: CampusAIActionEditorPresentation
    let onSave: (CampusAIActionDraft) -> Void

    @State private var countdownTitle: String
    @State private var targetDate: Date
    @State private var week: Int
    @State private var dayOfWeek: Int
    @State private var period: Int
    @State private var endPeriod: Int
    @State private var reminderTitle: String
    @State private var location: String
    @State private var note: String
    @State private var minutesBefore: Int

    init(
        presentation: CampusAIActionEditorPresentation,
        onSave: @escaping (CampusAIActionDraft) -> Void
    ) {
        self.presentation = presentation
        self.onSave = onSave
        let payload = presentation.draft.payload
        _countdownTitle = State(initialValue: payload.countdownTitle ?? payload.title ?? "")
        _targetDate = State(initialValue: CampusAIActionValidation.countdownDate(for: presentation.draft) ?? Date())
        _week = State(initialValue: max(1, min(payload.week ?? SemesterConfig.currentWeek(), SemesterConfig.supportedWeeks)))
        _dayOfWeek = State(initialValue: max(1, min(payload.dayOfWeek ?? 1, 7)))
        let initialPeriod = payload.period ?? TimetablePeriodSchedule.slots.first?.period ?? 1
        _period = State(initialValue: max(1, min(initialPeriod, TimetablePeriodSchedule.slots.last?.period ?? 12)))
        _endPeriod = State(initialValue: max(initialPeriod, min(payload.endPeriod ?? initialPeriod, TimetablePeriodSchedule.slots.last?.period ?? 12)))
        _reminderTitle = State(initialValue: payload.title ?? payload.countdownTitle ?? "")
        _location = State(initialValue: payload.location ?? "")
        _note = State(initialValue: payload.note ?? "")
        _minutesBefore = State(initialValue: max(0, payload.minutesBefore ?? 0))
    }

    var body: some View {
        NavigationStack {
            Form {
                switch presentation.draft.kind {
                case .createCountdown:
                    countdownSection
                case .createTimetableReminder:
                    timetableReminderSection
                default:
                    Text("这个动作不需要编辑。")
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(editedDraft)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
            .onChange(of: period) { _, newValue in
                if endPeriod < newValue {
                    endPeriod = newValue
                }
            }
        }
    }

    private var countdownSection: some View {
        Section("重要日期") {
            TextField("标题", text: $countdownTitle)
            DatePicker("目标日期", selection: $targetDate, displayedComponents: .date)
        }
    }

    private var timetableReminderSection: some View {
        Section("课表提醒") {
            TextField("标题", text: $reminderTitle)
            Stepper("第 \(week) 周", value: $week, in: 1...SemesterConfig.supportedWeeks)
            Picker("星期", selection: $dayOfWeek) {
                ForEach(1...7, id: \.self) { day in
                    Text(Self.weekdayText(day)).tag(day)
                }
            }
            Stepper("开始节次：\(period)", value: $period, in: periodRange)
            Stepper("结束节次：\(endPeriod)", value: $endPeriod, in: period...periodRange.upperBound)
            TextField("地点", text: $location)
            TextField("备注", text: $note, axis: .vertical)
                .lineLimit(2...4)
            Stepper(minutesBefore > 0 ? "提前 \(minutesBefore) 分钟提醒" : "不提前提醒", value: $minutesBefore, in: 0...180, step: 5)
        }
    }

    private var navigationTitle: String {
        switch presentation.draft.kind {
        case .createCountdown:
            return "编辑重要日期"
        case .createTimetableReminder:
            return "编辑课表提醒"
        default:
            return "编辑动作"
        }
    }

    private var canSave: Bool {
        switch presentation.draft.kind {
        case .createCountdown:
            return countdownTitle.nonEmptyTrimmed != nil
        case .createTimetableReminder:
            return reminderTitle.nonEmptyTrimmed != nil
        default:
            return false
        }
    }

    private var editedDraft: CampusAIActionDraft {
        switch presentation.draft.kind {
        case .createCountdown:
            let target = DateFormatters.queryDate.string(from: targetDate)
            return CampusAIActionDraft(
                id: presentation.draft.id,
                kind: .createCountdown,
                title: presentation.draft.title,
                detail: presentation.draft.detail,
                payload: CampusAIActionPayload(
                    countdownTitle: countdownTitle,
                    targetDate: target
                )
            )
        case .createTimetableReminder:
            return CampusAIActionDraft(
                id: presentation.draft.id,
                kind: .createTimetableReminder,
                title: presentation.draft.title,
                detail: presentation.draft.detail,
                payload: CampusAIActionPayload(
                    week: week,
                    dayOfWeek: dayOfWeek,
                    period: period,
                    endPeriod: endPeriod,
                    title: reminderTitle,
                    location: location,
                    note: note,
                    minutesBefore: minutesBefore
                )
            )
        default:
            return presentation.draft
        }
    }

    private var periodRange: ClosedRange<Int> {
        let periods = TimetablePeriodSchedule.slots.map(\.period)
        return (periods.min() ?? 1)...(periods.max() ?? 12)
    }

    private static func weekdayText(_ day: Int) -> String {
        ["周一", "周二", "周三", "周四", "周五", "周六", "周日"][max(1, min(day, 7)) - 1]
    }
}

private struct CampusAIDeliverablePreviewSheet: View {
    let item: CampusAIDeliverablePreviewItem

    var body: some View {
        NavigationStack {
            Group {
                if item.format == .html {
                    CampusAIHTMLArtifactPreview(url: item.url)
                } else {
                    CampusAITextArtifactPreview(url: item.url)
                }
            }
            .navigationTitle(item.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: item.url) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("分享资料包")
                }
            }
        }
    }
}

private struct CampusAIHTMLArtifactPreview: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        WKWebView(frame: .zero)
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }
}

private struct CampusAITextArtifactPreview: View {
    let url: URL

    @State private var text = ""
    @State private var errorText: String?

    var body: some View {
        ScrollView {
            Text(errorText ?? text)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(errorText == nil ? AppTheme.primaryText : AppTheme.danger)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(AppSpacing.page)
        }
        .background(AppTheme.cardElevated)
        .task(id: url) {
            do {
                text = try String(contentsOf: url, encoding: .utf8)
                errorText = nil
            } catch {
                errorText = error.localizedDescription
            }
        }
    }
}

private struct CampusAIAgentTraceDisclosure: View {
    let steps: [CampusAIAgentTraceStep]
    @Binding var isExpanded: Bool

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(steps.prefix(12)) { step in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: iconName(for: step))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(color(for: step))
                            .frame(width: 18, height: 18)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(step.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.primaryText)

                            if let detail = step.detail?.nonEmptyTrimmed {
                                Text(detail)
                                    .font(.caption2)
                                    .foregroundStyle(AppTheme.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            .padding(.top, 6)
        } label: {
            Label("执行链路", systemImage: "point.3.connected.trianglepath.dotted")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)
        }
        .tint(AppTheme.secondaryText)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(AppTheme.softFill.opacity(0.72), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func iconName(for step: CampusAIAgentTraceStep) -> String {
        switch step.status {
        case "completed":
            return "checkmark.circle.fill"
        case "failed":
            return "exclamationmark.triangle.fill"
        case "skipped":
            return "minus.circle.fill"
        default:
            return "circle.dotted"
        }
    }

    private func color(for step: CampusAIAgentTraceStep) -> Color {
        switch step.status {
        case "completed":
            return .green
        case "failed":
            return AppTheme.danger
        case "skipped":
            return AppTheme.secondaryText
        default:
            return AppTheme.accent
        }
    }
}

private struct CampusAIActionCard: View {
    let action: CampusAIActionRecord
    let executeAction: (CampusAIActionRecord) -> Void
    let cancelAction: (CampusAIActionRecord) -> Void

    private var isPending: Bool {
        action.status == .pending
    }

    private var kindTitle: String {
        switch action.kind {
        case .openAcademicRoute:
            return "打开页面"
        case .createCountdown:
            return "创建重要日期"
        case .createTimetableReminder:
            return "创建课表提醒"
        case nil:
            return "待确认动作"
        }
    }

    private var statusText: String {
        switch action.status {
        case .pending:
            return "待确认"
        case .completed:
            return "已执行"
        case .cancelled:
            return "已取消"
        case .failed:
            return "执行失败"
        }
    }

    private var iconName: String {
        switch action.kind {
        case .openAcademicRoute:
            return "arrow.up.right.square"
        case .createCountdown:
            return "calendar.badge.clock"
        case .createTimetableReminder:
            return "bell.badge"
        case nil:
            return "sparkles"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                if isPending {
                    executeAction(action)
                }
            } label: {
                cardContent
                    .padding(13)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        AppTheme.softFill.opacity(0.72),
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!isPending)
            .accessibilityHint(isPending ? "点按打开或编辑这个动作" : statusText)

            if isPending {
                Button {
                    cancelAction(action)
                } label: {
                    Label("忽略", systemImage: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(AppTheme.cardElevated.opacity(0.7), in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.leading, 42)
            }
        }
    }

    private var cardContent: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 32, height: 32)
                .background(AppTheme.accent.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(kindTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)

                    Text(statusText)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(statusForeground)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(statusForeground.opacity(0.1), in: Capsule())
                }

                Text(action.title.nonEmptyTrimmed ?? kindTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                if let detail = action.detail.nonEmptyTrimmed {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: AppSpacing.micro)

            if isPending {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.tertiaryText)
                    .frame(width: 20, height: 32)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusForeground: Color {
        switch action.status {
        case .pending:
            return AppTheme.accent
        case .completed:
            return .green
        case .cancelled:
            return AppTheme.secondaryText
        case .failed:
            return AppTheme.danger
        }
    }
}

private struct CampusAITypingDots: View {
    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { _ in
                Circle()
                    .fill(AppTheme.secondaryText.opacity(0.45))
                    .frame(width: 6, height: 6)
            }
        }
    }
}

private struct CampusAIMessageMarkdown: View {
    let markdown: String
    let isStreaming: Bool

    var body: some View {
        if isStreaming {
            CampusAIMarkdownFallbackText(markdown: markdown)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            CampusAIMarkdownWebView(markdown: markdown)
        }
    }
}

private struct CampusAISettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var settings: CampusAIUserSettings
    @State private var configuredProviderIDs: Set<CampusAIProviderID> = []
    @StateObject private var subscriptionStore = CampusAISubscriptionStore()
    @State private var isPaywallPresented = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        CampusAIServiceSettingsPage(
                            settings: $settings,
                            subscriptionStore: subscriptionStore,
                            isPaywallPresented: $isPaywallPresented
                        )
                    } label: {
                        CampusAISettingsNavigationRow(
                            systemImage: "sparkles",
                            title: "服务与联网",
                            detail: serviceSummary,
                            status: settings.serviceMode.shortTitle
                        )
                    }

                    NavigationLink {
                        CampusAIAPIKeySettingsPage(
                            settings: $settings,
                            configuredProviderIDs: configuredProviderIDs,
                            refreshConfiguredProviders: refreshConfiguredProviders
                        )
                    } label: {
                        CampusAISettingsNavigationRow(
                            systemImage: "key.fill",
                            title: "自备 API Key",
                            detail: apiKeySummary,
                            status: configuredProviderIDs.contains(settings.selectedProviderID) ? "已配置" : "未配置"
                        )
                    }
                } header: {
                    Text("AI 服务")
                } footer: {
                    Text("自备 Key 可使用非联网 agent 能力；Leafy 托管额外提供额度和联网搜索。")
                }

                Section {
                    NavigationLink {
                        CampusAIPromptSettingsPage(settings: $settings)
                    } label: {
                        CampusAISettingsNavigationRow(
                            systemImage: "text.alignleft",
                            title: "回答偏好",
                            detail: promptSummary,
                            status: settings.systemPrompt == CampusAISettingsStore.defaultSystemPrompt ? "默认" : "已自定义"
                        )
                    }

                    NavigationLink {
                        CampusAIContextSettingsPage(settings: $settings)
                    } label: {
                        CampusAISettingsNavigationRow(
                            systemImage: "switch.2",
                            title: "本机上下文",
                            detail: contextSummary,
                            status: "\(enabledContextScopeCount)/8"
                        )
                    }
                } header: {
                    Text("回答配置")
                } footer: {
                    Text("这些设置只影响后续请求，不会改写已有对话内容。")
                }

                Section("历史记录") {
                    LabeledContent("历史记录", value: "本机保存")
                }

                Section {
                    Text("当前使用 DeepSeek V4 Flash。AI 生成可能包含错误、遗漏或过时内容，请审慎采用回答。")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.secondaryText)
                        .textSelection(.enabled)
                } header: {
                    Text("说明")
                } footer: {
                    Text("Leafy 会使用你在本机保存的 DeepSeek API Key 直接请求供应商服务，不会把 API Key 写入设置文件。")
                }
            }
            .onChange(of: settings) { _, newValue in
                CampusAISettingsStore.save(newValue)
            }
            .onAppear {
                refreshConfiguredProviders()
                Task { await subscriptionStore.refresh() }
            }
            .sheet(isPresented: $isPaywallPresented) {
                CampusAISubscriptionPaywallView(store: subscriptionStore)
            }
            .navigationTitle("Leafy 设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("重置") {
                        settings = .defaultValue
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        CampusAISettingsStore.save(settings)
                        dismiss()
                    }
                }
            }
        }
        .campusAISettingsPresentation()
    }

    private var quotaText: String {
        guard let quota = subscriptionStore.quota else {
            return subscriptionStore.isLoading ? "同步中" : "未同步"
        }
        return "\(quota.remaining)/\(quota.limit)"
    }

    private var serviceSummary: String {
        switch settings.serviceMode {
        case .leafyManaged:
            return "额度 \(quotaText) · 联网\(settings.webSearchEnabled ? "开启" : "关闭")"
        case .ownAPIKey:
            return "使用 \(settings.selectedProvider.modelDisplayName)，不消耗 Leafy 托管额度"
        }
    }

    private var apiKeySummary: String {
        "\(settings.selectedProvider.displayName) · \(settings.selectedProvider.modelDisplayName)"
    }

    private var promptSummary: String {
        settings.systemPrompt == CampusAISettingsStore.defaultSystemPrompt
            ? "使用 Leafy 默认回答偏好"
            : "已追加自定义偏好"
    }

    private var contextSummary: String {
        "允许 \(enabledContextScopeCount) 类本机数据进入上下文"
    }

    private var enabledContextScopeCount: Int {
        [
            settings.contextSettings.includesTimetable,
            settings.contextSettings.includesGrades,
            settings.contextSettings.includesExamsAndPlans,
            settings.contextSettings.includesLearningWorkspace,
            settings.contextSettings.includesPostgraduateAndCareer,
            settings.contextSettings.includesHonorsFitnessQuality,
            settings.contextSettings.includesMedicalLedger,
            settings.contextSettings.includesCommunityCache
        ].filter { $0 }.count
    }

    private func refreshConfiguredProviders() {
        configuredProviderIDs = CampusAIKeychainStore.configuredProviderIDs()
        if settings.serviceMode == .ownAPIKey,
           !configuredProviderIDs.contains(settings.selectedProviderID) {
            settings.serviceMode = .leafyManaged
        }
    }
}

private struct CampusAISettingsNavigationRow: View {
    let systemImage: String
    let title: String
    let detail: String
    let status: String

    var body: some View {
        HStack(spacing: AppSpacing.compact) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 28, height: 28)
                .background(AppTheme.accent.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText)

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: AppSpacing.compact)

            Text(status)
                .font(.caption.weight(.medium))
                .foregroundStyle(AppTheme.tertiaryText)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

private struct CampusAIServiceSettingsPage: View {
    @Binding var settings: CampusAIUserSettings
    @ObservedObject var subscriptionStore: CampusAISubscriptionStore
    @Binding var isPaywallPresented: Bool

    var body: some View {
        Form {
            Section {
                Picker("模式", selection: $settings.serviceMode) {
                    ForEach(CampusAIServiceMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }

                if settings.serviceMode == .leafyManaged {
                    LabeledContent("额度", value: quotaText)
                    Toggle("联网搜索", isOn: $settings.webSearchEnabled)
                } else {
                    LabeledContent("联网搜索", value: "不可用")
                    LabeledContent("Agent Mode", value: "可用")
                }
            } header: {
                Text("服务模式")
            } footer: {
                Text("自备 API Key 可使用非联网 agent 能力。联网搜索和官方资料检索只在 Leafy 托管模式下生效。")
            }

            if settings.serviceMode == .leafyManaged {
                Section {
                    Button {
                        isPaywallPresented = true
                    } label: {
                        Label("升级 Leafy AI", systemImage: "sparkles")
                    }

                    Button {
                        Task { await subscriptionStore.restorePurchases() }
                    } label: {
                        Label("恢复购买", systemImage: "arrow.clockwise")
                    }
                } header: {
                    Text("订阅")
                }
            }
        }
        .navigationTitle("服务与联网")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var quotaText: String {
        guard let quota = subscriptionStore.quota else {
            return subscriptionStore.isLoading ? "同步中" : "未同步"
        }
        return "\(quota.remaining)/\(quota.limit)"
    }
}

private struct CampusAIAPIKeySettingsPage: View {
    @Binding var settings: CampusAIUserSettings
    let configuredProviderIDs: Set<CampusAIProviderID>
    let refreshConfiguredProviders: () -> Void

    var body: some View {
        Form {
            Section {
                ForEach(CampusAIProviderCatalog.all) { provider in
                    NavigationLink {
                        CampusAIProviderSettingsView(
                            provider: provider,
                            selectedProviderID: $settings.selectedProviderID,
                            onAPIKeyChanged: refreshConfiguredProviders
                        )
                    } label: {
                        CampusAIProviderListRow(
                            provider: provider,
                            isConfigured: configuredProviderIDs.contains(provider.id),
                            isSelected: settings.selectedProviderID == provider.id
                        )
                    }
                }
            } footer: {
                Text("API Key 只保存在当前设备 Keychain。自备 Key 不消耗 Leafy 托管额度，也不会使用服务端联网搜索。")
            }
        }
        .navigationTitle("自备 API Key")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: refreshConfiguredProviders)
    }
}

private struct CampusAIPromptSettingsPage: View {
    @Binding var settings: CampusAIUserSettings

    var body: some View {
        Form {
            Section {
                TextEditor(text: $settings.systemPrompt)
                    .font(.body)
                    .frame(minHeight: 180)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button("恢复默认 Prompt") {
                    settings.systemPrompt = CampusAISettingsStore.defaultSystemPrompt
                }
            } header: {
                Text("System Prompt")
            } footer: {
                Text("这里会作为用户偏好追加到 Leafy 的基础安全提示词后。本机全局保存，所有新对话都会使用当前设置。")
            }
        }
        .navigationTitle("回答偏好")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct CampusAIContextSettingsPage: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var settings: CampusAIUserSettings

    private var contextSnapshot: CampusAIContextPayload {
        CampusAIContextBuilder.build(modelContext: modelContext, settings: settings.contextSettings)
    }

    var body: some View {
        Form {
            Section {
                Toggle("课表和提醒", isOn: $settings.contextSettings.includesTimetable)
                Toggle("成绩和排名", isOn: $settings.contextSettings.includesGrades)
                Toggle("考试和培养计划", isOn: $settings.contextSettings.includesExamsAndPlans)
                Toggle("学习空间", isOn: $settings.contextSettings.includesLearningWorkspace)
                Toggle("考研和职业规划", isOn: $settings.contextSettings.includesPostgraduateAndCareer)
                Toggle("荣誉、体测和综测", isOn: $settings.contextSettings.includesHonorsFitnessQuality)
                Toggle("医疗台账", isOn: $settings.contextSettings.includesMedicalLedger)
                Toggle("社区公开缓存", isOn: $settings.contextSettings.includesCommunityCache)

                Button("全部开启") {
                    settings.contextSettings = .defaultValue
                }
            } header: {
                Text("允许进入上下文的数据")
            } footer: {
                Text("上传文件、图片、OCR、PDF/Word/PPT/表格正文和本地文件路径不会进入上下文；只会使用标题、备注、分类、文件类型和更新时间等元数据。")
            }

            Section("当前数据状态") {
                ForEach(contextSnapshot.sourceStatus, id: \.scope) { status in
                    CampusAIContextSourceStatusRow(status: status)
                }
            }
        }
        .navigationTitle("本机上下文")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct CampusAIProviderListRow: View {
    let provider: CampusAIProviderDescriptor
    let isConfigured: Bool
    let isSelected: Bool

    var body: some View {
        HStack(spacing: AppSpacing.compact) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(provider.displayName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(AppTheme.primaryText)
                        .lineLimit(1)

                    if isSelected {
                        Text("当前")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(AppTheme.accent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(AppTheme.softFill, in: Capsule())
                    }
                }

                Text(provider.modelDisplayName)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: AppSpacing.compact)

            Text(isConfigured ? "已配置" : "未配置")
                .font(.caption.weight(.medium))
                .foregroundStyle(isConfigured ? AppTheme.accent : AppTheme.tertiaryText)
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }
}

private struct CampusAIContextSourceStatusRow: View {
    let status: CampusAIContextSourceStatus

    private var stateText: String {
        switch status.state {
        case .available:
            return "可用"
        case .missing:
            return "缺失"
        case .disabled:
            return "已关闭"
        case .localOnly:
            return "本地"
        }
    }

    private var stateColor: Color {
        switch status.state {
        case .available:
            return .green
        case .missing:
            return .orange
        case .disabled:
            return AppTheme.secondaryText
        case .localOnly:
            return AppTheme.accent
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(status.scope)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText)

                Spacer(minLength: AppSpacing.micro)

                Text(stateText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(stateColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(stateColor.opacity(0.12), in: Capsule())
            }

            Text(statusSummary)
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    private var statusSummary: String {
        let countText = "条目 \(status.itemCount)"
        if let lastSyncAt = status.lastSyncAt?.nonEmptyTrimmed {
            return "\(countText) · \(lastSyncAt)"
        }
        return "\(countText) · \(status.note)"
    }
}

private struct CampusAIProviderSettingsView: View {
    let provider: CampusAIProviderDescriptor
    @Binding var selectedProviderID: CampusAIProviderID
    let onAPIKeyChanged: () -> Void

    @State private var apiKeyDraft = ""
    @State private var hasSavedAPIKey = false
    @State private var operationAlert: LeafyOperationAlert?
    @FocusState private var isAPIKeyFocused: Bool

    var body: some View {
        Form {
            Section("服务") {
                LabeledContent("供应商", value: provider.displayName)
                LabeledContent("模型", value: provider.modelDisplayName)
                LabeledContent("Base URL", value: provider.baseURLString)
            }

            Section {
                SecureField("DeepSeek API Key", text: $apiKeyDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($isAPIKeyFocused)

                LabeledContent("状态", value: hasSavedAPIKey ? "已保存在 Keychain" : "未配置")

                Button(action: saveAPIKey) {
                    Label("保存 API Key", systemImage: "key.fill")
                }
                .disabled(apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button(role: .destructive, action: clearAPIKey) {
                    Label("清除 API Key", systemImage: "trash")
                }
                .disabled(!hasSavedAPIKey)
            } header: {
                Text("API Key")
            } footer: {
                Text("API Key 只保存在当前设备的 Keychain。输入框不会回显已保存的值，留空离开不会覆盖原有 Key。")
            }
        }
        .navigationTitle(provider.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: refreshAPIKeyState)
        .leafyOperationAlert($operationAlert)
    }

    private func saveAPIKey() {
        guard !apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do {
            try CampusAIKeychainStore.save(apiKeyDraft, providerID: provider.id)
            selectedProviderID = provider.id
            apiKeyDraft = ""
            refreshAPIKeyState()
            onAPIKeyChanged()
        } catch {
            operationAlert = .failure(error.localizedDescription)
        }
    }

    private func clearAPIKey() {
        do {
            try CampusAIKeychainStore.delete(providerID: provider.id)
            apiKeyDraft = ""
            refreshAPIKeyState()
            onAPIKeyChanged()
        } catch {
            operationAlert = .failure(error.localizedDescription)
        }
    }

    private func refreshAPIKeyState() {
        hasSavedAPIKey = CampusAIKeychainStore.hasAPIKey(providerID: provider.id)
    }
}

private struct CampusAISubscriptionPaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @ObservedObject var store: CampusAISubscriptionStore

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: AppSpacing.compact) {
                        Text("Leafy AI")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(AppTheme.primaryText)

                        Text(priceText)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(AppTheme.accent)

                        Text("每周 50 次 Leafy 托管 AI 查询，自动续费。")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    LabeledContent("当前额度", value: quotaText)
                    LabeledContent("免费额度", value: "10 次/月")
                    LabeledContent("订阅额度", value: store.subscriptionQuotaText)
                    LabeledContent("商品 ID", value: store.productID)
                }

                Section {
                    Button {
                        Task { await store.purchase() }
                    } label: {
                        Label(purchaseTitle, systemImage: "sparkles")
                    }
                    .disabled(store.product == nil || store.isLoading)

                    Button {
                        Task { await store.restorePurchases() }
                    } label: {
                        Label("恢复购买", systemImage: "arrow.clockwise")
                    }
                    .disabled(store.isLoading)

                    Button {
                        if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                            openURL(url)
                        }
                    } label: {
                        Label("管理订阅", systemImage: "slider.horizontal.3")
                    }
                } footer: {
                    Text("订阅由 App Store 处理。价格、税费和续费状态以 App Store 显示为准。")
                }

                if let errorMessage = store.errorMessage?.nonEmptyTrimmed {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(AppTheme.danger)
                            .textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("Leafy AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
            .task {
                await store.refresh()
            }
        }
        .campusAISettingsPresentation()
    }

    private var priceText: String {
        guard let displayPrice = store.displayPrice else {
            return store.isLoading ? "正在读取价格" : "价格未读取"
        }
        return "\(displayPrice)/\(store.billingPeriodText)"
    }

    private var purchaseTitle: String {
        guard let displayPrice = store.displayPrice else {
            return "订阅"
        }
        return "订阅 \(displayPrice)/\(store.billingPeriodText)"
    }

    private var quotaText: String {
        guard let quota = store.quota else {
            return store.isLoading ? "同步中" : "未同步"
        }
        return "\(quota.remaining)/\(quota.limit)"
    }
}

private struct CampusAISuggestionRow: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.compact) {
                Text(title)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(AppTheme.primaryText)
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .allowsTightening(true)

                Spacer()

                Image(systemName: "arrow.up.left")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.tertiaryText)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .background(
                AppTheme.softFill,
                in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
            )
        }
        .buttonStyle(.plain)
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

    @ViewBuilder
    func campusAISettingsPresentation() -> some View {
        #if os(iOS)
        self.presentationDetents([.large])
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
