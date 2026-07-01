import SwiftData
import SwiftUI

struct CampusAIAssistantView: View {
    @Environment(\.modelContext) private var modelContext
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
    @State private var userSettings = CampusAISettingsStore.load()
    @State private var isClearHistoryConfirmationPresented = false
    @State private var conversationPendingDeletion: CampusAIConversation?
    @State private var operationAlert: LeafyOperationAlert?
    @State private var isExperimentalNoticePresented = false
    @State private var visibleSuggestionPrompts = Self.randomSuggestionPrompts()
    @State private var configuredProviderIDs: Set<CampusAIProviderID> = []
    @State private var quotaSnapshot: CampusAIQuotaSnapshot?

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
        }
        .background(AppTheme.cardElevated)
        .onAppear {
            selectInitialConversationIfNeeded()
            presentExperimentalNoticeIfNeeded()
            refreshConfiguredProviders()
            refreshManagedQuotaIfNeeded()
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
        .alert("Leafy AI 仍在实验阶段", isPresented: $isExperimentalNoticePresented) {
            Button("我知道了") {
                experimentalNoticeAcknowledged = true
            }
        } message: {
            Text("AI 问答功能还在测试中，回复可能会有错误、遗漏或过时内容。涉及课程、考试、成绩、医疗、手续等事项，请以学校官方系统和最新通知为准。")
        }
        .onDisappear(perform: cancelStreaming)
        .confirmationDialog(
            "清空全部对话？",
            isPresented: $isClearHistoryConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("清空全部历史", role: .destructive) {
                clearAllHistory()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这只会删除当前设备上的 Leafy 聊天记录。")
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
                                isStreaming: isSending
                                    && selectedMessages.last?.id == message.id
                                    && message.roleRawValue == CampusAIMessageRole.assistant.rawValue
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
                TextField("询问 Leafy", text: $draftText, axis: .vertical)
                    .focused($isComposerFocused)
                    .lineLimit(1...5)
                    .textFieldStyle(.plain)
                    .submitLabel(.send)
                    .onSubmit {
                        submitDraft()
                    }
                    .padding(.leading, 18)
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
                in: Capsule(),
                fallbackFill: AppTheme.cardElevated.opacity(0.92)
            )
        }
        .padding(.horizontal, AppSpacing.page)
        .padding(.top, AppSpacing.micro)
        .padding(.bottom, AppSpacing.compact)
    }

    private var historyOverlay: some View {
        GeometryReader { proxy in
            let horizontalInset = AppSpacing.compact
            let panelWidth = min(proxy.size.width * 0.5, proxy.size.width - horizontalInset * 2)
            let topInset = proxy.safeAreaInsets.top + AppSpacing.compact
            let bottomInset = proxy.safeAreaInsets.bottom + RootFloatingTabBar.reservedHeight(controlScale: leafyControlScale) + AppSpacing.micro
            let panelHeight = max(280, proxy.size.height - topInset - bottomInset)

            ZStack(alignment: .leading) {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture {
                        isHistoryPresented = false
                    }

                historyPanel
                    .frame(width: panelWidth, height: panelHeight)
                    .offset(x: horizontalInset, y: (topInset - bottomInset) / 2)
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
                    isClearHistoryConfirmationPresented = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(conversations.isEmpty ? AppTheme.tertiaryText : AppTheme.danger)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .disabled(conversations.isEmpty)
                .accessibilityLabel("清空历史")
                .leafyGlassSurface(in: Circle(), isInteractive: true)
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
        guard activeStreamTask == nil else { return }
        activeStreamTask = Task {
            await sendCurrentDraft()
        }
    }

    private func cancelStreaming() {
        activeStreamTask?.cancel()
        activeStreamTask = nil
        isSending = false
    }

    @MainActor
    private func sendCurrentDraft() async {
        let text = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        defer {
            isSending = false
            activeStreamTask = nil
        }

        let conversation = selectedConversation ?? {
            let newConversation = CampusAIConversation()
            modelContext.insert(newConversation)
            selectedConversationID = newConversation.id
            return newConversation
        }()

        let conversationKey = conversation.id.uuidString
        let context = contextPayload
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

        do {
            var streamedAnswer = ""
            var streamedReasoning = ""
            var lastSaveAt = Date.distantPast
            for try await event in service.stream(
                message: text,
                context: context,
                recentMessages: Array(recentMessages),
                settings: userSettings
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
        for action in actionRecords where action.conversationID == key {
            modelContext.delete(action)
        }
        for message in messages where message.conversationID == key {
            modelContext.delete(message)
        }
        modelContext.delete(conversation)
        if selectedConversationID == conversation.id {
            selectedConversationID = conversations.first(where: { $0.id != conversation.id })?.id
        }
        try? modelContext.save()
    }

    private func clearAllHistory() {
        for action in actionRecords {
            modelContext.delete(action)
        }
        for message in messages {
            modelContext.delete(message)
        }
        for conversation in conversations {
            modelContext.delete(conversation)
        }
        selectedConversationID = nil
        try? modelContext.save()
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
}

private struct CampusAIMessageRow: View {
    @Environment(\.leafyThemeColorPreference) private var themeColorPreference

    let message: CampusAIMessage
    let isStreaming: Bool
    @State private var isReasoningExpanded = false

    private var isUser: Bool {
        message.roleRawValue == CampusAIMessageRole.user.rawValue
    }

    private var answerText: String {
        message.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var reasoningText: String {
        message.reasoningText.trimmingCharacters(in: .whitespacesAndNewlines)
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
                    Picker("模式", selection: $settings.serviceMode) {
                        ForEach(CampusAIServiceMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }

                    if settings.serviceMode == .leafyManaged {
                        LabeledContent("额度", value: quotaText)

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
                    }
                } header: {
                    Text("服务模式")
                } footer: {
                    Text("有 DeepSeek API Key 时可直接使用自备 Key；没有 Key 时使用 Leafy 托管额度。请求失败不会自动切换模式。")
                }

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
                } header: {
                    Text("使用已有 API Key")
                } footer: {
                    Text("DeepSeek API Key 只保存在当前设备 Keychain，使用此模式不会消耗 Leafy 托管额度。")
                }

                Section {
                    TextEditor(text: $settings.systemPrompt)
                        .font(.body)
                        .frame(minHeight: 150)
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
                    Text("上下文范围")
                } footer: {
                    Text("上传文件、图片、OCR、PDF/Word/PPT/表格正文和本地文件路径不会进入上下文；只会使用标题、备注、分类、文件类型和更新时间等元数据。")
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

    private func refreshConfiguredProviders() {
        configuredProviderIDs = CampusAIKeychainStore.configuredProviderIDs()
        if settings.serviceMode == .ownAPIKey,
           !configuredProviderIDs.contains(settings.selectedProviderID) {
            settings.serviceMode = .leafyManaged
        }
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

                        Text("每月 120 次 Leafy 托管 AI 查询，自动续费。")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    LabeledContent("当前额度", value: quotaText)
                    LabeledContent("免费额度", value: "10 次/月")
                    LabeledContent("订阅额度", value: "120 次/月")
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
            return "正在读取价格"
        }
        return "\(displayPrice)/月"
    }

    private var purchaseTitle: String {
        guard let displayPrice = store.displayPrice else {
            return "订阅"
        }
        return "订阅 \(displayPrice)/月"
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
