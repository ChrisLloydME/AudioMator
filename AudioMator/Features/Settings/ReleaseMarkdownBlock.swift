import Foundation

enum ReleaseMarkdownBlock: Equatable {
    case spacer
    case heading(level: Int, text: String)
    case bullet(indentLevel: Int, text: String)
    case paragraph(indentLevel: Int, text: String)

    static func parse(_ markdown: String) -> [ReleaseMarkdownBlock] {
        let normalized = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false)
        guard !lines.isEmpty else {
            return [.paragraph(indentLevel: 0, text: "No release notes provided.")]
        }

        var blocks: [ReleaseMarkdownBlock] = []

        for line in lines {
            let rawLine = String(line)
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                if blocks.last.map({ if case .spacer = $0 { return true } else { return false } }) != true {
                    blocks.append(.spacer)
                }
                continue
            }

            let leadingWhitespaceCount = rawLine.prefix { $0 == " " || $0 == "\t" }.count
            let indentLevel = max(0, leadingWhitespaceCount / 2)

            if let heading = heading(from: trimmed) {
                blocks.append(.heading(level: heading.level, text: heading.text))
                continue
            }

            if let bulletText = bulletText(from: trimmed) {
                blocks.append(.bullet(indentLevel: indentLevel, text: bulletText))
                continue
            }

            blocks.append(.paragraph(indentLevel: indentLevel, text: trimmed))
        }

        return blocks.isEmpty ? [.paragraph(indentLevel: 0, text: "No release notes provided.")] : blocks
    }

    private static func heading(from line: String) -> (level: Int, text: String)? {
        let hashes = line.prefix { $0 == "#" }
        let level = hashes.count

        guard level > 0, level <= 6 else { return nil }

        let remainder = line.dropFirst(level).trimmingCharacters(in: .whitespaces)
        guard !remainder.isEmpty else { return nil }

        return (level, remainder)
    }

    private static func bulletText(from line: String) -> String? {
        guard line.count >= 2 else { return nil }

        let marker = line.prefix(2)
        guard marker == "- " || marker == "* " || marker == "+ " else { return nil }

        return String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
    }
}
