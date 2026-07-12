import SwiftData
import SwiftUI

struct CampusAISettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var settings: CampusAIUserSettings
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
                        CampusAIAPIKeySetupView(settings: $settings) {
                            hasAPIKey = true
                        }
                    } label: {
                        CampusAISettingsNavigationRow(
                            systemImage: "key.fill",
                            title: "DeepSeek API Key",
                            detail: "DeepSeek V4 Flash · 仅保存在设备 Keychain",
                            status: hasAPIKey ? "已配置" : "未配置"
                        )
                    }
                } header: {
                    Text("AI 服务")
                } footer: {
                    Text("当前仅支持自备 DeepSeek API Key。订阅、托管额度和联网搜索暂不开放。")
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
                    Text("清除 API Key 后仍可只读浏览已有对话；聊天历史不会自动同步到云端。")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.secondaryText)

                    Button("清空全部历史记录", role: .destructive) {
                        isClearHistoryConfirmationPresented = true
                    }
                    .disabled(!hasHistory)
                }

                Section("隐私与限制") {
                    Text("Leafy 会把你的问题及已启用的本机上下文直接发送给 DeepSeek。API Key 不会写入设置文件；生成内容可能有错误，重要事项请以权威来源为准。")
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
                LabeledContent("模型", value: provider.modelDisplayName)
                LabeledContent("状态", value: hasSavedAPIKey ? "已保存在 Keychain" : "未配置")
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
                Text("API Key 只保存在当前设备的 Keychain，输入框不会回显已保存的值。清除后仍可浏览本机历史，但不能发送新消息。")
            }

            Section("数据说明") {
                Text("请求会直接发送到 DeepSeek，不经过 Leafy 托管额度；当前不启用联网搜索。")
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
            settings = settings.normalizedForLocalRuntime
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
