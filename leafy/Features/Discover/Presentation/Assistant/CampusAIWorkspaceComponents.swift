import SwiftData
import SwiftUI

struct CampusAIHistorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isClearConfirmationPresented = false

    let conversations: [CampusAIConversation]
    let selectedConversationID: UUID?
    let selectConversation: (CampusAIConversation) -> Void
    let deleteConversation: (CampusAIConversation) -> Void
    let clearHistory: () -> Void
    let openSettings: () -> Void

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
            .navigationTitle("历史记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button(action: openSettings) {
                        Label("Leafy 设置", systemImage: "gearshape")
                    }

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
                Button("清空全部历史", role: .destructive, action: clearHistory)
                Button("取消", role: .cancel) {}
            } message: {
                Text("这只会删除当前设备上的 Leafy 聊天记录。")
            }
        }
    }
}

struct CampusAIEmptyConversationPanel: View {
    let prompts: [String]
    let hasAPIKey: Bool
    let configureAPIKey: () -> Void
    let selectPrompt: (String) -> Void

    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 12) {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 58, height: 58)
                    .background(AppTheme.accent.opacity(0.10), in: Circle())

                Text("Leafy")
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText)

                Text("基于这台设备上的课表、考试、成绩与个人记录，帮你回答问题并整理成品。")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 380)
            }

            if hasAPIKey {
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

            Text("API Key 只保存在当前设备的 Keychain。Leafy 会把你允许的本机上下文随请求发送给 DeepSeek，不使用托管额度，也不会联网搜索。")
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
    let hasAPIKey: Bool
    let configureAPIKey: () -> Void
    let submit: () -> Void
    let cancelStreaming: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            if outputMode == .artifact {
                HStack(spacing: 8) {
                    Image(systemName: "doc.richtext")
                    Text("下一条消息将生成成品")
                        .font(.caption.weight(.medium))
                    Spacer(minLength: 8)
                    Button {
                        outputMode = .automatic
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.bold))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("取消生成成品")
                }
                .foregroundStyle(AppTheme.accent)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(AppTheme.accent.opacity(0.10), in: Capsule())
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            if hasAPIKey {
                HStack(alignment: .bottom, spacing: 8) {
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
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(AppTheme.secondaryText)
                            .frame(width: 36, height: 36)
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
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend && !isSending)
                    .accessibilityLabel(isSending ? "停止生成" : "发送")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(AppTheme.separator.opacity(0.42), lineWidth: 0.5)
                }
            } else {
                Button(action: configureAPIKey) {
                    Label("配置 DeepSeek Key", systemImage: "key.fill")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
            }
        }
        .padding(.horizontal, AppSpacing.page)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(.bar)
        .animation(accessibilityReduceMotion ? nil : .easeInOut(duration: 0.2), value: outputMode)
    }
}

private extension String {
    var nonEmptyTrimmed: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
