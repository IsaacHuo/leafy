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
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var isProcessExpanded = false
    @State private var copied = false
    @State private var copyFeedbackSignal = 0

    let message: CampusAIMessage
    let actions: [CampusAIActionRecord]
    let isStreaming: Bool
    let interactionsDisabled: Bool
    let executeAction: (CampusAIActionRecord) -> Void
    let cancelAction: (CampusAIActionRecord) -> Void
    let edit: () -> Void
    let regenerate: () -> Void
    let rewind: () -> Void

    private var isUser: Bool {
        message.roleRawValue == CampusAIMessageRole.user.rawValue
    }

    private var answerText: String {
        message.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var agentMetadata: CampusAIMessageAgentMetadata {
        message.agentMetadata
    }

    private var progressSearchResults: [CampusAISearchResultPreview] {
        var results = agentMetadata.searchResults
        var seenURLs = Set(results.map(\.url))
        for citation in agentMetadata.citations where seenURLs.insert(citation.url).inserted {
            results.append(CampusAISearchResultPreview(
                id: "citation-\(citation.id)",
                title: citation.title,
                url: citation.url,
                siteName: citation.siteName
            ))
        }
        return results
    }

    private var citationAttachments: [CampusAIDeliverableAttachment] {
        var seenURLs = Set<String>()
        return agentMetadata.citations
            .flatMap(\.attachments)
            .filter { seenURLs.insert($0.url).inserted }
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
            if isUser, !interactionsDisabled {
                Button(action: edit) {
                    Label("重新编辑", systemImage: "pencil")
                }
            }
            if !isUser && !interactionsDisabled {
                Button(action: regenerate) {
                    Label(regenerateTitle, systemImage: "arrow.clockwise")
                }
                Button(action: rewind) {
                    Label("回到上一阶段", systemImage: "arrow.uturn.backward")
                }
            }
        }
        .campusAIInAppBrowser()
        .sensoryFeedback(.success, trigger: copyFeedbackSignal)
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
        } else {
            VStack(alignment: .leading, spacing: 10) {
                if answerText.isEmpty {
                    CampusAITypingDots()
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(AppTheme.softFill, in: Capsule())
                } else {
                    CampusAIMessageMarkdown(
                        markdown: message.text,
                        citationURLs: agentMetadata.citations.map(\.url),
                        isStreaming: isStreaming
                    )
                }

                if isStreaming || !agentMetadata.agentTrace.isEmpty || !progressSearchResults.isEmpty {
                    CampusAIAgentProgressView(
                        steps: agentMetadata.agentTrace,
                        statusText: agentMetadata.statusText,
                        searchResults: progressSearchResults,
                        isStreaming: isStreaming,
                        isExpanded: $isProcessExpanded
                    )
                }

                if !citationAttachments.isEmpty {
                    CampusAIAttachmentPillList(attachments: citationAttachments)
                }

                if !isStreaming,
                   agentMetadata.citations.isEmpty,
                   agentMetadata.agentTrace.contains(where: { step in
                       ["official_search", "web_search", "read_web_page", "read_pdf", "read_spreadsheet"].contains(step.tool ?? "")
                   }) {
                    Label("未引用已验证来源", systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
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
                    CampusAIActionList(
                        actions: actions,
                        executeAction: executeAction,
                        cancelAction: cancelAction
                    )
                    .padding(.top, 2)
                }

                if !isStreaming {
                    HStack(spacing: 0) {
                        messageActionButton(
                            systemName: copied ? "checkmark" : "doc.on.doc",
                            accessibilityLabel: copied ? "已复制" : "复制回复",
                            action: copyMessage
                        )

                        messageActionButton(
                            systemName: "arrow.clockwise",
                            accessibilityLabel: regenerateTitle,
                            action: regenerate
                        )
                        .disabled(interactionsDisabled)

                        messageActionButton(
                            systemName: "arrow.uturn.backward",
                            accessibilityLabel: "回到上一阶段",
                            action: rewind
                        )
                        .disabled(interactionsDisabled)

                        Spacer(minLength: 0)
                    }
                    .padding(.top, -6)
                    .padding(.leading, -6)
                }
            }
            .font(.body)
            .foregroundStyle(AppTheme.primaryText)
            .padding(.vertical, 4)
            .multilineTextAlignment(.leading)
        }
    }

    private var regenerateTitle: String {
        agentMetadata.artifactState == .failed ? "重试生成卡片" : "重新生成"
    }

    private func messageActionButton(
        systemName: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppTheme.secondaryText)
                .frame(width: 40, height: 38)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private func copyMessage() {
        let copyText = isUser
            ? message.text
            : CampusAIMarkdownNormalizer.normalize(
                message.text,
                removingCitationURLs: agentMetadata.citations.map(\.url)
            )
        #if os(iOS)
        UIPasteboard.general.string = copyText
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(copyText, forType: .string)
        #endif
        copied = true
        copyFeedbackSignal += 1
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            guard !accessibilityReduceMotion else {
                copied = false
                return
            }
            withAnimation(.easeOut(duration: 0.16)) {
                copied = false
            }
        }
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

private struct CampusAIAgentProgressView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.openURL) private var openURL

    let steps: [CampusAIAgentTraceStep]
    let statusText: String?
    let searchResults: [CampusAISearchResultPreview]
    let isStreaming: Bool
    @Binding var isExpanded: Bool

    var body: some View {
        Group {
            if isStreaming {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(steps.suffix(4))) { step in
                        stepRow(step)
                    }
                    if let statusText = statusText?.nonEmptyTrimmed {
                        HStack(alignment: .center, spacing: 7) {
                            ProgressView()
                                .controlSize(.mini)
                                .frame(width: 14, height: 14, alignment: .center)
                            Text(CampusAIAgentPresentation.sanitizedStatusText(statusText))
                                .lineLimit(2)
                        }
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .animation(
                    accessibilityReduceMotion ? nil : .easeOut(duration: 0.18),
                    value: steps.map(\.id) + [statusText ?? ""]
                )
            } else if !steps.isEmpty || !searchResults.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Button {
                        if accessibilityReduceMotion {
                            isExpanded.toggle()
                        } else {
                            withAnimation(.easeOut(duration: 0.18)) {
                                isExpanded.toggle()
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Label("已完成 \(steps.count) 步", systemImage: "checklist")
                                .font(.caption.weight(.medium))

                            Spacer(minLength: 8)

                            Image(systemName: "chevron.down")
                                .font(.caption.weight(.semibold))
                                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        }
                        .foregroundStyle(AppTheme.secondaryText)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if isExpanded {
                        VStack(alignment: .leading, spacing: 7) {
                        ForEach(steps) { step in
                            stepRow(step)
                        }

                            if !searchResults.isEmpty {
                                searchResultList
                                    .padding(.top, 3)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                        .transition(.opacity)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(AppTheme.softFill.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func stepRow(_ step: CampusAIAgentTraceStep) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: step.status == "failed" ? "exclamationmark.circle" : "checkmark.circle")
                .font(.caption2)
            VStack(alignment: .leading, spacing: 1) {
                Text(step.title)
                    .font(.caption)
                if let detail = step.detail?.nonEmptyTrimmed {
                    Text(detail)
                        .font(.caption2)
                        .lineLimit(2)
                }
            }
        }
        .foregroundStyle(step.status == "failed" ? AppTheme.warning : AppTheme.secondaryText)
    }

    private var searchResultList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("找到的结果")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)

            ForEach(searchResults) { result in
                Button {
                    guard let url = URL(string: result.url) else { return }
                    openURL(url)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Image(systemName: "link")
                            .font(.caption2.weight(.semibold))

                        VStack(alignment: .leading, spacing: 1) {
                            Text(result.title.nonEmptyTrimmed ?? result.url)
                                .font(.caption)
                                .lineLimit(2)
                            if let siteName = result.siteName?.nonEmptyTrimmed {
                                Text(siteName)
                                    .font(.caption2)
                                    .foregroundStyle(AppTheme.secondaryText)
                                    .lineLimit(1)
                            }
                        }

                        Spacer(minLength: 4)

                        Image(systemName: "arrow.up.right")
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(AppTheme.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("在应用内打开")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CampusAIAttachmentPillList: View {
    @Environment(\.openURL) private var openURL

    let attachments: [CampusAIDeliverableAttachment]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(attachments.prefix(12)) { attachment in
                pill(attachment)
            }
        }
    }

    @ViewBuilder
    private func pill(_ attachment: CampusAIDeliverableAttachment) -> some View {
        if let url = URL(string: attachment.url), ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            Button {
                openURL(url)
            } label: {
                pillContent(attachment)
            }
            .buttonStyle(.plain)
            .accessibilityHint("在应用内打开")
        } else {
            pillContent(attachment)
        }
    }

    private func pillContent(_ attachment: CampusAIDeliverableAttachment) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "paperclip")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(attachment.title.nonEmptyTrimmed ?? attachment.url)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(attachment.fileType.nonEmptyTrimmed?.uppercased() ?? "附件")
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
}

private struct CampusAIActionList: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    let actions: [CampusAIActionRecord]
    let executeAction: (CampusAIActionRecord) -> Void
    let cancelAction: (CampusAIActionRecord) -> Void
    @State private var expandedCompletedActionIDs: Set<UUID> = []
    @Namespace private var transitionNamespace

    private var visibleActions: [CampusAIActionRecord] {
        actions.filter { CampusAIActionPresentationPolicy.isVisible($0.status) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(visibleActions) { action in
                CampusAIActionCard(
                    action: action,
                    isExpanded: action.status != .completed || expandedCompletedActionIDs.contains(action.id),
                    transitionNamespace: transitionNamespace,
                    executeAction: executeAction,
                    cancelAction: cancelAction,
                    toggleCompleted: { toggleCompleted(action.id) }
                )
                .transition(
                    accessibilityReduceMotion
                        ? .opacity
                        : .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .bottomLeading)),
                            removal: .opacity.combined(with: .scale(scale: 0.85, anchor: .bottomLeading))
                        )
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(
            accessibilityReduceMotion ? .easeOut(duration: 0.14) : .spring(response: 0.3, dampingFraction: 0.88),
            value: actions.map { "\($0.id.uuidString):\($0.status.rawValue)" }
        )
    }

    private func toggleCompleted(_ id: UUID) {
        withAnimation(accessibilityReduceMotion ? .easeOut(duration: 0.14) : .spring(response: 0.3, dampingFraction: 0.88)) {
            if expandedCompletedActionIDs.contains(id) {
                expandedCompletedActionIDs.remove(id)
            } else {
                expandedCompletedActionIDs.insert(id)
            }
        }
    }
}

private struct CampusAIActionCard: View {
    let action: CampusAIActionRecord
    let isExpanded: Bool
    let transitionNamespace: Namespace.ID
    let executeAction: (CampusAIActionRecord) -> Void
    let cancelAction: (CampusAIActionRecord) -> Void
    let toggleCompleted: () -> Void

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
        Group {
            if action.status == .completed, !isExpanded {
                collapsedCompletedButton
            } else {
                expandedCard
            }
        }
        .matchedGeometryEffect(id: action.id, in: transitionNamespace)
    }

    private var expandedCard: some View {
        HStack(spacing: 4) {
            Button(action: primaryAction) {
                HStack(spacing: 10) {
                    actionIcon

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(action.title.nonEmptyTrimmed ?? kindTitle)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.primaryText)
                                .lineLimit(1)

                            Text(statusText)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(statusForeground)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(statusForeground.opacity(0.1), in: Capsule())
                        }

                        Text(action.detail.nonEmptyTrimmed ?? kindTitle)
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    if isPending {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(AppTheme.tertiaryText)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(action.status == .failed)

            if isPending {
                Button {
                    cancelAction(action)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                        .frame(width: 36, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("忽略动作")
            }
        }
        .padding(.leading, 11)
        .padding(.trailing, isPending ? 4 : 11)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .background(AppTheme.softFill.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var collapsedCompletedButton: some View {
        Button(action: toggleCompleted) {
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: 36, height: 36)
                .background(Color.green, in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("已执行，展开动作详情")
    }

    private var actionIcon: some View {
        Image(systemName: iconName)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(AppTheme.accent)
            .frame(width: 30, height: 30)
            .background(AppTheme.accent.opacity(0.12), in: Circle())
    }

    private func primaryAction() {
        switch action.status {
        case .pending:
            executeAction(action)
        case .completed:
            toggleCompleted()
        case .cancelled, .failed:
            break
        }
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
    let citationURLs: [String]
    let isStreaming: Bool

    var body: some View {
        let document = CampusAIResponseDocument(markdown: markdown, citationURLs: citationURLs)
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(document.blocks.enumerated()), id: \.offset) { _, block in
                CampusAIResponseBlockView(block: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct CampusAIResponseBlockView: View {
    let block: CampusAIResponseDocument.Block

    var body: some View {
        switch block {
        case .heading(let level, let text):
            inlineText(text)
                .font(headingFont(level))
                .padding(.top, level == 1 ? 3 : 1)
        case .paragraph(let text):
            inlineText(text)
                .font(.body)
                .lineSpacing(3)
        case .unorderedList(let items):
            list(items: items, ordered: false)
        case .orderedList(let items):
            list(items: items, ordered: true)
        case .quote(let text):
            HStack(alignment: .top, spacing: 10) {
                Capsule()
                    .fill(AppTheme.accent.opacity(0.45))
                    .frame(width: 3)
                inlineText(text)
                    .font(.callout)
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineSpacing(2)
            }
        case .code(let language, let source):
            VStack(alignment: .leading, spacing: 6) {
                if let language {
                    Text(language)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(source)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            .padding(12)
            .background(AppTheme.softFill.opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        case .table(let headers, let rows):
            ScrollView(.horizontal, showsIndicators: false) {
                Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                    GridRow {
                        ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
                            tableCell(header, isHeader: true, isShaded: true)
                        }
                    }
                    ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                        GridRow {
                            ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                                tableCell(cell, isHeader: false, isShaded: rowIndex.isMultiple(of: 2))
                            }
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(AppTheme.separator.opacity(0.55), lineWidth: 0.5)
                }
            }
        }
    }

    private func list(items: [String], ordered: Bool) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Text(ordered ? "\(index + 1)." : "•")
                        .font(.body.weight(ordered ? .regular : .semibold))
                        .foregroundStyle(ordered ? AppTheme.secondaryText : AppTheme.primaryText)
                        .frame(minWidth: 16, alignment: .trailing)
                    inlineText(item)
                        .font(.body)
                        .lineSpacing(2)
                }
            }
        }
    }

    private func tableCell(_ markdown: String, isHeader: Bool, isShaded: Bool) -> some View {
        inlineText(markdown)
            .font(isHeader ? .subheadline.weight(.semibold) : .subheadline)
            .lineSpacing(2)
            .frame(minWidth: 112, maxWidth: 220, minHeight: 24, alignment: .leading)
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(isShaded ? AppTheme.softFill.opacity(0.72) : Color.clear)
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(AppTheme.separator.opacity(0.45))
                    .frame(width: 0.5)
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(AppTheme.separator.opacity(0.45))
                    .frame(height: 0.5)
            }
    }

    private func inlineText(_ markdown: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: markdown,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attributed)
        }
        return Text(markdown)
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1:
            return .title2.weight(.semibold)
        case 2:
            return .headline
        default:
            return .subheadline.weight(.semibold)
        }
    }
}

private extension String {
    var nonEmptyTrimmed: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
