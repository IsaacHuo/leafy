import SwiftData
import SwiftUI

struct CampusAISettingsView: View {
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

private extension View {
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
