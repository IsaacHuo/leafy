import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

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

struct CampusAIMessageRow: View {
    @Environment(\.leafyThemeColorPreference) private var themeColorPreference

    let message: CampusAIMessage
    let actions: [CampusAIActionRecord]
    let isStreaming: Bool
    let executeAction: (CampusAIActionRecord) -> Void
    let cancelAction: (CampusAIActionRecord) -> Void
    let regenerate: () -> Void

    private var isUser: Bool {
        message.roleRawValue == CampusAIMessageRole.user.rawValue
    }

    private var answerText: String {
        message.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var agentMetadata: CampusAIMessageAgentMetadata {
        message.agentMetadata
    }

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.compact) {
            if isUser {
                Spacer(minLength: 46)
            }

            messageContent
                .frame(maxWidth: isUser ? 420 : 680, alignment: isUser ? .trailing : .leading)

            if !isUser {
                Spacer(minLength: 24)
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .contextMenu {
            Button(action: copyMessage) {
                Label("复制", systemImage: "doc.on.doc")
            }
            if !isUser && !isStreaming {
                Button(action: regenerate) {
                    Label(regenerateTitle, systemImage: "arrow.clockwise")
                }
            }
        }
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
        } else if answerText.isEmpty {
            CampusAITypingDots()
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(AppTheme.softFill, in: Capsule())
        } else {
            VStack(alignment: .leading, spacing: 10) {
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

                if !agentMetadata.citations.isEmpty {
                    CampusAISourceAttachmentPillList(
                        citations: agentMetadata.citations,
                        deliverables: []
                    )
                }

                if !agentMetadata.deliverables.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(agentMetadata.deliverables) { deliverable in
                            CampusAIArtifactCard(
                                deliverable: deliverable,
                                messageID: message.id
                            )
                        }
                    }
                }

                if agentMetadata.artifactState == .failed {
                    CampusAIArtifactFailureView(
                        message: agentMetadata.artifactErrorMessage,
                        retry: regenerate
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

    private var regenerateTitle: String {
        agentMetadata.artifactState == .failed ? "重试生成成品" : "重新生成"
    }

    private func copyMessage() {
        #if os(iOS)
        UIPasteboard.general.string = message.text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.text, forType: .string)
        #endif
    }
}

struct CampusAITypingRow: View {
    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.compact) {
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

private struct CampusAIActionCard: View {
    let action: CampusAIActionRecord
    let executeAction: (CampusAIActionRecord) -> Void
    let cancelAction: (CampusAIActionRecord) -> Void

    private var isPending: Bool {
        action.status == .pending
    }

    private var toolDescriptor: CampusAIToolDescriptor? {
        CampusAIToolRegistry.descriptor(for: action.kind)
    }

    private var kindTitle: String {
        toolDescriptor?.title ?? "待确认动作"
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
        toolDescriptor?.systemImageName ?? "sparkles"
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
        CampusAIMarkdownFallbackText(markdown: markdown)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private extension String {
    var nonEmptyTrimmed: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
