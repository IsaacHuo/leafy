import SwiftData
import SwiftUI

struct CampusAISettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var settings: CampusAIUserSettings
    @ObservedObject var subscriptionStore: CampusAISubscriptionStore
    let hasHistory: Bool
    let clearHistory: () -> Void
    @State private var hasAPIKey = false
    @State private var isClearHistoryConfirmationPresented = false
    @State private var operationAlert: LeafyOperationAlert?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        CampusAISubscriptionView(store: subscriptionStore) {}
                    } label: {
                        CampusAISettingsNavigationRow(
                            systemImage: "sparkles",
                            title: "Leafy AI 额度",
                            detail: quotaDetail,
                            status: subscriptionStore.isPurchased ? "已订阅" : "查看订阅"
                        )
                    }
                    if settings.serviceMode == .ownAPIKey {
                        Button("改回 Leafy AI 免费额度") {
                            settings.serviceMode = .leafyManaged
                        }
                    }

                    NavigationLink {
                        CampusAIAPIKeySetupView(settings: $settings) {
                            hasAPIKey = true
                        }
                    } label: {
                        CampusAISettingsNavigationRow(
                            systemImage: "key.fill",
                            title: "自备 DeepSeek API Key",
                            detail: "备选方式 · 可使用 Flash 或 Pro",
                            status: settings.serviceMode == .ownAPIKey ? "使用中" : (hasAPIKey ? "已配置" : "可选")
                        )
                    }

                    Toggle(isOn: $settings.webSearchEnabled) {
                        Label("联网研究", systemImage: "globe")
                    }
                } header: {
                    Text("AI 服务")
                } footer: {
                    Text("默认先使用每日免费额度，订阅后可获得更多次数。自备 Key 是可选方式，密钥只保存在本机 Keychain。")
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
                            detail: "允许 \(enabledContextScopeCount) 类本机数据进入请求上下文",
                            status: "\(enabledContextScopeCount)/8"
                        )
                    }
                } header: {
                    Text("回答配置")
                } footer: {
                    Text("这些设置只影响后续请求，不会改写已有对话。")
                }

                Section("历史记录") {
                    LabeledContent("保存位置", value: "当前设备")
                    Text("清除 API Key 后仍可使用免费或订阅额度；聊天历史不会自动同步到云端。")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.secondaryText)

                    Button("清空全部历史记录", role: .destructive) {
                        isClearHistoryConfirmationPresented = true
                    }
                    .disabled(!hasHistory)
                }

                Section("隐私与限制") {
                    Text("使用 Leafy AI 服务时，你的问题及获准上下文会经 Leafy 服务发送给 DeepSeek；使用自备 Key 时则由本机直接发送。开启联网研究后，搜索词会经过 Leafy 搜索服务。生成内容可能有错误，重要事项请核对来源。")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.secondaryText)
                        .textSelection(.enabled)
                }
            }
            .navigationTitle("Leafy 设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        saveSettingsAndDismiss()
                    }
                }
            }
            .onAppear {
                normalizeSettings()
                refreshAPIKeyState()
                Task { await subscriptionStore.refresh() }
            }
            .onChange(of: settings) { _, _ in
                persistSettings()
            }
            .confirmationDialog(
                "清空全部对话与成品？",
                isPresented: $isClearHistoryConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button("清空全部历史记录", role: .destructive, action: clearHistory)
                Button("取消", role: .cancel) {}
            } message: {
                Text("这会删除当前设备上的 Leafy 对话、动作记录与成品缓存，且无法撤销。")
            }
        }
        .presentationDetents([.large])
        .leafyOperationAlert($operationAlert)
    }

    private var promptSummary: String {
        settings.systemPrompt == CampusAISettingsStore.defaultSystemPrompt
            ? "使用 Leafy 默认回答偏好"
            : "已追加自定义偏好"
    }

    private var quotaDetail: String {
        guard let quota = subscriptionStore.quota else {
            return subscriptionStore.isLoading ? "正在刷新额度" : "每日免费 10 次"
        }
        if quota.planSource == "subscription" {
            return "本周期 \(quota.periodRemaining ?? quota.remaining)/\(quota.periodLimit ?? 120) · 今日 \(quota.dailyRemaining)/\(quota.dailyLimit)"
        }
        return "今日剩余 \(quota.dailyRemaining)/\(quota.dailyLimit)"
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

    private func normalizeSettings() {
        settings = settings.normalizedForLocalRuntime
    }

    private func refreshAPIKeyState() {
        hasAPIKey = CampusAIKeychainStore.hasAPIKey(providerID: settings.selectedProviderID)
    }

    private func persistSettings() {
        guard CampusAISettingsStore.save(settings) else {
            operationAlert = .failure("设置保存失败，请重试。")
            return
        }
    }

    private func saveSettingsAndDismiss() {
        guard CampusAISettingsStore.save(settings) else {
            operationAlert = .failure("设置保存失败，请重试。")
            return
        }
        dismiss()
    }
}

struct CampusAIAPIKeySetupView: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var settings: CampusAIUserSettings
    var focusesOnAppear = false
    let onAPIKeyChanged: () -> Void

    @State private var apiKeyDraft = ""
    @State private var hasSavedAPIKey = false
    @State private var operationAlert: LeafyOperationAlert?
    @FocusState private var isAPIKeyFocused: Bool

    private var provider: CampusAIProviderDescriptor { settings.selectedProvider }

    var body: some View {
        Form {
            Section {
                LabeledContent("供应商", value: provider.displayName)
                LabeledContent("模型", value: settings.selectedModel.fullDisplayName)
                LabeledContent("状态", value: hasSavedAPIKey ? "已保存在 Keychain" : "未配置")
            }

            Section {
                Text("1. 登录 DeepSeek 开放平台。")
                Text("2. 在 API Keys 页面创建并复制密钥。")
                Text("3. 返回 Leafy，将密钥粘贴到下方并保存。")

                Link(destination: provider.apiKeyManagementURL) {
                    Label("前往 DeepSeek API Keys", systemImage: "arrow.up.right.square")
                }
            } header: {
                Text("如何获取 API Key")
            } footer: {
                Text("链接将使用系统浏览器打开 DeepSeek 官方开放平台。")
            }

            Section {
                SecureField("DeepSeek API Key", text: $apiKeyDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($isAPIKeyFocused)

                Button(action: saveAPIKey) {
                    Label("保存并开始使用", systemImage: "key.fill")
                }
                .disabled(apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button(role: .destructive, action: clearAPIKey) {
                    Label("清除 API Key", systemImage: "trash")
                }
                .disabled(!hasSavedAPIKey)
            } header: {
                Text("API Key")
            } footer: {
                Text("API Key 只保存在当前设备的 Keychain，输入框不会回显已保存的值。保存后会明确切换到自备 Key；清除后可在设置中改回 Leafy AI 免费额度。")
            }

            Section("数据说明") {
                Text("选择自备 Key 后，模型请求会从本机直接发送到 DeepSeek，不使用免费或订阅额度。联网研究服务不会收到你的 DeepSeek API Key。")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .navigationTitle("DeepSeek Key")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            refreshAPIKeyState()
            if focusesOnAppear {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(300))
                    isAPIKeyFocused = true
                }
            }
        }
        .leafyOperationAlert($operationAlert)
    }

    private func saveAPIKey() {
        guard let trimmed = apiKeyDraft.nonEmptyTrimmed else { return }
        do {
            try CampusAIKeychainStore.save(trimmed, providerID: provider.id)
            settings.selectedProviderID = provider.id
            settings.serviceMode = .ownAPIKey
            guard CampusAISettingsStore.save(settings) else {
                operationAlert = .failure("API Key 已保存，但设置写入失败，请重试。")
                return
            }
            apiKeyDraft = ""
            refreshAPIKeyState()
            onAPIKeyChanged()
            dismiss()
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

struct CampusAISubscriptionView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: CampusAISubscriptionStore
    let onSubscribed: () -> Void

    private let privacyURL = URL(string: "https://myleafy.space/privacy")!
    private let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 10) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundStyle(AppTheme.accent)
                            .frame(width: 64, height: 64)
                            .background(AppTheme.accent.opacity(0.10), in: Circle())

                        Text("Leafy AI 周订阅")
                            .font(.title2.weight(.bold))
                        if let displayPrice = store.displayPrice {
                            Text("\(displayPrice)/周")
                                .font(.title3.weight(.semibold))
                        } else {
                            Text("正在读取 App Store 价格")
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                        Text("自动续订")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryText)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        subscriptionBenefit("每个订阅周期 120 次")
                        subscriptionBenefit("每日最多 40 次")
                        subscriptionBenefit("未订阅每日可免费使用 10 次")
                        subscriptionBenefit("Leafy AI 服务固定使用 Flash")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .background(AppTheme.softFill.opacity(0.72), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                    if let quota = store.quota {
                        Text(quotaText(quota))
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let pendingMessage = store.pendingMessage {
                        Label(pendingMessage, systemImage: "clock")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let errorMessage = store.errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button {
                        Task {
                            if await store.purchase() {
                                onSubscribed()
                                dismiss()
                            }
                        }
                    } label: {
                        Text(store.isPurchased ? "已订阅" : subscribeButtonTitle)
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accent)
                    .disabled(store.product == nil || store.isLoading || store.isPurchased)

                    Button("恢复购买") {
                        Task { await store.restorePurchases() }
                    }
                    .disabled(store.isLoading)

                    HStack(spacing: 18) {
                        Link("隐私政策", destination: privacyURL)
                        Link("使用条款", destination: termsURL)
                    }
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryText)
                }
                .leafyAdaptiveContentWidth(maxWidth: 560, horizontalPadding: AppSpacing.page)
                .padding(.vertical, 28)
            }
            .background(AppTheme.cardElevated.ignoresSafeArea())
            .navigationTitle("Leafy AI 订阅")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .task { await store.refresh() }
        }
    }

    private var subscribeButtonTitle: String {
        guard let displayPrice = store.displayPrice else { return "商品暂不可用" }
        return "订阅 · \(displayPrice)/周"
    }

    private func subscriptionBenefit(_ text: String) -> some View {
        Label {
            Text(text).foregroundStyle(AppTheme.primaryText)
        } icon: {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(AppTheme.accent)
        }
    }

    private func quotaText(_ quota: CampusAIQuotaSnapshot) -> String {
        if quota.planSource == "subscription" {
            return "订阅额度：本周期剩余 \(quota.periodRemaining ?? quota.remaining)/\(quota.periodLimit ?? 120)，今日剩余 \(quota.dailyRemaining)/\(quota.dailyLimit)。"
        }
        return "免费额度：今日剩余 \(quota.dailyRemaining)/\(quota.dailyLimit)。"
    }
}

private struct CampusAISettingsNavigationRow: View {
    let systemImage: String
    let title: String
    let detail: String
    let status: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 30, height: 30)
                .background(AppTheme.accent.opacity(0.10), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(AppTheme.primaryText)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)
            Text(status)
                .font(.caption)
                .foregroundStyle(AppTheme.tertiaryText)
        }
        .padding(.vertical, 3)
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

                Button("恢复默认偏好") {
                    settings.systemPrompt = CampusAISettingsStore.defaultSystemPrompt
                }
            } header: {
                Text("回答偏好")
            } footer: {
                Text("偏好会追加到 Leafy 的基础安全提示词后，并用于之后的新请求。")
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
                Text("上传文件正文、图片像素、OCR、PDF、Word、PPT 和本地文件路径不会进入上下文。")
            }

            Section("当前数据状态") {
                ForEach(contextSnapshot.sourceStatus, id: \.scope) { status in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(status.scope)
                                .font(.subheadline.weight(.medium))
                            Text("条目 \(status.itemCount) · \(status.note)")
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryText)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 8)
                        Text(status.state == .disabled ? "已关闭" : "本机")
                            .font(.caption)
                            .foregroundStyle(status.state == .disabled ? AppTheme.tertiaryText : AppTheme.accent)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle("本机上下文")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private extension String {
    var nonEmptyTrimmed: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
