import SwiftData
import SwiftUI

struct CampusAIChatTopBar: View {
    @Environment(\.leafyThemeColorPreference) private var themeColorPreference

    let settings: CampusAIUserSettings
    let quotaSnapshot: CampusAIQuotaSnapshot?
    let configuredProviderIDs: Set<CampusAIProviderID>
    let openHistory: () -> Void
    let openSettings: () -> Void
    let newConversation: () -> Void
    let selectServiceMode: (CampusAIServiceMode) -> Void

    var body: some View {
        LeafyGlassGroup(spacing: AppSpacing.micro) {
            HStack(spacing: AppSpacing.compact) {
                iconButton(
                    systemName: "line.3.horizontal",
                    accessibilityLabel: "打开历史记录",
                    action: openHistory
                )

                iconButton(
                    systemName: "gearshape",
                    accessibilityLabel: "打开 Leafy 设置",
                    action: openSettings
                )

                serviceModeSelector

                Spacer(minLength: AppSpacing.micro)

                iconButton(
                    systemName: "plus",
                    accessibilityLabel: "新建对话",
                    action: newConversation
                )
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
                    systemImage: settings.serviceMode == .leafyManaged ? "checkmark" : "sparkles"
                )
            }

            Button {
                selectServiceMode(.ownAPIKey)
            } label: {
                Label(
                    CampusAIServiceMode.ownAPIKey.title,
                    systemImage: settings.serviceMode == .ownAPIKey ? "checkmark" : "key.fill"
                )
            }
            .disabled(!configuredProviderIDs.contains(settings.selectedProviderID))
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(settings.serviceMode.shortTitle)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(AppTheme.tertiaryText)
                }

                if settings.serviceMode == .leafyManaged, let quotaSnapshot {
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
        .accessibilityLabel("当前 AI 服务 \(settings.serviceMode.title)")
    }

    private func iconButton(
        systemName: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppTheme.accent(for: themeColorPreference))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .leafyGlassSurface(in: Circle(), isInteractive: true)
    }
}

struct CampusAIHistoryPanel: View {
    @Environment(\.leafyThemeColorPreference) private var themeColorPreference

    let conversations: [CampusAIConversation]
    let selectedConversationID: UUID?
    let onSelectConversation: (CampusAIConversation) -> Void
    let onDeleteConversation: (CampusAIConversation) -> Void
    let onClearHistory: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if conversations.isEmpty {
                        ContentUnavailableView("暂无历史", systemImage: "clock")
                            .padding(.top, AppSpacing.card)
                    } else {
                        ForEach(conversations) { conversation in
                            CampusAIHistoryRow(
                                conversation: conversation,
                                isSelected: selectedConversationID == conversation.id,
                                selectConversation: {
                                    onSelectConversation(conversation)
                                },
                                deleteConversation: {
                                    onDeleteConversation(conversation)
                                }
                            )
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

    private var header: some View {
        HStack(spacing: AppSpacing.micro) {
            Text("历史记录")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.primaryText)
                .lineLimit(1)

            Spacer(minLength: AppSpacing.micro)

            Button(role: .destructive, action: onClearHistory) {
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
    }
}

private struct CampusAIHistoryRow: View {
    @Environment(\.leafyThemeColorPreference) private var themeColorPreference

    let conversation: CampusAIConversation
    let isSelected: Bool
    let selectConversation: () -> Void
    let deleteConversation: () -> Void

    var body: some View {
        Button(action: selectConversation) {
            VStack(alignment: .leading, spacing: 4) {
                Text(titleText)
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
                isSelected
                    ? AppTheme.accent(for: themeColorPreference).opacity(0.12)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive, action: deleteConversation) {
                Label("删除对话", systemImage: "trash")
            }
        }
    }

    private var titleText: String {
        let trimmed = conversation.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "新的对话" : trimmed
    }
}

struct CampusAIEmptyConversationPanel: View {
    @Environment(\.leafyThemeColorPreference) private var themeColorPreference

    let prompts: [String]
    let selectPrompt: (String) -> Void

    var body: some View {
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

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppSpacing.micro) {
                ForEach(prompts, id: \.self) { prompt in
                    CampusAIPromptSuggestionButton(title: prompt) {
                        selectPrompt(prompt)
                    }
                }
            }
            .frame(maxWidth: 560)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct CampusAIPromptSuggestionButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.compact) {
                Text(title)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(AppTheme.primaryText)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                    .allowsTightening(true)

                Spacer()

                Image(systemName: "arrow.up.left")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.tertiaryText)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 12)
            .frame(minHeight: 48)
            .background(
                AppTheme.softFill,
                in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }
}

struct CampusAIComposerBar: View {
    @Environment(\.leafyThemeColorPreference) private var themeColorPreference

    @Binding var draftText: String
    let isFocused: FocusState<Bool>.Binding
    let settings: CampusAIUserSettings
    let isSending: Bool
    let canSend: Bool
    let submit: () -> Void
    let cancelStreaming: () -> Void
    let toggleWebSearch: () -> Void

    private var isWebSearchActive: Bool {
        settings.serviceMode == .leafyManaged && settings.webSearchEnabled
    }

    var body: some View {
        LeafyGlassGroup(spacing: AppSpacing.micro) {
            HStack(alignment: .bottom, spacing: 10) {
                webSearchToggleButton
                    .padding(.leading, 8)
                    .padding(.bottom, 7)

                TextField("功能仍在测试，不作功能保证。", text: $draftText, axis: .vertical)
                    .focused(isFocused)
                    .lineLimit(1...5)
                    .textFieldStyle(.plain)
                    .submitLabel(.send)
                    .onSubmit(submit)
                    .padding(.leading, 2)
                    .padding(.trailing, 8)
                    .padding(.vertical, 14)

                Button(action: sendButtonAction) {
                    Image(systemName: isSending ? "stop.fill" : "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle((canSend || isSending) ? AppTheme.textOnAccent(for: themeColorPreference) : AppTheme.tertiaryText)
                        .frame(width: 34, height: 34)
                        .background(
                            (canSend || isSending)
                                ? AppTheme.accent(for: themeColorPreference)
                                : AppTheme.accent(for: themeColorPreference).opacity(0.16),
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
        Button(action: toggleWebSearch) {
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
                    : AppTheme.softFill.opacity(settings.serviceMode == .leafyManaged ? 0.95 : 0.48),
                in: Capsule()
            )
            .opacity(settings.serviceMode == .leafyManaged ? 1 : 0.58)
        }
        .buttonStyle(.plain)
        .disabled(settings.serviceMode != .leafyManaged || isSending)
        .accessibilityLabel(isWebSearchActive ? "关闭联网搜索" : "开启联网搜索")
        .accessibilityValue(isWebSearchActive ? "已开启" : "已关闭")
    }

    private func sendButtonAction() {
        if isSending {
            cancelStreaming()
        } else {
            submit()
        }
    }
}
