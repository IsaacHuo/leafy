import SwiftUI

struct CampusAIChatTopBar: View {
    let openHistory: () -> Void
    let openSettings: () -> Void
    let selectedModelID: CampusAIModelID
    let allowsModelSelection: Bool
    let isModelSelectionDisabled: Bool
    let selectModel: (CampusAIModelID) -> Void
    let startNewConversation: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            LeafyGlassGroup(spacing: 10) {
                HStack(spacing: 10) {
                    LeafyGlassIconButton(
                        systemName: "clock.arrow.circlepath",
                        accessibilityLabel: "历史记录",
                        action: openHistory
                    )

                    LeafyGlassIconButton(
                        systemName: "gearshape",
                        accessibilityLabel: "Leafy 设置",
                        action: openSettings
                    )

                    if allowsModelSelection {
                        Menu {
                            ForEach(CampusAIModelCatalog.all) { model in
                                Button {
                                    selectModel(model.id)
                                } label: {
                                    if model.id == selectedModelID {
                                        Label(model.shortDisplayName, systemImage: "checkmark")
                                    } else {
                                        Text(model.shortDisplayName)
                                    }
                                }
                            }
                        } label: {
                            modelCapsuleLabel(
                                CampusAIModelCatalog.model(for: selectedModelID).shortDisplayName,
                                showsChevron: true
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isModelSelectionDisabled)
                        .accessibilityLabel("模型：\(CampusAIModelCatalog.model(for: selectedModelID).shortDisplayName)")
                    } else {
                        modelCapsuleLabel("Flash", showsChevron: false)
                            .accessibilityLabel("模型：Flash")
                    }
                }
            }

            Spacer(minLength: 16)

            LeafyGlassIconButton(
                systemName: "plus",
                accessibilityLabel: "新建对话",
                action: startNewConversation
            )
        }
        .padding(.horizontal, LeafyRootChromeMetrics.horizontalInset)
        .padding(.bottom, LeafyRootChromeMetrics.contentSpacing)
    }

    private func modelCapsuleLabel(_ title: String, showsChevron: Bool) -> some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
            }
        }
        .foregroundStyle(AppTheme.accent)
        .padding(.horizontal, 14)
        .frame(height: LeafyRootChromeMetrics.controlDiameter)
        .contentShape(Capsule())
        .leafyGlassSurface(in: Capsule(), isInteractive: showsChevron)
    }
}

struct CampusAIHistorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isClearConfirmationPresented = false

    let conversations: [CampusAIConversation]
    let selectedConversationID: UUID?
    let selectConversation: (CampusAIConversation) -> Void
    let deleteConversation: (CampusAIConversation) -> Void
    let clearHistory: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                if conversations.isEmpty {
                    ContentUnavailableView(
                        "暂无对话",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text("新的对话会保存在这台设备上。")
                    )
                } else {
                    conversationList
                }
            }
            .navigationTitle("历史记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        isClearConfirmationPresented = true
                    } label: {
                        Label("清空历史", systemImage: "trash")
                    }
                    .disabled(conversations.isEmpty)
                }
            }
            .confirmationDialog(
                "清空全部对话？",
                isPresented: $isClearConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button("清空全部历史", role: .destructive) {
                    clearHistory()
                    dismiss()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("这只会删除当前设备上的 Leafy 聊天记录。")
            }
        }
    }

    private var conversationList: some View {
        List {
            ForEach(conversations) { conversation in
                Button {
                    selectConversation(conversation)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(conversation.title.nonEmptyTrimmed ?? "新的对话")
                                .font(.body.weight(.medium))
                                .foregroundStyle(AppTheme.primaryText)
                                .lineLimit(1)

                            Text(conversation.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryText)
                        }

                        Spacer(minLength: 8)

                        if selectedConversationID == conversation.id {
                            Image(systemName: "checkmark")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.accent)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowSeparator(.hidden)
                .swipeActions {
                    Button(role: .destructive) {
                        deleteConversation(conversation)
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
    }
}

struct CampusAIEmptyConversationPanel: View {
    @Environment(\.leafyThemeColorPreference) private var themeColorPreference

    let prompts: [String]
    let canUseService: Bool
    let quotaText: String
    let openSubscription: () -> Void
    let configureAPIKey: () -> Void
    let selectPrompt: (String) -> Void

    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 12) {
                Text("Leafy")
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(AppTheme.accent(for: themeColorPreference))

                Text("和 Leafy 聊聊，获取建议。")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 380)
            }

            if canUseService {
                VStack(spacing: 0) {
                    ForEach(Array(prompts.enumerated()), id: \.element) { index, prompt in
                        Button {
                            selectPrompt(prompt)
                        } label: {
                            HStack(spacing: 12) {
                                Text(prompt)
                                    .font(.body)
                                    .foregroundStyle(AppTheme.primaryText)
                                    .multilineTextAlignment(.leading)

                                Spacer(minLength: 8)

                                Image(systemName: "arrow.up.left")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(AppTheme.tertiaryText)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if index < prompts.count - 1 {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
                .background(AppTheme.softFill.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .frame(maxWidth: 520)

                Button(action: openSubscription) {
                    Text(quotaText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.accent)
                }
                .buttonStyle(.plain)
            } else {
                CampusAIMissingKeyPanel(configureAPIKey: configureAPIKey)
                    .frame(maxWidth: 520)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct CampusAIMissingKeyPanel: View {
    let configureAPIKey: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("配置 DeepSeek Key 后开始", systemImage: "key.horizontal")
                .font(.headline)
                .foregroundStyle(AppTheme.primaryText)

            Text("API Key 只保存在当前设备的 Keychain。Leafy 会把你允许的本机上下文直接发送给 DeepSeek；联网研究只通过 Leafy Tool Gateway 执行公开搜索和网页读取。")
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: configureAPIKey) {
                Text("配置 DeepSeek Key")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.accent)
        }
        .padding(20)
        .background(AppTheme.softFill.opacity(0.72), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct CampusAIComposerBar: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Binding var draftText: String
    @Binding var outputMode: CampusAIOutputMode
    let isFocused: FocusState<Bool>.Binding
    let isSending: Bool
    let canSend: Bool
    let canUseService: Bool
    let isEditingMessage: Bool
    let configureAPIKey: () -> Void
    let cancelEditing: () -> Void
    let submit: () -> Void
    let cancelStreaming: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            if isEditingMessage {
                editingMessagePill
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            if outputMode == .artifact {
                artifactModePill
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            composerSurface
        }
        .frame(maxWidth: 820)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, LeafyRootChromeMetrics.horizontalInset)
        .padding(.bottom, 8)
        .animation(accessibilityReduceMotion ? nil : .easeInOut(duration: 0.2), value: outputMode)
        .animation(accessibilityReduceMotion ? nil : .easeInOut(duration: 0.2), value: isEditingMessage)
    }

    @ViewBuilder
    private var composerSurface: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 10) {
                composerContent
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 26))
            }
        } else {
            composerContent
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(AppTheme.separator.opacity(0.40), lineWidth: 0.5)
                }
                .shadow(color: Color.black.opacity(0.055), radius: 12, y: 5)
        }
    }

    @ViewBuilder
    private var composerContent: some View {
        if canUseService {
            HStack(alignment: .center, spacing: 2) {
                Menu {
                    Button {
                        outputMode = outputMode == .artifact ? .automatic : .artifact
                    } label: {
                        Label(
                            outputMode == .artifact ? "取消生成成品" : "生成成品",
                            systemImage: outputMode == .artifact ? "checkmark" : "doc.richtext"
                        )
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(AppTheme.primaryText)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("更多输入选项")

                TextField("问问 Leafy", text: $draftText, axis: .vertical)
                    .focused(isFocused)
                    .lineLimit(1...6)
                    .textFieldStyle(.plain)
                    .submitLabel(.send)
                    .onSubmit(submit)
                    .padding(.vertical, 10)

                Button(action: isSending ? cancelStreaming : submit) {
                    Image(systemName: isSending ? "stop.fill" : "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle((canSend || isSending) ? Color.white : AppTheme.tertiaryText)
                        .frame(width: 34, height: 34)
                        .background(
                            (canSend || isSending) ? AppTheme.accent : AppTheme.softFill,
                            in: Circle()
                        )
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .disabled(!canSend && !isSending)
                .accessibilityLabel(isSending ? "停止生成" : "发送")
            }
            .padding(.horizontal, 8)
            .frame(minHeight: 52)
        } else {
            Button(action: configureAPIKey) {
                Label("配置 DeepSeek Key", systemImage: "key.fill")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.accent)
            .padding(.horizontal, 12)
        }
    }

    @ViewBuilder
    private var editingMessagePill: some View {
        let pill = HStack(spacing: 8) {
            Image(systemName: "pencil")
            Text("正在编辑消息")
                .font(.caption.weight(.medium))
            Spacer(minLength: 8)
            Button(action: cancelEditing) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("取消编辑消息")
        }
        .foregroundStyle(AppTheme.accent)
        .padding(.leading, 14)
        .padding(.trailing, 4)

        if #available(iOS 26.0, *) {
            pill.glassEffect(.regular.tint(AppTheme.accent.opacity(0.10)), in: .capsule)
        } else {
            pill
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(AppTheme.accent.opacity(0.18), lineWidth: 0.5)
                }
        }
    }

    @ViewBuilder
    private var artifactModePill: some View {
        let pill = HStack(spacing: 8) {
            Image(systemName: "doc.richtext")
            Text("下一条消息将生成成品")
                .font(.caption.weight(.medium))
            Spacer(minLength: 8)
            Button(action: cancelArtifactMode) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("取消生成成品")
        }
        .foregroundStyle(AppTheme.accent)
        .padding(.leading, 14)
        .padding(.trailing, 4)

        if #available(iOS 26.0, *) {
            pill.glassEffect(.regular.tint(AppTheme.accent.opacity(0.10)), in: .capsule)
        } else {
            pill
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(AppTheme.accent.opacity(0.18), lineWidth: 0.5)
                }
        }
    }

    private func cancelArtifactMode() {
        if accessibilityReduceMotion {
            outputMode.resetToAutomatic()
        } else {
            withAnimation(.easeInOut(duration: 0.16)) {
                outputMode.resetToAutomatic()
            }
        }
    }
}

private extension String {
    var nonEmptyTrimmed: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
