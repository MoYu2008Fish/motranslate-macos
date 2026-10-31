import Foundation

/// 分段后的翻译单元。按顺序拼接 `text + trailing` 可以还原原文。
struct TranslationChunk {
    let text: String
    let trailing: String
    let translatable: Bool
}

/// 长文本分段：按 Markdown 结构切块，代码块整块保留，超长段落再按句子切分。
enum TextSegmenter {

    /// 本地小模型的上下文有限，单段控制在 1200 字符左右可显著缩短单次耗时。
    static let defaultMaxCharacters = 1200

    // MARK: Markdown 识别

    /// 命中代码围栏、标题、表格等强特征，或累计两个弱特征，就按 Markdown 处理。
    static func looksLikeMarkdown(_ text: String) -> Bool {
        var score = 0
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                return true
            }
            if trimmed.hasPrefix("# ") || trimmed.hasPrefix("## ")
                || trimmed.hasPrefix("### ") || trimmed.hasPrefix("#### ") {
                return true
            }
            if trimmed.hasPrefix("|"), trimmed.hasSuffix("|"),
               trimmed.filter({ $0 == "|" }).count >= 3 {
                return true
            }
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ")
                || trimmed.hasPrefix("+ ") || trimmed.hasPrefix("> ") {
                score += 1
            }
            if trimmed.range(of: "^\\d+\\.\\s", options: .regularExpression) != nil {
                score += 1
            }
        }
        if text.range(of: "\\*\\*[^*\\n]+\\*\\*", options: .regularExpression) != nil { score += 1 }
        if text.range(of: "\\[[^\\]\\n]+\\]\\([^)\\n]+\\)", options: .regularExpression) != nil { score += 1 }
        if text.range(of: "`[^`\\n]+`", options: .regularExpression) != nil { score += 1 }
        return score >= 2
    }

    // MARK: 分段

    static func chunks(from text: String, maxCharacters: Int = defaultMaxCharacters) -> [TranslationChunk] {
        let ns = text as NSString
        guard ns.length > 0 else { return [] }
        let slices = scanSlices(in: ns)
        let assembled = assemble(slices, in: ns)
        let expanded = assembled.flatMap { expand($0, maxCharacters: maxCharacters) }
        return merge(expanded, maxCharacters: maxCharacters)
    }

    // MARK: 内部实现

    private struct Slice {
        let range: NSRange
        let isCode: Bool
    }

    /// 行扫描找出 fenced code block，其余区间按空行切成段落。
    private static func scanSlices(in ns: NSString) -> [Slice] {
        var lineRanges: [NSRange] = []
        ns.enumerateSubstrings(
            in: NSRange(location: 0, length: ns.length),
            options: [.byLines, .substringNotRequired]
        ) { _, _, enclosingRange, _ in
            lineRanges.append(enclosingRange)
        }
        guard !lineRanges.isEmpty else { return [] }

        var slices: [Slice] = []
        var normalStart: Int?
        var index = 0

        func flushNormal(upTo end: Int) {
            guard let start = normalStart, end > start else { return }
            let location = lineRanges[start].location
            let upper = lineRanges[end - 1].upperBound
            let range = NSRange(location: location, length: upper - location)
            slices.append(contentsOf: paragraphs(in: ns, range: range).map { Slice(range: $0, isCode: false) })
            normalStart = nil
        }

        while index < lineRanges.count {
            let line = ns.substring(with: lineRanges[index])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let marker = fenceMarker(line) {
                flushNormal(upTo: index)
                var end = lineRanges.count - 1
                var scan = index + 1
                while scan < lineRanges.count {
                    let candidate = ns.substring(with: lineRanges[scan])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if candidate.hasPrefix(marker) {
                        end = scan
                        break
                    }
                    scan += 1
                }
                let location = lineRanges[index].location
                let upper = lineRanges[end].upperBound
                slices.append(Slice(range: NSRange(location: location, length: upper - location), isCode: true))
                index = end + 1
            } else {
                if normalStart == nil { normalStart = index }
                index += 1
            }
        }
        flushNormal(upTo: lineRanges.count)

        return slices.sorted { $0.range.location < $1.range.location }
    }

    private static func fenceMarker(_ line: String) -> String? {
        if line.hasPrefix("```") { return "```" }
        if line.hasPrefix("~~~") { return "~~~" }
        return nil
    }

    /// 用空行切段落；纯空白段落不单独成块，留给拼接时的分隔符。
    private static func paragraphs(in ns: NSString, range: NSRange) -> [NSRange] {
        guard let regex = try? NSRegularExpression(pattern: "\\n[\\t ]*\\n[\\t ]*") else {
            return [range]
        }
        var result: [NSRange] = []
        var cursor = range.location
        for match in regex.matches(in: ns as String, range: range) {
            let paragraphRange = NSRange(location: cursor, length: match.range.location - cursor)
            if isMeaningful(ns, paragraphRange) { result.append(paragraphRange) }
            cursor = match.range.upperBound
        }
        if cursor < range.upperBound {
            let tail = NSRange(location: cursor, length: range.upperBound - cursor)
            if isMeaningful(ns, tail) { result.append(tail) }
        }
        return result
    }

    private static func isMeaningful(_ ns: NSString, _ range: NSRange) -> Bool {
        range.length > 0
            && !ns.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 把块之间的间隙（空行）挂到上一块尾部，保证拼接能还原原文。
    private static func assemble(_ slices: [Slice], in ns: NSString) -> [TranslationChunk] {
        var chunks: [TranslationChunk] = []
        var cursor = 0

        for slice in slices {
            guard slice.range.location >= cursor else { continue }
            let gap = ns.substring(with: NSRange(location: cursor, length: slice.range.location - cursor))
            cursor = slice.range.upperBound
            let content = ns.substring(with: slice.range)

            if let last = chunks.popLast() {
                chunks.append(TranslationChunk(text: last.text, trailing: last.trailing + gap, translatable: last.translatable))
                chunks.append(TranslationChunk(text: content, trailing: "", translatable: !slice.isCode))
            } else {
                chunks.append(TranslationChunk(text: gap + content, trailing: "", translatable: !slice.isCode))
            }
        }

        let tail = ns.substring(from: min(cursor, ns.length))
        if let last = chunks.popLast() {
            chunks.append(TranslationChunk(text: last.text, trailing: last.trailing + tail, translatable: last.translatable))
        } else if !tail.isEmpty {
            chunks.append(TranslationChunk(text: tail, trailing: "", translatable: true))
        }
        return chunks
    }

    private static func expand(_ chunk: TranslationChunk, maxCharacters: Int) -> [TranslationChunk] {
        guard chunk.translatable, chunk.text.count > maxCharacters else { return [chunk] }
        let pieces = split(chunk.text, maxCharacters: maxCharacters)
        return pieces.enumerated().map { index, piece in
            TranslationChunk(
                text: piece,
                trailing: index == pieces.count - 1 ? chunk.trailing : "",
                translatable: true
            )
        }
    }

    /// 优先在句末标点处断开，实在过长再退回空白处，避免把单词切碎。
    private static func split(_ text: String, maxCharacters: Int) -> [String] {
        var pieces: [String] = []
        var buffer = ""

        for character in text {
            buffer.append(character)
            let atSentenceEnd = "。！？!?；;\n".contains(character)
            if atSentenceEnd, buffer.count >= maxCharacters * 2 / 3 {
                pieces.append(buffer)
                buffer = ""
            } else if buffer.count >= maxCharacters {
                if let breakIndex = buffer.lastIndex(where: { $0.isWhitespace || $0 == "，" || $0 == "," }),
                   buffer.distance(from: buffer.startIndex, to: breakIndex) > maxCharacters / 3 {
                    let cut = buffer.index(after: breakIndex)
                    pieces.append(String(buffer[..<cut]))
                    buffer = String(buffer[cut...])
                } else {
                    pieces.append(buffer)
                    buffer = ""
                }
            }
        }
        if !buffer.isEmpty { pieces.append(buffer) }
        return pieces
    }

    /// 合并相邻的短段落，减少请求次数；代码块不参与合并。
    private static func merge(_ chunks: [TranslationChunk], maxCharacters: Int) -> [TranslationChunk] {
        var result: [TranslationChunk] = []
        for chunk in chunks {
            if let last = result.last,
               last.translatable, chunk.translatable,
               last.text.count + last.trailing.count + chunk.text.count <= maxCharacters {
                result[result.count - 1] = TranslationChunk(
                    text: last.text + last.trailing + chunk.text,
                    trailing: chunk.trailing,
                    translatable: true
                )
            } else {
                result.append(chunk)
            }
        }
        return result
    }
}
