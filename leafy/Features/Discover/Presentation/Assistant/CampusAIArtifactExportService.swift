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
            let renderer = CampusAIArtifactWebRenderer()
            try await renderer.render(markdown: markdown)
            let html = try await renderer.staticHTML(inlineCSS: try rendererCSS())
            guard !Self.containsExecutableScript(html) else {
                throw CampusAIArtifactExportError.unsafeHTML
            }
            try Data(html.utf8).write(to: fileURL, options: .atomic)
        case .plainText:
            let renderer = CampusAIArtifactWebRenderer()
            try await renderer.render(markdown: markdown)
            let text = try await renderer.plainText()
            try Data(text.utf8).write(to: fileURL, options: .atomic)
        case .pdf:
            let renderer = CampusAIArtifactWebRenderer()
            try await renderer.render(markdown: markdown)
            let data = try await renderer.pdfData()
            guard data.starts(with: Data("%PDF".utf8)) else {
                throw CampusAIArtifactExportError.invalidPDF
            }
            try data.write(to: fileURL, options: .atomic)
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
    case invalidPDF

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
        case .invalidPDF:
            return "PDF 生成失败，请重试。"
        }
    }
}

@MainActor
private final class CampusAIArtifactWebRenderer: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private var navigationContinuation: CheckedContinuation<Void, Error>?

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
        try await withCheckedThrowingContinuation { continuation in
            navigationContinuation = continuation
            webView.loadHTMLString(
                CampusAIMarkdownHTML.baseDocument,
                baseURL: CampusAIMarkdownHTML.rendererDirectory()
            )
        }

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

    func pdfData() async throws -> Data {
        let height = max(webView.scrollView.contentSize.height, 1123)
        let configuration = WKPDFConfiguration()
        configuration.rect = CGRect(x: 0, y: 0, width: 794, height: height)
        return try await webView.pdf(configuration: configuration)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        navigationContinuation?.resume()
        navigationContinuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        navigationContinuation?.resume(throwing: error)
        navigationContinuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        navigationContinuation?.resume(throwing: error)
        navigationContinuation = nil
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

private extension WKWebView {
    func pdf(configuration: WKPDFConfiguration) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            createPDF(configuration: configuration) { result in
                continuation.resume(with: result)
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
