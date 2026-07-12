import SwiftUI

struct CampusAIArtifactCard: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Namespace private var transitionNamespace

    let deliverable: CampusAIDeliverable
    let messageID: UUID

    private var markdown: String {
        deliverable.content?.markdown?.nonEmptyTrimmed ?? ""
    }

    private var sections: [CampusAIArtifactSectionPreview] {
        CampusAIArtifactSectionPreview.parse(markdown).prefix(3).map { $0 }
    }

    var body: some View {
        NavigationLink {
            CampusAIArtifactReaderView(deliverable: deliverable, messageID: messageID)
                .campusAIArtifactZoomDestination(
                    id: deliverable.id,
                    namespace: transitionNamespace,
                    reduceMotion: accessibilityReduceMotion
                )
        } label: {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "doc.richtext.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 36, height: 36)
                        .background(AppTheme.accent.opacity(0.11), in: Circle())

                    VStack(alignment: .leading, spacing: 5) {
                        Text(deliverable.title.nonEmptyTrimmed ?? "Leafy 成品")
                            .font(.headline)
                            .foregroundStyle(AppTheme.primaryText)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(deliverable.summary.nonEmptyTrimmed ?? "已整理为可阅读和导出的成品。")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryText)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 4)

                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.tertiaryText)
                        .frame(width: 28, height: 28)
                }

                if !sections.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(sections) { section in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(section.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppTheme.primaryText)
                                    .lineLimit(1)
                                if let excerpt = section.excerpt {
                                    Text(excerpt)
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.secondaryText)
                                        .lineLimit(2)
                                }
                            }
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.cardElevated.opacity(0.78), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                }

                HStack(spacing: 8) {
                    Label(sourceText, systemImage: deliverable.sources.isEmpty ? "iphone" : "externaldrive")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.secondaryText)

                    Spacer(minLength: 8)

                    Text("打开成品")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [AppTheme.accent.opacity(0.10), AppTheme.softFill.opacity(0.60)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(AppTheme.accent.opacity(0.16), lineWidth: 0.8)
            }
            .shadow(color: AppTheme.accent.opacity(0.06), radius: 16, y: 7)
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .campusAIArtifactZoomSource(
                id: deliverable.id,
                namespace: transitionNamespace,
                reduceMotion: accessibilityReduceMotion
            )
        }
        .buttonStyle(.plain)
    }

    private var sourceText: String {
        deliverable.sources.isEmpty ? "未附加本机条目" : "引用 \(deliverable.sources.count) 条本机数据"
    }
}

struct CampusAIArtifactFailureView: View {
    let message: String?
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("成品整理失败", systemImage: "exclamationmark.triangle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.danger)

            Text(message?.nonEmptyTrimmed ?? "回答已保留，可以单独重试生成成品。")
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Button("重试生成成品", action: retry)
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .tint(AppTheme.accent)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.danger.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct CampusAIArtifactReaderView: View {
    let deliverable: CampusAIDeliverable
    let messageID: UUID

    @State private var isExporting = false
    @State private var shareItem: CampusAIArtifactShareItem?
    @State private var exportError: String?
    @State private var failedFormat: CampusAIArtifactExportFormat?
    @State private var isSourceSheetPresented = false

    private var markdown: String {
        deliverable.content?.markdown?.nonEmptyTrimmed ?? ""
    }

    var body: some View {
        Group {
            if markdown.isEmpty {
                ContentUnavailableView(
                    "成品内容不可用",
                    systemImage: "doc.badge.ellipsis",
                    description: Text("这条旧记录没有保存 Markdown 原文。")
                )
            } else {
                CampusAIMarkdownWebView(markdown: markdown, mode: .document)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(AppTheme.cardElevated)
        .navigationTitle(deliverable.title.nonEmptyTrimmed ?? "Leafy 成品")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !deliverable.sources.isEmpty {
                    Button {
                        isSourceSheetPresented = true
                    } label: {
                        Label("来源", systemImage: "info.circle")
                    }
                }

                Menu {
                    ForEach(CampusAIArtifactExportFormat.allCases) { format in
                        Button {
                            Task { await export(format) }
                        } label: {
                            Label(format.title, systemImage: format.systemImage)
                        }
                    }
                } label: {
                    Label("分享", systemImage: isExporting ? "clock" : "square.and.arrow.up")
                }
                .disabled(isExporting || markdown.isEmpty)
            }
        }
        .sheet(item: $shareItem) { item in
            LeafySystemShare(activityItems: [item.url])
        }
        .sheet(isPresented: $isSourceSheetPresented) {
            CampusAIArtifactSourcesSheet(deliverable: deliverable)
        }
        .alert("导出失败", isPresented: exportErrorBinding) {
            if let failedFormat {
                Button("重试") {
                    Task { await export(failedFormat) }
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(exportError ?? "请稍后重试。")
        }
    }

    private var exportErrorBinding: Binding<Bool> {
        Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )
    }

    @MainActor
    private func export(_ format: CampusAIArtifactExportFormat) async {
        guard !isExporting else { return }
        isExporting = true
        exportError = nil
        defer { isExporting = false }
        do {
            let url = try await CampusAIArtifactExportService().export(
                deliverable,
                messageID: messageID,
                format: format
            )
            failedFormat = nil
            shareItem = CampusAIArtifactShareItem(url: url)
        } catch {
            CampusAIDiagnostics.failure(error, stage: "artifact.export", requestID: messageID)
            failedFormat = format
            exportError = error.localizedDescription
        }
    }
}

private struct CampusAIArtifactSourcesSheet: View {
    @Environment(\.dismiss) private var dismiss
    let deliverable: CampusAIDeliverable

    var body: some View {
        NavigationStack {
            List {
                Section("数据范围") {
                    LabeledContent("生成时间", value: deliverable.generatedAt.nonEmptyTrimmed ?? "未知")
                    LabeledContent("本机条目", value: "\(deliverable.sources.count) 条")
                }

                Section("本机来源") {
                    ForEach(deliverable.sources) { source in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(source.title.nonEmptyTrimmed ?? "本机数据")
                                .font(.body.weight(.medium))
                            if let summary = source.summary?.nonEmptyTrimmed {
                                Text(summary)
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.secondaryText)
                                    .lineLimit(3)
                            }
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
            .navigationTitle("成品来源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct CampusAIArtifactShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct CampusAIArtifactSectionPreview: Identifiable {
    let id: Int
    let title: String
    let excerpt: String?

    static func parse(_ markdown: String) -> [CampusAIArtifactSectionPreview] {
        let lines = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        var result: [CampusAIArtifactSectionPreview] = []

        for (index, line) in lines.enumerated() {
            guard let match = line.wholeMatch(of: /^(#{1,3})\s+(.+)$/) else { continue }
            let title = String(match.2).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            let excerpt = lines.dropFirst(index + 1)
                .first(where: { candidate in
                    let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
                    return !trimmed.isEmpty && !trimmed.hasPrefix("#") && !trimmed.hasPrefix("```")
                })?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: #"^[\-*+>]\s*"#, with: "", options: .regularExpression)
            result.append(
                CampusAIArtifactSectionPreview(
                    id: index,
                    title: title,
                    excerpt: excerpt.map { String($0.prefix(120)) }
                )
            )
        }
        return result
    }
}

private extension View {
    @ViewBuilder
    func campusAIArtifactZoomSource(
        id: String,
        namespace: Namespace.ID,
        reduceMotion: Bool
    ) -> some View {
        if #available(iOS 18.0, *), !reduceMotion {
            matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }

    @ViewBuilder
    func campusAIArtifactZoomDestination(
        id: String,
        namespace: Namespace.ID,
        reduceMotion: Bool
    ) -> some View {
        if #available(iOS 18.0, *), !reduceMotion {
            navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            self
        }
    }
}

private extension String {
    var nonEmptyTrimmed: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
