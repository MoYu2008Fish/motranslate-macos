import Foundation
import SwiftUI

// MARK: - 解析结果

enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case bullet(text: String, orderedIndex: Int?)
    case quote(String)
    case code(String)
    case table([String])
    case rule
    case paragraph(String)
}

// MARK: - 轻量 Markdown 解析

/// 只解析翻译结果里会出现的常见结构：标题、列表、引用、代码块、表格、分隔线。
/// 行内加粗、斜体、行内代码和链接交给 AttributedString 处理。
enum MarkdownBlockParser {

    static func parse(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var codeLines: [String] = []
        var tableLines: [String] = []
        var inCode = false
        var fence = ""

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: "\n")))
            paragraph.removeAll()
        }

        func flushTable() {
            guard !tableLines.isEmpty else { return }
            blocks.append(.table(tableLines))
            tableLines.removeAll()
        }

        for rawLine in text.components(separatedBy: "\n") {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if inCode {
                if trimmed.hasPrefix(fence) {
                    blocks.append(.code(codeLines.joined(separator: "\n")))
                    codeLines.removeAll()
                    inCode = false
                } else {
                    codeLines.append(rawLine)
                }
                continue
            }

            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flushParagraph()
                flushTable()
                fence = String(trimmed.prefix(3))
                inCode = true
                continue
            }

            let isTableRow = trimmed.hasPrefix("|") && trimmed.hasSuffix("|") && trimmed.count > 2
            if !isTableRow { flushTable() }

            if trimmed.isEmpty {
                flushParagraph()
                continue
            }

            if let heading = parseHeading(trimmed) {
                flushParagraph()
                blocks.append(heading)
                continue
            }

            if trimmed.hasPrefix(">") {
                flushParagraph()
                blocks.append(.quote(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)))
                continue
            }

            if isRule(trimmed) {
                flushParagraph()
                blocks.append(.rule)
                continue
            }

            if let bullet = parseBullet(trimmed) {
                flushParagraph()
                blocks.append(bullet)
                continue
            }

            if isTableRow {
                flushParagraph()
                tableLines.append(trimmed)
                continue
            }

            paragraph.append(rawLine)
        }

        if inCode, !codeLines.isEmpty {
            blocks.append(.code(codeLines.joined(separator: "\n")))
        }
        flushParagraph()
        flushTable()
        return blocks
    }

    /// 自己解析行内标记：Foundation 的 Markdown 解析器按 CommonMark 判定
    /// flanking，中文标点紧贴 `**` 时不会识别为强调，所以这里直接匹配。
    static func inline(_ text: String) -> AttributedString {
        let pattern = #"\*\*(.+?)\*\*|__(.+?)__|`([^`\n]+)`|\[([^\]\n]+)\]\(([^)\s]+)\)|\*([^*\n]+)\*|_([^_\n]+)_"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return AttributedString(text)
        }

        let ns = text as NSString
        var result = AttributedString()
        var cursor = 0

        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            if match.range.location > cursor {
                result += AttributedString(ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor)))
            }

            if let value = captured(ns, match, 1) ?? captured(ns, match, 2) {
                var piece = AttributedString(value)
                piece.inlinePresentationIntent = .stronglyEmphasized
                result += piece
            } else if let value = captured(ns, match, 3) {
                var piece = AttributedString(value)
                piece.inlinePresentationIntent = .code
                result += piece
            } else if let value = captured(ns, match, 4) {
                var piece = AttributedString(value)
                if let urlText = captured(ns, match, 5), let url = URL(string: urlText) {
                    piece.link = url
                }
                result += piece
            } else if let value = captured(ns, match, 6) ?? captured(ns, match, 7) {
                var piece = AttributedString(value)
                piece.inlinePresentationIntent = .emphasized
                result += piece
            }

            cursor = match.range.location + match.range.length
        }

        if cursor < ns.length {
            result += AttributedString(ns.substring(from: cursor))
        }
        return result
    }

    private static func captured(_ ns: NSString, _ match: NSTextCheckingResult, _ index: Int) -> String? {
        guard index < match.numberOfRanges else { return nil }
        let range = match.range(at: index)
        guard range.location != NSNotFound, range.length > 0 else { return nil }
        return ns.substring(with: range)
    }

    private static func parseHeading(_ line: String) -> MarkdownBlock? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes) else { return nil }
        let rest = line.dropFirst(hashes)
        guard rest.hasPrefix(" ") else { return nil }
        return .heading(level: hashes, text: rest.trimmingCharacters(in: .whitespaces))
    }

    private static func parseBullet(_ line: String) -> MarkdownBlock? {
        if let first = line.first, "-*+".contains(first), line.dropFirst().hasPrefix(" ") {
            return .bullet(
                text: String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces),
                orderedIndex: nil
            )
        }

        let digits = line.prefix { $0.isNumber }
        guard !digits.isEmpty else { return nil }
        let rest = line.dropFirst(digits.count)
        if rest.hasPrefix(". ") || rest.hasPrefix(") ") {
            return .bullet(
                text: String(rest.dropFirst(2)).trimmingCharacters(in: .whitespaces),
                orderedIndex: Int(digits) ?? 1
            )
        }
        return nil
    }

    private static func isRule(_ line: String) -> Bool {
        let compact = line.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 3 else { return false }
        return compact.allSatisfy { $0 == "-" }
            || compact.allSatisfy { $0 == "*" }
            || compact.allSatisfy { $0 == "_" }
    }
}

// MARK: - 渲染

struct MarkdownText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(MarkdownBlockParser.parse(text).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(MarkdownBlockParser.inline(text))
                .font(.system(size: headingSize(level), weight: .semibold))
                .padding(.top, level <= 2 ? 4 : 0)

        case .bullet(let text, let orderedIndex):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(orderedIndex.map { "\($0)." } ?? "•")
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 16, alignment: .trailing)
                Text(MarkdownBlockParser.inline(text))
            }

        case .quote(let text):
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.secondary.opacity(0.25))
                    .frame(width: 3)
                Text(MarkdownBlockParser.inline(text))
                    .foregroundStyle(.secondary)
            }

        case .code(let code):
            Text(code)
                .font(.system(size: 13, design: .monospaced))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))

        case .table(let rows):
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    Text(row)
                        .font(.system(size: 13, design: .monospaced))
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))

        case .rule:
            Divider()

        case .paragraph(let text):
            Text(MarkdownBlockParser.inline(text))
        }
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return 22
        case 2: return 20
        case 3: return 18
        case 4: return 17
        default: return 16
        }
    }
}
