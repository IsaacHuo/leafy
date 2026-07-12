import Foundation
import WebKit

@MainActor
final class CampusAIArtifactExportService {
    func export(
        _ artifact: CampusAIDeliverable,
        messageID: UUID,
        format: CampusAIArtifactExportFormat
    ) async throws -> URL {
        let markdown = try canonicalMarkdown(for: artifact)
        let directory = try exportDirectory(messageID: messageID)
        let filename = sanitizedFilename(artifact.title.nonEmptyTrimmed ?? "Leafy Artifact")
        let fileURL = directory
            .appendingPathComponent(filename)
            .appendingPathExtension(format.fileExtension)

        switch format {
        case .markdown:
            try Data(markdown.utf8).write(to: fileURL, options: .atomic)
        case .html:
            let html: String
            if CampusAIStaticArtifactDocument.requiresRichRenderer(markdown) {
                let renderer = CampusAIArtifactWebRenderer()
                try await renderer.render(markdown: markdown)
                html = try await renderer.staticHTML(inlineCSS: try rendererCSS())
            } else {
                html = CampusAIStaticArtifactDocument.html(
                    markdown: markdown,
                    inlineCSS: try rendererCSS()
                )
            }
            guard !Self.containsExecutableScript(html) else {
                throw CampusAIArtifactExportError.unsafeHTML
            }
            try Data(html.utf8).write(to: fileURL, options: .atomic)
        case .plainText:
            let text: String
            if CampusAIStaticArtifactDocument.requiresRichRenderer(markdown) {
                let renderer = CampusAIArtifactWebRenderer()
                try await renderer.render(markdown: markdown)
                text = try await renderer.plainText()
            } else {
                text = CampusAIStaticArtifactDocument.plainText(markdown: markdown)
            }
            try Data(text.utf8).write(to: fileURL, options: .atomic)
        }
        return fileURL
    }

    static func containsExecutableScript(_ html: String) -> Bool {
        html.range(of: #"<\s*script\b"#, options: [.regularExpression, .caseInsensitive]) != nil
            || html.range(of: #"\son[a-z]+\s*="#, options: [.regularExpression, .caseInsensitive]) != nil
            || html.range(of: #"javascript\s*:"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private func canonicalMarkdown(for artifact: CampusAIDeliverable) throws -> String {
        guard let markdown = artifact.content?.markdown?.nonEmptyTrimmed else {
            throw CampusAIArtifactExportError.missingMarkdown
        }
        return markdown
    }

    private func exportDirectory(messageID: UUID) throws -> URL {
        let root = try CampusAIDeliverableFileBuilder.cacheRoot()
            .appendingPathComponent("Exports", isDirectory: true)
            .appendingPathComponent(messageID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func rendererCSS() throws -> String {
        guard let directory = CampusAIMarkdownHTML.rendererDirectory() else {
            throw CampusAIArtifactExportError.rendererUnavailable
        }
        let names = ["renderer.css", "katex.min.css"]
        return try names.map { name in
            let url = directory.appendingPathComponent(name)
            return try String(contentsOf: url, encoding: .utf8)
        }.joined(separator: "\n")
    }

    private func sanitizedFilename(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>\n\r\t")
        let scalars = value.unicodeScalars.map { invalid.contains($0) ? "-" : String($0) }
        let candidate = scalars.joined()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String((candidate.nonEmptyTrimmed ?? "Leafy Artifact").prefix(80))
    }
}

private enum CampusAIArtifactExportError: LocalizedError {
    case missingMarkdown
    case rendererUnavailable
    case renderingFailed
    case unsafeHTML

    var errorDescription: String? {
        switch self {
        case .missingMarkdown:
            return "这个成品缺少可导出的 Markdown 原文。"
        case .rendererUnavailable:
            return "成品渲染资源不可用。"
        case .renderingFailed:
            return "成品渲染失败，请重试。"
        case .unsafeHTML:
            return "HTML 清理失败，已停止导出。"
        }
    }
}

private nonisolated enum CampusAIStaticArtifactDocument {
    static func requiresRichRenderer(_ markdown: String) -> Bool {
        let lowercased = markdown.lowercased()
        return lowercased.contains("```mermaid")
            || markdown.contains("$$")
            || markdown.contains("\\[")
            || markdown.contains("\\(")
    }

    static func html(markdown: String, inlineCSS: String) -> String {
        let body = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .map(blockHTML)
            .joined(separator: "\n")
        return """
        <!doctype html>
        <html lang="zh-Hans">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src https: data:">
          <style>\(inlineCSS)</style>
        </head>
        <body><main id="content">\(body)</main></body>
        </html>
        """
    }

    static func plainText(markdown: String) -> String {
        markdown
            .replacingOccurrences(of: #"(?m)^#{1,6}\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?m)^\s*[-*+]\s+"#, with: "• ", options: .regularExpression)
            .replacingOccurrences(of: #"`{1,3}"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\*\*([^*]+)\*\*"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"\[([^\]]+)\]\([^\)]+\)"#, with: "$1", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func blockHTML(_ line: String) -> String {
        let escaped = inlineHTML(line.trimmingCharacters(in: .whitespaces))
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if let match = trimmed.wholeMatch(of: /^(#{1,6})\s+(.+)$/) {
            let level = match.1.count
            return "<h\(level)>\(inlineHTML(String(match.2)))</h\(level)>"
        }
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
            return "<p class=\"list-item\">• \(inlineHTML(String(trimmed.dropFirst(2))))</p>"
        }
        if trimmed.isEmpty { return "" }
        return "<p>\(escaped)</p>"
    }

    private static func inlineHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
            .replacingOccurrences(of: #"\*\*([^*]+)\*\*"#, with: "<strong>$1</strong>", options: .regularExpression)
            .replacingOccurrences(of: #"`([^`]+)`"#, with: "<code>$1</code>", options: .regularExpression)
    }
}

@MainActor
private final class CampusAIArtifactWebRenderer: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private var navigationContinuation: CheckedContinuation<Void, Error>?
    private var navigationOperationID: UUID?

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 794, height: 1123), configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = .white
        webView.scrollView.backgroundColor = .white
    }

    func render(markdown: String) async throws {
        guard CampusAIMarkdownHTML.hasRequiredResources() else {
            throw CampusAIArtifactExportError.rendererUnavailable
        }
        try await loadHTML(
            CampusAIMarkdownHTML.baseDocument,
            baseURL: CampusAIMarkdownHTML.rendererDirectory()
        )

        _ = try await webView.callAsyncJavaScript(
            """
            window.LeafyMarkdown.render(markdown);
            await new Promise(resolve => window.setTimeout(resolve, 120));
            return true;
            """,
            arguments: ["markdown": markdown],
            in: nil,
            contentWorld: .page
        )

        var previousHeight: Double = 0
        var stablePasses = 0
        for _ in 0..<20 {
            try Task.checkCancellation()
            let state = try await renderState()
            if abs(state.height - previousHeight) < 1, state.pendingMermaid == 0 {
                stablePasses += 1
                if stablePasses >= 2 { return }
            } else {
                stablePasses = 0
            }
            previousHeight = state.height
            try await Task.sleep(for: .milliseconds(100))
        }
        guard (try await renderState()).height > 0 else {
            throw CampusAIArtifactExportError.renderingFailed
        }
    }

    func staticHTML(inlineCSS: String) async throws -> String {
        let result = try await webView.callAsyncJavaScript(
            """
            const clone = document.documentElement.cloneNode(true);
            clone.querySelectorAll('script, link, button').forEach(node => node.remove());
            clone.querySelectorAll('*').forEach(node => {
              Array.from(node.attributes).forEach(attribute => {
                const name = attribute.name.toLowerCase();
                const value = String(attribute.value || '').toLowerCase();
                if (name.startsWith('on') || value.includes('javascript:')) {
                  node.removeAttribute(attribute.name);
                }
              });
            });
            const style = document.createElement('style');
            style.textContent = css;
            clone.querySelector('head').appendChild(style);
            const meta = clone.querySelector('meta[http-equiv="Content-Security-Policy"]');
            if (meta) meta.setAttribute('content', "default-src 'none'; style-src 'unsafe-inline'; img-src https: data:; font-src data:");
            return '<!doctype html>\\n' + clone.outerHTML;
            """,
            arguments: ["css": inlineCSS],
            in: nil,
            contentWorld: .page
        )
        guard let html = result as? String, !html.isEmpty else {
            throw CampusAIArtifactExportError.renderingFailed
        }
        return html
    }

    func plainText() async throws -> String {
        let result = try await webView.callAsyncJavaScript(
            "return document.getElementById('content').innerText || '';",
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        guard let text = result as? String, !text.isEmpty else {
            throw CampusAIArtifactExportError.renderingFailed
        }
        return text
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        navigationContinuation?.resume()
        navigationContinuation = nil
        navigationOperationID = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        navigationContinuation?.resume(throwing: error)
        navigationContinuation = nil
        navigationOperationID = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        navigationContinuation?.resume(throwing: error)
        navigationContinuation = nil
        navigationOperationID = nil
    }

    private func loadHTML(_ html: String, baseURL: URL?) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let operationID = UUID()
            navigationOperationID = operationID
            navigationContinuation = continuation
            webView.loadHTMLString(html, baseURL: baseURL)
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(15))
                guard let self, self.navigationOperationID == operationID else { return }
                self.navigationContinuation?.resume(throwing: CampusAIArtifactExportError.renderingFailed)
                self.navigationContinuation = nil
                self.navigationOperationID = nil
                self.webView.stopLoading()
            }
        }
    }

    private func renderState() async throws -> (height: Double, pendingMermaid: Int) {
        let result = try await webView.callAsyncJavaScript(
            """
            return {
              height: Math.max(document.body.scrollHeight, document.documentElement.scrollHeight),
              pendingMermaid: document.querySelectorAll('.mermaid-diagram:not(.rendered)').length
            };
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        guard let dictionary = result as? [String: Any] else {
            throw CampusAIArtifactExportError.renderingFailed
        }
        let height = (dictionary["height"] as? NSNumber)?.doubleValue ?? 0
        let pending = (dictionary["pendingMermaid"] as? NSNumber)?.intValue ?? 0
        return (height, pending)
    }
}

private extension String {
    var nonEmptyTrimmed: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
