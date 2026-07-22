import Foundation

nonisolated enum CampusAIMarkdownNormalizer {
    static func normalize(_ markdown: String, removingCitationURLs citationURLs: [String] = []) -> String {
        let citationKeys = Set(citationURLs.compactMap(citationURLKey))
        let sourceLines = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        var normalizedLines: [String] = []
        var protectedLines: [Bool] = []
        var activeFence: String?

        for sourceLine in sourceLines {
            let trimmed = sourceLine.trimmingCharacters(in: .whitespaces)
            let fence = fenceMarker(in: trimmed)
            let isProtected = activeFence != nil || fence != nil
            var line = sourceLine

            if !isProtected {
                line = line.replacingOccurrences(
                    of: "(?<=[0-9０-９])\\s*~~\\s*(?=[0-9０-９])",
                    with: "–",
                    options: .regularExpression
                )
                line = normalizeTablePipes(in: line)
                if !citationKeys.isEmpty {
                    line = removeCitationLinks(in: line, citationKeys: citationKeys)
                }
            }

            normalizedLines.append(line)
            protectedLines.append(isProtected)

            if let currentFence = activeFence {
                if trimmed.hasPrefix(currentFence) {
                    activeFence = nil
                }
            } else if let fence {
                activeFence = fence
            }
        }

        return repairStrictTables(lines: normalizedLines, protectedLines: protectedLines)
            .joined(separator: "\n")
    }

    private static func fenceMarker(in line: String) -> String? {
        if line.hasPrefix("```") { return "```" }
        if line.hasPrefix("~~~") { return "~~~" }
        return nil
    }

    private static func normalizeTablePipes(in line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard (trimmed.hasPrefix("|") || trimmed.hasPrefix("｜")),
              (trimmed.hasSuffix("|") || trimmed.hasSuffix("｜"))
        else { return line }
        let normalizedPipes = line.replacingOccurrences(of: "｜", with: "|")
        let normalizedDashes = normalizedPipes
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "－", with: "-")
        if let cells = strictTableCells(in: normalizedDashes), isTableSeparator(cells) {
            return normalizedDashes
        }
        return normalizedPipes
    }

    private static func repairStrictTables(lines: [String], protectedLines: [Bool]) -> [String] {
        var result: [String] = []
        var index = 0

        while index < lines.count {
            guard !protectedLines[index],
                  let header = strictTableCells(in: lines[index]),
                  index + 1 < lines.count,
                  !protectedLines[index + 1],
                  let next = strictTableCells(in: lines[index + 1]),
                  header.count == next.count
            else {
                result.append(lines[index])
                index += 1
                continue
            }

            var end = index + 2
            while end < lines.count,
                  !protectedLines[end],
                  let cells = strictTableCells(in: lines[end]),
                  cells.count == header.count {
                end += 1
            }

            result.append(lines[index])
            if !isTableSeparator(next) {
                result.append("| " + Array(repeating: "---", count: header.count).joined(separator: " | ") + " |")
            }
            result.append(contentsOf: lines[(index + 1)..<end])
            index = end
        }

        return result
    }

    fileprivate static func strictTableCells(in line: String) -> [String]? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("|"), trimmed.hasSuffix("|"), trimmed.count >= 3 else { return nil }
        let content = trimmed.dropFirst().dropLast()
        let cells = content.split(separator: "|", omittingEmptySubsequences: false).map {
            String($0).trimmingCharacters(in: .whitespaces)
        }
        return cells.count >= 2 ? cells : nil
    }

    fileprivate static func isTableSeparator(_ cells: [String]) -> Bool {
        !cells.isEmpty && cells.allSatisfy { cell in
            cell.range(of: "^:?-{3,}:?$", options: .regularExpression) != nil
        }
    }

    private static func removeCitationLinks(in line: String, citationKeys: Set<String>) -> String {
        let pattern = #"\[([^\]\n]+)\]\((https?://[^\s\)]+)(?:\s+[\"'][^\)]*[\"'])?\)"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return line }
        var result = line
        let matches = expression.matches(in: line, range: NSRange(line.startIndex..., in: line))

        for match in matches.reversed() {
            guard let range = Range(match.range, in: result),
                  let urlRange = Range(match.range(at: 2), in: result),
                  citationKeys.contains(citationURLKey(String(result[urlRange])) ?? "")
            else { continue }
            result.replaceSubrange(range, with: "")
        }

        return result.trimmingCharacters(in: .whitespaces)
    }

    private static func citationURLKey(_ value: String) -> String? {
        guard let decoded = value.removingPercentEncoding?.trimmingCharacters(in: .whitespacesAndNewlines),
              !decoded.isEmpty
        else { return nil }
        return decoded.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

nonisolated struct CampusAIResponseDocument: Equatable {
    nonisolated enum Block: Equatable {
        case heading(level: Int, text: String)
        case paragraph(String)
        case unorderedList([String])
        case orderedList([String])
        case quote(String)
        case code(language: String?, source: String)
        case table(headers: [String], rows: [[String]])
        case divider
    }

    let blocks: [Block]

    init(markdown: String, citationURLs: [String] = []) {
        blocks = Self.parse(CampusAIMarkdownNormalizer.normalize(markdown, removingCitationURLs: citationURLs))
    }

    private static func parse(_ markdown: String) -> [Block] {
        let lines = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        var result: [Block] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                index += 1
                continue
            }

            if let fence = fenceStart(in: trimmed) {
                var source: [String] = []
                index += 1
                while index < lines.count {
                    let candidate = lines[index]
                    if candidate.trimmingCharacters(in: .whitespaces).hasPrefix(fence.marker) {
                        index += 1
                        break
                    }
                    source.append(candidate)
                    index += 1
                }
                result.append(.code(language: fence.language, source: source.joined(separator: "\n")))
                continue
            }

            if let heading = heading(in: trimmed) {
                result.append(.heading(level: heading.level, text: heading.text))
                index += 1
                continue
            }

            if isThematicBreak(trimmed) {
                result.append(.divider)
                index += 1
                continue
            }

            if let table = table(in: lines, startIndex: index) {
                result.append(.table(headers: table.headers, rows: table.rows))
                index = table.nextIndex
                continue
            }

            if unorderedItem(in: trimmed) != nil {
                var items: [String] = []
                while index < lines.count, let item = unorderedItem(in: lines[index].trimmingCharacters(in: .whitespaces)) {
                    items.append(item)
                    index += 1
                }
                result.append(.unorderedList(items))
                continue
            }

            if orderedItem(in: trimmed) != nil {
                var items: [String] = []
                while index < lines.count, let item = orderedItem(in: lines[index].trimmingCharacters(in: .whitespaces)) {
                    items.append(item)
                    index += 1
                }
                result.append(.orderedList(items))
                continue
            }

            if trimmed.hasPrefix(">") {
                var quoteLines: [String] = []
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    guard candidate.hasPrefix(">") else { break }
                    quoteLines.append(String(candidate.dropFirst()).trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                result.append(.quote(quoteLines.joined(separator: " ")))
                continue
            }

            var paragraphLines: [String] = []
            while index < lines.count {
                let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                guard !candidate.isEmpty, !isBlockStart(candidate) else { break }
                paragraphLines.append(candidate)
                index += 1
            }
            if paragraphLines.isEmpty {
                paragraphLines.append(trimmed)
                index += 1
            }
            result.append(.paragraph(paragraphLines.joined(separator: " ")))
        }

        return result
    }

    private static func isBlockStart(_ line: String) -> Bool {
        fenceStart(in: line) != nil || heading(in: line) != nil || unorderedItem(in: line) != nil ||
            orderedItem(in: line) != nil || line.hasPrefix(">") || isThematicBreak(line) ||
            CampusAIMarkdownNormalizer.strictTableCells(in: line) != nil
    }

    private static func heading(in line: String) -> (level: Int, text: String)? {
        let hashes = line.prefix { $0 == "#" }
        guard (1...6).contains(hashes.count), line.dropFirst(hashes.count).first == " " else { return nil }
        let text = line.dropFirst(hashes.count + 1).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : (hashes.count, text)
    }

    private static func isThematicBreak(_ line: String) -> Bool {
        line.range(
            of: #"^(?:(?:-\s*){3,}|(?:\*\s*){3,}|(?:_\s*){3,})$"#,
            options: .regularExpression
        ) != nil
    }

    private static func unorderedItem(in line: String) -> String? {
        guard line.count >= 2 else { return nil }
        let prefix = line.prefix(2)
        guard prefix == "- " || prefix == "* " || prefix == "+ " else { return nil }
        let item = line.dropFirst(2).trimmingCharacters(in: .whitespaces)
        return item.isEmpty ? nil : item
    }

    private static func orderedItem(in line: String) -> String? {
        guard let markerEnd = line.firstIndex(where: { $0 == "." || $0 == ")" }) else { return nil }
        let marker = line[..<markerEnd]
        guard !marker.isEmpty, marker.allSatisfy(\.isNumber) else { return nil }
        let contentStart = line.index(after: markerEnd)
        guard contentStart < line.endIndex, line[contentStart] == " " else { return nil }
        let item = line[line.index(after: contentStart)...].trimmingCharacters(in: .whitespaces)
        return item.isEmpty ? nil : item
    }

    private static func fenceStart(in line: String) -> (marker: String, language: String?)? {
        let marker: String
        if line.hasPrefix("```") {
            marker = "```"
        } else if line.hasPrefix("~~~") {
            marker = "~~~"
        } else {
            return nil
        }
        let language = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        return (marker, language.isEmpty ? nil : language)
    }

    private static func table(
        in lines: [String],
        startIndex: Int
    ) -> (headers: [String], rows: [[String]], nextIndex: Int)? {
        guard startIndex + 1 < lines.count,
              let headers = CampusAIMarkdownNormalizer.strictTableCells(in: lines[startIndex]),
              let separator = CampusAIMarkdownNormalizer.strictTableCells(in: lines[startIndex + 1]),
              separator.count == headers.count,
              CampusAIMarkdownNormalizer.isTableSeparator(separator)
        else { return nil }

        var rows: [[String]] = []
        var index = startIndex + 2
        while index < lines.count,
              let cells = CampusAIMarkdownNormalizer.strictTableCells(in: lines[index]),
              cells.count == headers.count {
            rows.append(cells)
            index += 1
        }
        return (headers, rows, index)
    }
}

nonisolated enum CampusAIActionPresentationPolicy {
    static func isVisible(_ status: CampusAIActionStatus) -> Bool {
        status != .cancelled
    }

    static func isCollapsedByDefault(_ status: CampusAIActionStatus) -> Bool {
        status == .completed
    }
}
