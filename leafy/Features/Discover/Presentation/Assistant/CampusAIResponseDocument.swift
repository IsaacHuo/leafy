import Foundation

nonisolated struct CampusAIResponseDocument: Equatable {
    nonisolated enum Block: Equatable {
        case heading(level: Int, text: String)
        case paragraph(String)
        case unorderedList([String])
        case orderedList([String])
        case quote(String)
        case code(language: String?, source: String)
    }

    let blocks: [Block]

    init(markdown: String) {
        blocks = Self.parse(markdown)
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
            orderedItem(in: line) != nil || line.hasPrefix(">")
    }

    private static func heading(in line: String) -> (level: Int, text: String)? {
        let hashes = line.prefix { $0 == "#" }
        guard (1...3).contains(hashes.count), line.dropFirst(hashes.count).first == " " else { return nil }
        let text = line.dropFirst(hashes.count + 1).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : (hashes.count, text)
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
}

nonisolated enum CampusAIActionPresentationPolicy {
    static func isVisible(_ status: CampusAIActionStatus) -> Bool {
        status != .cancelled
    }

    static func isCollapsedByDefault(_ status: CampusAIActionStatus) -> Bool {
        status == .completed
    }
}
