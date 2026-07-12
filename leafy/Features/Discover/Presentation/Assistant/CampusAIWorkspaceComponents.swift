import SwiftUI

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

                Text("和 Leafy 讨论任何问题；需要时，它也能结合你允许的本机数据整理建议与成品。")
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
                artifactModePill
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            composerSurface
        }
        .frame(maxWidth: 820)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .animation(accessibilityReduceMotion ? nil : .easeInOut(duration: 0.2), value: outputMode)
    }

    @ViewBuilder
    private var composerSurface: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 10) {
                composerContent
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 28))
            }
        } else {
            composerContent
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(AppTheme.separator.opacity(0.40), lineWidth: 0.5)
                }
                .shadow(color: Color.black.opacity(0.07), radius: 14, y: 6)
        }
    }

    @ViewBuilder
    private var composerContent: some View {
        if hasAPIKey {
            HStack(alignment: .bottom, spacing: 4) {
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
                        .font(.system(size: 19, weight: .medium))
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
                    .padding(.vertical, 15)

                Button(action: isSending ? cancelStreaming : submit) {
                    Image(systemName: isSending ? "stop.fill" : "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle((canSend || isSending) ? Color.white : AppTheme.tertiaryText)
                        .frame(width: 36, height: 36)
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
            .frame(minHeight: 56)
        } else {
            Button(action: configureAPIKey) {
                Label("配置 DeepSeek Key", systemImage: "key.fill")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 56)
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.accent)
            .padding(.horizontal, 12)
        }
    }

    @ViewBuilder
    private var artifactModePill: some View {
        let pill = HStack(spacing: 8) {
            Image(systemName: "doc.richtext")
            Text("下一条消息将生成成品")
                .font(.caption.weight(.medium))
            Spacer(minLength: 8)
            Button {
                outputMode = .automatic
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("取消生成成品")
        }
        .foregroundStyle(AppTheme.accent)
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 6)

        if #available(iOS 26.0, *) {
            pill.glassEffect(.regular.tint(AppTheme.accent.opacity(0.10)).interactive(), in: .capsule)
        } else {
            pill
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(AppTheme.accent.opacity(0.18), lineWidth: 0.5)
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
