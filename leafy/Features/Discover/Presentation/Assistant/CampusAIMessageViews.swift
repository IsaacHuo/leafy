import SwiftUI
import WebKit

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
                            CampusAIDeliverableCard(
                                deliverable: deliverable,
                                messageID: message.id
                            )
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

}

struct CampusAITypingRow: View {
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

    @State private var previewItem: CampusAIArtifactPreviewItem?

    private var availableFormats: [CampusAIDeliverableFileFormat] {
        let formats = deliverable.formats.isEmpty ? [.html] : deliverable.formats
        return CampusAIDeliverableFileFormat.allCases.filter { formats.contains($0) }
    }

    var body: some View {
        Button {
            previewItem = CampusAIArtifactPreviewItem(
                deliverable: deliverable,
                messageID: messageID,
                initialFormat: availableFormats.first ?? .html
            )
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "doc.richtext")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 30, height: 30)
                    .background(AppTheme.accent.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 7) {
                    Text(deliverable.title.nonEmptyTrimmed ?? "学校官方资料包")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(deliverable.summary.nonEmptyTrimmed ?? "已整理官方来源和附件链接。")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 6) {
                        Text(sourceCountText)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(AppTheme.secondaryText)

                        ForEach(availableFormats) { format in
                            Text(format.displayTitle)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(AppTheme.accent)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(AppTheme.accent.opacity(0.1), in: Capsule())
                        }
                    }
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.tertiaryText)
                    .frame(width: 20, height: 30)
            }
        }
        .buttonStyle(.plain)
        .padding(13)
        .background(AppTheme.softFill.opacity(0.72), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .sheet(item: $previewItem) { item in
            CampusAIArtifactPreviewSheet(item: item)
        }
    }

    private var sourceCountText: String {
        switch deliverable.sources.count {
        case 0:
            return "无来源"
        case 1:
            return "1 个来源"
        default:
            return "\(deliverable.sources.count) 个来源"
        }
    }
}

private struct CampusAIArtifactPreviewItem: Identifiable {
    let id = UUID()
    let deliverable: CampusAIDeliverable
    let messageID: UUID
    let initialFormat: CampusAIDeliverableFileFormat
}

private struct CampusAIArtifactPreviewSheet: View {
    let item: CampusAIArtifactPreviewItem

    @State private var selectedFormat: CampusAIDeliverableFileFormat
    @State private var fileURL: URL?
    @State private var contentText = ""
    @State private var errorText: String?
    @State private var isCopiedAlertPresented = false

    init(item: CampusAIArtifactPreviewItem) {
        self.item = item
        _selectedFormat = State(initialValue: item.initialFormat)
    }

    private var availableFormats: [CampusAIDeliverableFileFormat] {
        let formats = item.deliverable.formats.isEmpty ? [.html] : item.deliverable.formats
        return CampusAIDeliverableFileFormat.allCases.filter { formats.contains($0) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if availableFormats.count > 1 {
                    Picker("Artifact 格式", selection: $selectedFormat) {
                        ForEach(availableFormats) { format in
                            Text(format.displayTitle).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, AppSpacing.page)
                    .padding(.vertical, AppSpacing.compact)

                    Divider().opacity(0.24)
                }

                previewContent
            }
            .background(AppTheme.cardElevated)
            .task(id: selectedFormat) {
                loadSelectedFormat()
            }
            .navigationTitle(item.deliverable.title.nonEmptyTrimmed ?? selectedFormat.displayTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        copyCurrentContent()
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .disabled(contentText.isEmpty)
                    .accessibilityLabel("复制 Artifact 内容")

                    if let fileURL {
                        ShareLink(item: fileURL) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("分享 Artifact")
                    }
                }
            }
            .alert("已复制", isPresented: $isCopiedAlertPresented) {
                Button("好", role: .cancel) {}
            }
        }
    }

    @ViewBuilder
    private var previewContent: some View {
        if let errorText {
            CampusAITextArtifactPreview(text: errorText, isError: true)
        } else {
            switch selectedFormat {
            case .html:
                if let fileURL {
                    CampusAIHTMLArtifactPreview(url: fileURL)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            case .markdown:
                ScrollView {
                    CampusAIMarkdownWebView(markdown: contentText)
                        .padding(AppSpacing.page)
                }
            case .txt:
                CampusAITextArtifactPreview(text: contentText, isError: false)
            }
        }
    }

    private func loadSelectedFormat() {
        do {
            contentText = CampusAIDeliverableFileBuilder.content(
                for: item.deliverable,
                format: selectedFormat
            )
            fileURL = try CampusAIDeliverableFileBuilder.writeFile(
                for: item.deliverable,
                messageID: item.messageID,
                format: selectedFormat
            )
            errorText = nil
        } catch {
            contentText = ""
            fileURL = nil
            errorText = error.localizedDescription
        }
    }

    private func copyCurrentContent() {
        Self.copyToPasteboard(contentText)
        isCopiedAlertPresented = true
    }

    private static func copyToPasteboard(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}

private struct CampusAIHTMLArtifactPreview: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }
}

private struct CampusAITextArtifactPreview: View {
    let text: String
    let isError: Bool

    var body: some View {
        ScrollView {
            Text(text)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(isError ? AppTheme.danger : AppTheme.primaryText)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(AppSpacing.page)
        }
        .background(AppTheme.cardElevated)
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
        if isStreaming {
            CampusAIMarkdownFallbackText(markdown: markdown)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            CampusAIMarkdownWebView(markdown: markdown)
        }
    }
}

private extension String {
    var nonEmptyTrimmed: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
