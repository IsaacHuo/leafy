nonisolated struct CampusAICitation: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var url: String
    var siteName: String?
    var snippet: String?
    var summary: String?
    var publishedAt: String?
    var attachments: [CampusAIDeliverableAttachment]

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case url
        case siteName
        case siteNameSnake = "site_name"
        case snippet
        case summary
        case publishedAt
        case publishedAtSnake = "published_at"
        case attachments
    }

    init(
        id: String = UUID().uuidString,
        title: String,
        url: String,
        siteName: String? = nil,
        snippet: String? = nil,
        summary: String? = nil,
        publishedAt: String? = nil,
        attachments: [CampusAIDeliverableAttachment] = []
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.siteName = siteName
        self.snippet = snippet
        self.summary = summary
        self.publishedAt = publishedAt
        self.attachments = attachments
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        url = try container.decodeIfPresent(String.self, forKey: .url) ?? ""
        siteName = try container.decodeIfPresent(String.self, forKey: .siteName)
            ?? container.decodeIfPresent(String.self, forKey: .siteNameSnake)
        snippet = try container.decodeIfPresent(String.self, forKey: .snippet)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        publishedAt = try container.decodeIfPresent(String.self, forKey: .publishedAt)
            ?? container.decodeIfPresent(String.self, forKey: .publishedAtSnake)
        attachments = try container.decodeIfPresent([CampusAIDeliverableAttachment].self, forKey: .attachments) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(url, forKey: .url)
        try container.encodeIfPresent(siteName, forKey: .siteName)
        try container.encodeIfPresent(snippet, forKey: .snippet)
        try container.encodeIfPresent(summary, forKey: .summary)
        try container.encodeIfPresent(publishedAt, forKey: .publishedAt)
        try container.encode(attachments, forKey: .attachments)
    }
}

nonisolated private extension String {
    var nonEmptyTrimmed: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func clampedForAIContext(_ limit: Int = 240) -> String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(max(limit - 1, 0))) + "…"
    }
}

nonisolated enum CampusAIDeliverableFileFormat: String, Codable, CaseIterable, Hashable, Identifiable {
    case html
    case markdown
    case txt

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .html:
            return "HTML"
        case .markdown:
            return "Markdown"
        case .txt:
            return "TXT"
        }
    }

    var fileExtension: String {
        switch self {
        case .html:
            return "html"
        case .markdown:
            return "md"
        case .txt:
            return "txt"
        }
    }
}

nonisolated enum CampusAIArtifactFormatResolver {
    static func formats(for message: String) -> [CampusAIDeliverableFileFormat] {
        let text = message.lowercased()
        var formats: [CampusAIDeliverableFileFormat] = []
        if containsAny(text, ["html", "网页", "浏览器", "浏览", "网站"]) {
            formats.append(.html)
        }
        if containsAny(text, ["markdown", "md", "markdown 文件"]) {
            formats.append(.markdown)
        }
        if containsAny(text, ["txt", "文本", "纯文本"]) {
            formats.append(.txt)
        }
        return formats.isEmpty ? [.html] : CampusAIDeliverableFileFormat.allCases.filter { formats.contains($0) }
    }

    private static func containsAny(_ text: String, _ keywords: [String]) -> Bool {
        keywords.contains { text.contains($0) }
    }
}

nonisolated struct CampusAIArtifactContent: Codable, Hashable {
    var html: String?
    var markdown: String?
    var text: String?

    init(html: String? = nil, markdown: String? = nil, text: String? = nil) {
        self.html = html
        self.markdown = markdown
        self.text = text
    }

    func content(for format: CampusAIDeliverableFileFormat) -> String? {
        switch format {
        case .html:
            return html?.nonEmptyTrimmed
        case .markdown:
            return markdown?.nonEmptyTrimmed
        case .txt:
            return text?.nonEmptyTrimmed
        }
    }

    var availableFormats: [CampusAIDeliverableFileFormat] {
        CampusAIDeliverableFileFormat.allCases.filter { content(for: $0) != nil }
    }
}

nonisolated struct CampusAIDeliverableAttachment: Identifiable, Codable, Hashable {
    var title: String
    var url: String
    var fileType: String

    var id: String { url }

    enum CodingKeys: String, CodingKey {
        case title
        case url
        case fileType
        case fileTypeSnake = "file_type"
    }

    init(title: String, url: String, fileType: String) {
        self.title = title
        self.url = url
        self.fileType = fileType
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        url = try container.decodeIfPresent(String.self, forKey: .url) ?? ""
        fileType = try container.decodeIfPresent(String.self, forKey: .fileType)
            ?? container.decodeIfPresent(String.self, forKey: .fileTypeSnake)
            ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(url, forKey: .url)
        try container.encode(fileType, forKey: .fileType)
    }
}

nonisolated struct CampusAIDeliverableSource: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var url: String
    var siteName: String?
    var summary: String?
    var excerpt: String?
    var trustScore: Double
    var attachments: [CampusAIDeliverableAttachment]

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case url
        case siteName
        case siteNameSnake = "site_name"
        case summary
        case excerpt
        case trustScore
        case trustScoreSnake = "trust_score"
        case attachments
    }

    init(
        id: String = UUID().uuidString,
        title: String,
        url: String,
        siteName: String? = nil,
        summary: String? = nil,
        excerpt: String? = nil,
        trustScore: Double = 0,
        attachments: [CampusAIDeliverableAttachment] = []
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.siteName = siteName
        self.summary = summary
        self.excerpt = excerpt
        self.trustScore = trustScore
        self.attachments = attachments
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        url = try container.decodeIfPresent(String.self, forKey: .url) ?? ""
        siteName = try container.decodeIfPresent(String.self, forKey: .siteName)
            ?? container.decodeIfPresent(String.self, forKey: .siteNameSnake)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        excerpt = try container.decodeIfPresent(String.self, forKey: .excerpt)
        trustScore = try container.decodeIfPresent(Double.self, forKey: .trustScore)
            ?? container.decodeIfPresent(Double.self, forKey: .trustScoreSnake)
            ?? 0
        attachments = (try container.decodeIfPresent([CampusAIDeliverableAttachment].self, forKey: .attachments) ?? [])
            .filter { !$0.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(url, forKey: .url)
        try container.encodeIfPresent(siteName, forKey: .siteName)
        try container.encodeIfPresent(summary, forKey: .summary)
        try container.encodeIfPresent(excerpt, forKey: .excerpt)
        try container.encode(trustScore, forKey: .trustScore)
        try container.encode(attachments, forKey: .attachments)
    }
}

nonisolated struct CampusAIDeliverable: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var query: String
    var summary: String
    var generatedAt: String
    var sources: [CampusAIDeliverableSource]
    var formats: [CampusAIDeliverableFileFormat]
    var content: CampusAIArtifactContent?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case query
        case summary
        case generatedAt
        case generatedAtSnake = "generated_at"
        case sources
        case formats
        case content
    }

    init(
        id: String = UUID().uuidString,
        title: String,
        query: String,
        summary: String,
        generatedAt: String,
        sources: [CampusAIDeliverableSource],
        formats: [CampusAIDeliverableFileFormat] = CampusAIDeliverableFileFormat.allCases,
        content: CampusAIArtifactContent? = nil
    ) {
        self.id = id
        self.title = title
        self.query = query
        self.summary = summary
        self.generatedAt = generatedAt
        self.sources = sources
        self.formats = formats
        self.content = content
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        query = try container.decodeIfPresent(String.self, forKey: .query) ?? ""
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
        generatedAt = try container.decodeIfPresent(String.self, forKey: .generatedAt)
            ?? container.decodeIfPresent(String.self, forKey: .generatedAtSnake)
            ?? ""
        sources = (try container.decodeIfPresent([CampusAIDeliverableSource].self, forKey: .sources) ?? [])
            .filter { !$0.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        content = try container.decodeIfPresent(CampusAIArtifactContent.self, forKey: .content)
        let rawFormats = try container.decodeIfPresent([String].self, forKey: .formats) ?? []
        formats = rawFormats.compactMap { CampusAIDeliverableFileFormat(rawValue: $0.lowercased()) }
        if formats.isEmpty {
            formats = content?.availableFormats ?? CampusAIDeliverableFileFormat.allCases
        }
        if formats.isEmpty {
            formats = CampusAIDeliverableFileFormat.allCases
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(query, forKey: .query)
        try container.encode(summary, forKey: .summary)
        try container.encode(generatedAt, forKey: .generatedAt)
        try container.encode(sources, forKey: .sources)
        try container.encode(formats.map(\.rawValue), forKey: .formats)
        try container.encodeIfPresent(content, forKey: .content)
    }
}

nonisolated enum CampusAIDeliverableFileBuilder {
    static func cacheRoot(fileManager: FileManager = .default) throws -> URL {
        let caches = try fileManager.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return caches.appendingPathComponent("CampusAIArtifacts", isDirectory: true)
    }

    static func writeFile(
        for deliverable: CampusAIDeliverable,
        messageID: UUID,
        format: CampusAIDeliverableFileFormat,
        rootDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> URL {
        let root: URL
        if let rootDirectory {
            root = rootDirectory
        } else {
            root = try cacheRoot(fileManager: fileManager)
        }
        let directory = root.appendingPathComponent(messageID.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let fileName = sanitizedFileStem(deliverable.title.nonEmptyTrimmed ?? "CampusAIArtifacts")
            + "."
            + format.fileExtension
        let fileURL = directory.appendingPathComponent(fileName, isDirectory: false)
        try content(for: deliverable, format: format).write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    static func removeArtifacts(
        for messageID: UUID,
        rootDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) throws {
        let directory = try artifactsDirectory(
            for: messageID,
            rootDirectory: rootDirectory,
            fileManager: fileManager
        )
        guard fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.removeItem(at: directory)
    }

    static func removeAllArtifacts(
        rootDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) throws {
        let root: URL
        if let rootDirectory {
            root = rootDirectory
        } else {
            root = try cacheRoot(fileManager: fileManager)
        }
        guard fileManager.fileExists(atPath: root.path) else { return }
        try fileManager.removeItem(at: root)
    }

    static func pruneArtifacts(
        keeping messageIDs: Set<UUID>,
        rootDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) throws {
        let root: URL
        if let rootDirectory {
            root = rootDirectory
        } else {
            root = try cacheRoot(fileManager: fileManager)
        }
        guard fileManager.fileExists(atPath: root.path) else { return }
        let directories = try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        for directory in directories {
            let values = try directory.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true,
                  let id = UUID(uuidString: directory.lastPathComponent),
                  !messageIDs.contains(id)
            else { continue }
            try fileManager.removeItem(at: directory)
        }
    }

    static func content(for deliverable: CampusAIDeliverable, format: CampusAIDeliverableFileFormat) -> String {
        if let content = deliverable.content?.content(for: format) {
            return content
        }

        switch format {
        case .html:
            return htmlDocument(for: deliverable)
        case .markdown:
            return markdownDocument(for: deliverable)
        case .txt:
            return textDocument(for: deliverable)
        }
    }

    static func htmlDocument(for deliverable: CampusAIDeliverable) -> String {
        let sourceSections = deliverable.sources.enumerated().map { index, source in
            let attachments = source.attachments.isEmpty
                ? "<p class=\"muted\">未识别到附件链接。</p>"
                : """
                <ul class="attachments">
                \(source.attachments.map { attachment in
                    """
                    <li><a href="\(attributeEscape(attachment.url))">\(htmlEscape(attachment.title.nonEmptyTrimmed ?? attachment.url))</a><span>\(htmlEscape(attachment.fileType.uppercased()))</span></li>
                    """
                }.joined(separator: "\n"))
                </ul>
                """
            return """
            <section class="source">
              <h2>\(index + 1). <a href="\(attributeEscape(source.url))">\(htmlEscape(source.title.nonEmptyTrimmed ?? source.url))</a></h2>
              <p class="meta">\(htmlEscape([source.siteName?.nonEmptyTrimmed, scoreText(source.trustScore)].compactMap { $0 }.joined(separator: " · ")))</p>
              \(paragraphHTML(source.summary?.nonEmptyTrimmed ?? source.excerpt?.nonEmptyTrimmed))
              <h3>附件</h3>
              \(attachments)
            </section>
            """
        }.joined(separator: "\n")

        return """
        <!doctype html>
        <html lang="zh-CN">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>\(htmlEscape(deliverable.title.nonEmptyTrimmed ?? "学校官方资料卡片"))</title>
          <style>
            body { font: -apple-system-body; margin: 0; padding: 28px; color: #17201a; background: #fbfdfb; }
            main { max-width: 820px; margin: 0 auto; }
            header { border-bottom: 1px solid #dfe7df; padding-bottom: 18px; margin-bottom: 20px; }
            h1 { font-size: 28px; line-height: 1.2; margin: 0 0 12px; }
            h2 { font-size: 18px; line-height: 1.35; margin: 0 0 8px; }
            h3 { font-size: 14px; margin: 14px 0 8px; color: #4f6557; }
            p { line-height: 1.62; }
            a { color: #216e45; text-decoration-thickness: 0.08em; }
            .meta, .muted { color: #68766c; font-size: 13px; }
            .source { background: #ffffff; border: 1px solid #dfe7df; border-radius: 14px; padding: 16px; margin: 14px 0; }
            .attachments { padding-left: 20px; margin: 6px 0 0; }
            .attachments li { margin: 7px 0; }
            .attachments span { display: inline-block; margin-left: 8px; color: #68766c; font-size: 12px; }
          </style>
        </head>
        <body>
          <main>
            <header>
              <h1>\(htmlEscape(deliverable.title.nonEmptyTrimmed ?? "学校官方资料卡片"))</h1>
              <p class="meta">查询：\(htmlEscape(deliverable.query))</p>
              <p class="meta">生成时间：\(htmlEscape(deliverable.generatedAt))</p>
              \(paragraphHTML(deliverable.summary.nonEmptyTrimmed))
            </header>
            \(sourceSections.isEmpty ? "<p class=\"muted\">未找到可交付的官方来源。</p>" : sourceSections)
          </main>
        </body>
        </html>
        """
    }

    static func markdownDocument(for deliverable: CampusAIDeliverable) -> String {
        let sources = deliverable.sources.enumerated().map { index, source in
            let attachments = source.attachments.isEmpty
                ? "- 附件：未识别到附件链接"
                : source.attachments.map {
                    "- 附件：[\(markdownEscape($0.title.nonEmptyTrimmed ?? $0.url))](\($0.url))（\($0.fileType.uppercased())）"
                }.joined(separator: "\n")
            return """
            \(index + 1). [\(markdownEscape(source.title.nonEmptyTrimmed ?? source.url))](\(source.url))
               - 来源：\([source.siteName?.nonEmptyTrimmed, scoreText(source.trustScore)].compactMap { $0 }.joined(separator: " · "))
               - 摘要：\(markdownEscape(source.summary?.nonEmptyTrimmed ?? source.excerpt?.nonEmptyTrimmed ?? "暂无摘要"))
            \(attachments.split(separator: "\n").map { "   \($0)" }.joined(separator: "\n"))
            """
        }.joined(separator: "\n\n")

        return """
        # \(markdownEscape(deliverable.title.nonEmptyTrimmed ?? "学校官方资料卡片"))

        - 查询：\(markdownEscape(deliverable.query))
        - 生成时间：\(markdownEscape(deliverable.generatedAt))

        \(markdownEscape(deliverable.summary.nonEmptyTrimmed ?? "已整理官方来源和附件链接。"))

        ## 官方来源

        \(sources.isEmpty ? "未找到可交付的官方来源。" : sources)
        """
    }

    static func textDocument(for deliverable: CampusAIDeliverable) -> String {
        let sources = deliverable.sources.enumerated().map { index, source in
            let attachments = source.attachments.isEmpty
                ? "附件：未识别到附件链接"
                : source.attachments.map { "附件：\($0.title.nonEmptyTrimmed ?? $0.url) [\($0.fileType.uppercased())]\n\($0.url)" }.joined(separator: "\n")
            return """
            \(index + 1). \(source.title.nonEmptyTrimmed ?? source.url)
            \(source.url)
            \([source.siteName?.nonEmptyTrimmed, scoreText(source.trustScore)].compactMap { $0 }.joined(separator: " · "))
            \(source.summary?.nonEmptyTrimmed ?? source.excerpt?.nonEmptyTrimmed ?? "暂无摘要")
            \(attachments)
            """
        }.joined(separator: "\n\n")

        return """
        \(deliverable.title.nonEmptyTrimmed ?? "学校官方资料卡片")

        查询：\(deliverable.query)
        生成时间：\(deliverable.generatedAt)

        \(deliverable.summary.nonEmptyTrimmed ?? "已整理官方来源和附件链接。")

        官方来源
        \(sources.isEmpty ? "未找到可交付的官方来源。" : sources)
        """
    }

    private static func sanitizedFileStem(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
        let scalars = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let collapsed = String(scalars)
            .replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "- "))
        return String((collapsed.nonEmptyTrimmed ?? "CampusAIArtifacts").prefix(64))
    }

    private static func artifactsDirectory(
        for messageID: UUID,
        rootDirectory: URL?,
        fileManager: FileManager
    ) throws -> URL {
        let root: URL
        if let rootDirectory {
            root = rootDirectory
        } else {
            root = try cacheRoot(fileManager: fileManager)
        }
        return root.appendingPathComponent(messageID.uuidString, isDirectory: true)
    }

    private static func paragraphHTML(_ value: String?) -> String {
        guard let value else { return "" }
        return "<p>\(htmlEscape(value))</p>"
    }

    private static func scoreText(_ score: Double) -> String {
        "可信度 \(Int((max(0, min(score, 1)) * 100).rounded()))%"
    }

    private static func htmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func attributeEscape(_ value: String) -> String {
        htmlEscape(value)
    }

    private static func markdownEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
    }
}

nonisolated enum CampusAILocalArtifactBuilder {
    static func deliverables(for request: CampusAIRequest, answer: String) -> [CampusAIDeliverable] {
        guard request.capabilities.artifactGenerationEnabled,
              request.outputMode == .artifact,
              !request.localRetrieval.results.isEmpty
        else {
            return []
        }

        let sources = request.localRetrieval.results.prefix(12).map { result in
            CampusAIDeliverableSource(
                id: "local-\(result.id)",
                title: result.title.nonEmptyTrimmed ?? result.domain.title,
                url: "leafy://local/\(result.domain.rawValue)/\(result.sourceID)",
                siteName: "Leafy \(result.domain.title)",
                summary: result.summary.nonEmptyTrimmed,
                excerpt: nil,
                trustScore: 1,
                attachments: []
            )
        }
        guard !sources.isEmpty else { return [] }

        return [
            CampusAIDeliverable(
                id: "local-deliverable-\(request.requestID.uuidString)",
                title: artifactTitle(for: request.message),
                query: request.message,
                summary: artifactSummary(answer: answer),
                generatedAt: ISO8601DateFormatter().string(from: Date()),
                sources: sources,
                formats: CampusAIArtifactFormatResolver.formats(for: request.message),
                content: CampusAIArtifactContent(markdown: answer)
            )
        ]
    }

    private static func artifactTitle(for message: String) -> String {
        let base = message
            .replacingOccurrences(of: #"[\r\n\t]+"#, with: " ", options: .regularExpression)
            .clampedForAIContext(32)
        return "\(base.nonEmptyTrimmed ?? "本地资料")卡片"
    }

    private static func artifactSummary(answer: String) -> String {
        answer.nonEmptyTrimmed?.clampedForAIContext(240) ?? "已根据相关资料整理为可打开的卡片。"
    }
}

nonisolated struct CampusAIAgentTraceStep: Identifiable, Codable, Hashable {
    var id: String
    var kind: String
    var title: String
    var detail: String?
    var status: String
    var tool: String?
    var role: String?
    var timestamp: String?
}

nonisolated struct CampusAIAgentToolEvent: Codable, Hashable {
    var name: String
    var status: String
    var detail: String?
    var resultCount: Int?

    enum CodingKeys: String, CodingKey {
        case name
        case status
        case detail
        case resultCount
        case resultCountSnake = "result_count"
    }

    init(name: String, status: String, detail: String? = nil, resultCount: Int? = nil) {
        self.name = name
        self.status = status
        self.detail = detail
        self.resultCount = resultCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? ""
        detail = try container.decodeIfPresent(String.self, forKey: .detail)
        resultCount = try container.decodeIfPresent(Int.self, forKey: .resultCount)
            ?? container.decodeIfPresent(Int.self, forKey: .resultCountSnake)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(detail, forKey: .detail)
        try container.encodeIfPresent(resultCount, forKey: .resultCount)
    }
}

nonisolated struct CampusAISearchResultPreview: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var url: String
    var siteName: String?
}

nonisolated enum CampusAIAgentPresentation {
    static func toolStatusText(_ tool: CampusAIAgentToolEvent) -> String {
        let title = toolTitle(for: tool.name)

        switch tool.status {
        case "running":
            return "\(title)正在调用"
        case "completed":
            if let resultCount = tool.resultCount, resultCount > 0 {
                return "\(title)调用完成，找到 \(resultCount) 条结果"
            }
            return "\(title)调用完成"
        case "failed":
            return "\(title)调用失败，继续生成回答"
        case "skipped":
            return "\(title)已跳过"
        default:
            return title
        }
    }

    static func sanitizedStatusText(_ text: String) -> String {
        var result = text
        let replacements = [
            "official_search": "搜索工具",
            "web_search": "搜索工具",
            "read_web_page": "网页读取工具",
            "read_pdf": "PDF 读取工具",
            "read_spreadsheet": "Excel 读取工具"
        ]
        for (internalName, displayName) in replacements {
            result = result.replacingOccurrences(of: internalName, with: displayName)
        }
        result = result.replacingOccurrences(of: "搜索工具完成", with: "搜索工具调用完成")
        return result
    }

    private static func toolTitle(for name: String) -> String {
        switch name {
        case "official_search", "web_search", "official.document.search":
            return "搜索工具"
        case "read_web_page":
            return "网页读取工具"
        case "read_pdf":
            return "PDF 读取工具"
        case "read_spreadsheet":
            return "Excel 读取工具"
        case "completion.plan":
            return "整理工具"
        case "delegate.subtask":
            return "子任务"
        default:
            return "工具"
        }
    }
}

nonisolated struct CampusAIMessageAgentMetadata: Codable, Hashable {
    var statusText: String?
    var citations: [CampusAICitation]
    var searchResults: [CampusAISearchResultPreview]
    var agentTrace: [CampusAIAgentTraceStep]
    var deliverables: [CampusAIDeliverable]
    var artifactState: CampusAIArtifactGenerationState
    var artifactErrorMessage: String?

    static let empty = CampusAIMessageAgentMetadata()

    enum CodingKeys: String, CodingKey {
        case statusText
        case statusTextSnake = "status_text"
        case citations
        case searchResults
        case searchResultsSnake = "search_results"
        case agentTrace
        case agentTraceSnake = "agent_trace"
        case deliverables
        case artifactState
        case artifactStateSnake = "artifact_state"
        case artifactErrorMessage
        case artifactErrorMessageSnake = "artifact_error_message"
    }

    init(
        statusText: String? = nil,
        citations: [CampusAICitation] = [],
        searchResults: [CampusAISearchResultPreview] = [],
        agentTrace: [CampusAIAgentTraceStep] = [],
        deliverables: [CampusAIDeliverable] = [],
        artifactState: CampusAIArtifactGenerationState = .none,
        artifactErrorMessage: String? = nil
    ) {
        self.statusText = statusText
        self.citations = citations
        self.searchResults = searchResults
        self.agentTrace = agentTrace
        self.deliverables = deliverables
        self.artifactState = artifactState
        self.artifactErrorMessage = artifactErrorMessage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        statusText = try container.decodeIfPresent(String.self, forKey: .statusText)
            ?? container.decodeIfPresent(String.self, forKey: .statusTextSnake)
        citations = try container.decodeIfPresent([CampusAICitation].self, forKey: .citations) ?? []
        searchResults = try container.decodeIfPresent([CampusAISearchResultPreview].self, forKey: .searchResults)
            ?? container.decodeIfPresent([CampusAISearchResultPreview].self, forKey: .searchResultsSnake)
            ?? []
        agentTrace = try container.decodeIfPresent([CampusAIAgentTraceStep].self, forKey: .agentTrace)
            ?? container.decodeIfPresent([CampusAIAgentTraceStep].self, forKey: .agentTraceSnake)
            ?? []
        deliverables = try container.decodeIfPresent([CampusAIDeliverable].self, forKey: .deliverables) ?? []
        artifactState = try container.decodeIfPresent(CampusAIArtifactGenerationState.self, forKey: .artifactState)
            ?? container.decodeIfPresent(CampusAIArtifactGenerationState.self, forKey: .artifactStateSnake)
            ?? (deliverables.isEmpty ? .none : .ready)
        artifactErrorMessage = try container.decodeIfPresent(String.self, forKey: .artifactErrorMessage)
            ?? container.decodeIfPresent(String.self, forKey: .artifactErrorMessageSnake)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(statusText, forKey: .statusText)
        try container.encode(citations, forKey: .citations)
        try container.encode(searchResults, forKey: .searchResults)
        try container.encode(agentTrace, forKey: .agentTrace)
        try container.encode(deliverables, forKey: .deliverables)
        try container.encode(artifactState, forKey: .artifactState)
        try container.encodeIfPresent(artifactErrorMessage, forKey: .artifactErrorMessage)
    }
}

nonisolated struct CampusAIResponse: Codable, Hashable {
    var answer: String
    var reasoning: String
    var finishReason: String?
    var suggestedTitle: String?
    var summary: String?
    var actions: [CampusAIActionDraft]
    var citations: [CampusAICitation]
    var agentTrace: [CampusAIAgentTraceStep]
    var deliverables: [CampusAIDeliverable]
    var artifactState: CampusAIArtifactGenerationState
    var artifactErrorMessage: String?

    enum CodingKeys: String, CodingKey {
        case answer
        case reasoning
        case finishReason = "finish_reason"
        case suggestedTitle = "suggested_title"
        case summary
        case actions
        case citations
        case agentTrace
        case agentTraceSnake = "agent_trace"
        case deliverables
        case artifactState
        case artifactStateSnake = "artifact_state"
        case artifactErrorMessage
        case artifactErrorMessageSnake = "artifact_error_message"
    }

    init(
        answer: String,
        reasoning: String = "",
        finishReason: String? = nil,
        suggestedTitle: String? = nil,
        summary: String? = nil,
        actions: [CampusAIActionDraft] = [],
        citations: [CampusAICitation] = [],
        agentTrace: [CampusAIAgentTraceStep] = [],
        deliverables: [CampusAIDeliverable] = [],
        artifactState: CampusAIArtifactGenerationState = .none,
        artifactErrorMessage: String? = nil
    ) {
        self.answer = answer
        self.reasoning = reasoning
        self.finishReason = finishReason
        self.suggestedTitle = suggestedTitle
        self.summary = summary
        self.actions = CampusAIActionValidation.validated(actions)
        self.citations = citations.filter { !$0.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        self.agentTrace = agentTrace
        self.deliverables = deliverables
        self.artifactState = artifactState
        self.artifactErrorMessage = artifactErrorMessage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        answer = try container.decodeIfPresent(String.self, forKey: .answer) ?? ""
        reasoning = try container.decodeIfPresent(String.self, forKey: .reasoning) ?? ""
        finishReason = try container.decodeIfPresent(String.self, forKey: .finishReason)
        suggestedTitle = try container.decodeIfPresent(String.self, forKey: .suggestedTitle)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        actions = CampusAIActionValidation.validated(
            try container.decodeIfPresent([CampusAIActionDraft].self, forKey: .actions) ?? []
        )
        citations = (try container.decodeIfPresent([CampusAICitation].self, forKey: .citations) ?? [])
            .filter { !$0.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        agentTrace = try container.decodeIfPresent([CampusAIAgentTraceStep].self, forKey: .agentTrace)
            ?? container.decodeIfPresent([CampusAIAgentTraceStep].self, forKey: .agentTraceSnake)
            ?? []
        deliverables = try container.decodeIfPresent([CampusAIDeliverable].self, forKey: .deliverables) ?? []
        artifactState = try container.decodeIfPresent(CampusAIArtifactGenerationState.self, forKey: .artifactState)
            ?? container.decodeIfPresent(CampusAIArtifactGenerationState.self, forKey: .artifactStateSnake)
            ?? (deliverables.isEmpty ? .none : .ready)
        artifactErrorMessage = try container.decodeIfPresent(String.self, forKey: .artifactErrorMessage)
            ?? container.decodeIfPresent(String.self, forKey: .artifactErrorMessageSnake)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(answer, forKey: .answer)
        try container.encode(reasoning, forKey: .reasoning)
        try container.encodeIfPresent(finishReason, forKey: .finishReason)
        try container.encodeIfPresent(suggestedTitle, forKey: .suggestedTitle)
        try container.encodeIfPresent(summary, forKey: .summary)
        try container.encode(actions, forKey: .actions)
        try container.encode(citations, forKey: .citations)
        try container.encode(agentTrace, forKey: .agentTrace)
        try container.encode(deliverables, forKey: .deliverables)
        try container.encode(artifactState, forKey: .artifactState)
        try container.encodeIfPresent(artifactErrorMessage, forKey: .artifactErrorMessage)
    }
}

nonisolated struct CampusAIQuotaSnapshot: Codable, Hashable {
    var planSource: String
    var limit: Int
    var used: Int
    var remaining: Int
    var resetAt: String
    var status: String
    var dailyLimit: Int
    var dailyUsed: Int
    var dailyRemaining: Int
    var dailyResetAt: String
    var periodLimit: Int?
    var periodUsed: Int?
    var periodRemaining: Int?
    var periodResetAt: String?

    enum CodingKeys: String, CodingKey {
        case planSource = "plan_source"
        case limit
        case used
        case remaining
        case resetAt = "reset_at"
        case status
        case dailyLimit = "daily_limit"
        case dailyUsed = "daily_used"
        case dailyRemaining = "daily_remaining"
        case dailyResetAt = "daily_reset_at"
        case periodLimit = "period_limit"
        case periodUsed = "period_used"
        case periodRemaining = "period_remaining"
        case periodResetAt = "period_reset_at"
    }

    init(
        planSource: String,
        limit: Int,
        used: Int,
        remaining: Int,
        resetAt: String,
        status: String,
        dailyLimit: Int? = nil,
        dailyUsed: Int? = nil,
        dailyRemaining: Int? = nil,
        dailyResetAt: String? = nil,
        periodLimit: Int? = nil,
        periodUsed: Int? = nil,
        periodRemaining: Int? = nil,
        periodResetAt: String? = nil
    ) {
        self.planSource = planSource
        self.limit = limit
        self.used = used
        self.remaining = remaining
        self.resetAt = resetAt
        self.status = status
        self.dailyLimit = dailyLimit ?? limit
        self.dailyUsed = dailyUsed ?? used
        self.dailyRemaining = dailyRemaining ?? remaining
        self.dailyResetAt = dailyResetAt ?? resetAt
        self.periodLimit = periodLimit
        self.periodUsed = periodUsed
        self.periodRemaining = periodRemaining
        self.periodResetAt = periodResetAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        planSource = try container.decodeIfPresent(String.self, forKey: .planSource) ?? "free"
        limit = try container.decodeIfPresent(Int.self, forKey: .limit) ?? 10
        used = try container.decodeIfPresent(Int.self, forKey: .used) ?? 0
        remaining = try container.decodeIfPresent(Int.self, forKey: .remaining) ?? max(limit - used, 0)
        resetAt = try container.decodeIfPresent(String.self, forKey: .resetAt) ?? ""
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? planSource
        dailyLimit = try container.decodeIfPresent(Int.self, forKey: .dailyLimit) ?? limit
        dailyUsed = try container.decodeIfPresent(Int.self, forKey: .dailyUsed) ?? used
        dailyRemaining = try container.decodeIfPresent(Int.self, forKey: .dailyRemaining) ?? remaining
        dailyResetAt = try container.decodeIfPresent(String.self, forKey: .dailyResetAt) ?? resetAt
        periodLimit = try container.decodeIfPresent(Int.self, forKey: .periodLimit)
        periodUsed = try container.decodeIfPresent(Int.self, forKey: .periodUsed)
        periodRemaining = try container.decodeIfPresent(Int.self, forKey: .periodRemaining)
        periodResetAt = try container.decodeIfPresent(String.self, forKey: .periodResetAt)
    }

    var displayText: String {
        "\(remaining)/\(limit)"
    }
}
import Foundation
