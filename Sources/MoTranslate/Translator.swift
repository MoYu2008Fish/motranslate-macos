import Foundation
import NaturalLanguage

// MARK: - 数据结构

struct TranslatorConfig {
    let baseURL: String
    let apiKey: String
    let model: String
    let targetMode: TargetMode
}

struct TranslationResult {
    let text: String
    let sourceCode: String
    let targetCode: String
}

struct TranslationOptions {
    var chunking: Bool = true
    var streaming: Bool = true
}

enum TranslationError: LocalizedError {
    case notConfigured
    case emptyInput
    case invalidURL(String)
    case http(Int, String)
    case malformed
    case network(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "还没配置 API，点右上角齿轮填入地址、密钥和模型"
        case .emptyInput:
            return "没有可翻译的内容"
        case .invalidURL(let value):
            return "接口地址无效：\(value)"
        case .http(let code, let message):
            return "接口返回 \(code)：\(message)"
        case .malformed:
            return "接口返回内容无法解析"
        case .network(let message):
            return "网络错误：\(message)"
        }
    }
}

// MARK: - 翻译引擎

enum Translator {

    // MARK: 语言识别

    /// 按字符占比判断主体语言：汉字按字计、拉丁字母按词计，取占比高的一方。
    /// 只检查“有没有汉字”会把大段英文里的少量中文误判成中文，从而翻错方向。
    static func detectLanguage(_ text: String) -> String {
        var han = 0, kana = 0, hangul = 0, cyrillic = 0, latinWords = 0
        var inLatinWord = false

        for scalar in text.unicodeScalars {
            if isHan(scalar) {
                han += 1
                inLatinWord = false
            } else if isKana(scalar) {
                kana += 1
                inLatinWord = false
            } else if isHangul(scalar) {
                hangul += 1
                inLatinWord = false
            } else if isCyrillic(scalar) {
                cyrillic += 1
                inLatinWord = false
            } else if isLatinLetter(scalar) {
                if !inLatinWord {
                    latinWords += 1
                    inLatinWord = true
                }
            } else {
                inLatinWord = false
            }
        }

        // 假名、谚文只出现在日韩文本里，优先识别，避免被汉字带偏。
        if kana > 0, kana * 3 >= han { return "ja" }
        if hangul > 0, hangul >= han, hangul >= latinWords { return "ko" }

        if han > 0, han >= latinWords { return "zh-Hans" }

        if latinWords > 0 {
            // 纯拉丁文本再交给 NaturalLanguage 区分英、法、德等。
            let recognizer = NLLanguageRecognizer()
            recognizer.processString(text)
            if let language = recognizer.dominantLanguage {
                return language.rawValue
            }
            return "en"
        }

        if cyrillic > 0 { return "ru" }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue ?? "en"
    }

    private static func isHan(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x2FA1F:
            return true
        default:
            return false
        }
    }

    private static func isKana(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3040...0x309F, 0x30A0...0x30FF, 0x31F0...0x31FF, 0xFF66...0xFF9D:
            return true
        default:
            return false
        }
    }

    private static func isHangul(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x1100...0x11FF, 0x3130...0x318F, 0xAC00...0xD7AF:
            return true
        default:
            return false
        }
    }

    private static func isCyrillic(_ scalar: Unicode.Scalar) -> Bool {
        (0x0400...0x04FF).contains(scalar.value)
    }

    private static func isLatinLetter(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x41...0x5A, 0x61...0x7A, 0xC0...0x24F:
            return true
        default:
            return false
        }
    }

    static func resolveTarget(sourceCode: String, mode: TargetMode) -> String {
        switch mode {
        case .english: return "en"
        case .chinese: return "zh-Hans"
        case .auto:
            return sourceCode.hasPrefix("zh") ? "en" : "zh-Hans"
        }
    }

    static func displayName(_ code: String) -> String {
        switch code {
        case "en": return "English"
        case "zh-Hans", "zh", "zh-Hant": return "中文"
        case "ja": return "日本語"
        case "ko": return "한국어"
        case "fr": return "Français"
        case "de": return "Deutsch"
        case "es": return "Español"
        case "ru": return "Русский"
        case "pt": return "Português"
        case "it": return "Italiano"
        default:
            return Locale.current.localizedString(forLanguageCode: code) ?? code
        }
    }

    // MARK: 请求

    static func endpoint(from base: String) -> URL? {
        var value = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if !value.lowercased().hasPrefix("http") {
            value = "https://" + value
        }
        while value.hasSuffix("/") { value.removeLast() }
        let lower = value.lowercased()
        if lower.hasSuffix("/chat/completions") {
            return URL(string: value)
        }
        // 已经带版本段或 OpenAI 兼容前缀时直接补路径，避免拼成 /v4/v1/chat/completions。
        if lower.hasSuffix("/openai") || lower.hasSuffix("/v1") || lower.hasSuffix("/v2")
            || lower.hasSuffix("/v3") || lower.hasSuffix("/v4") || lower.hasSuffix("/v1beta") {
            return URL(string: value + "/chat/completions")
        }
        return URL(string: value + "/v1/chat/completions")
    }

    /// 长文本会自动按 Markdown 结构分段串行翻译，`onProgress` 报告 (已完成, 总段数)。
    static func translate(
        _ text: String,
        config: TranslatorConfig,
        options: TranslationOptions = TranslationOptions(),
        onProgress: ((Int, Int) -> Void)? = nil,
        onPartial: ((String) -> Void)? = nil
    ) async throws -> TranslationResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TranslationError.emptyInput }
        guard config.baseURL.trimmingCharacters(in: .whitespaces).isEmpty == false,
              !config.model.trimmingCharacters(in: .whitespaces).isEmpty
        else { throw TranslationError.notConfigured }
        guard let url = endpoint(from: config.baseURL) else {
            throw TranslationError.invalidURL(config.baseURL)
        }

        let sourceCode = detectLanguage(trimmed)
        let targetCode = resolveTarget(sourceCode: sourceCode, mode: config.targetMode)
        let isMarkdown = TextSegmenter.looksLikeMarkdown(trimmed)
        let chunks = options.chunking
            ? TextSegmenter.chunks(from: trimmed)
            : [TranslationChunk(text: trimmed, trailing: "", translatable: true)]
        let translatableCount = chunks.filter(\.translatable).count

        var assembled = ""
        if translatableCount == 0 {
            // 整段都是代码块：没有自然语言可翻，原样返回。
            assembled = trimmed
        } else {
            var completed = 0
            for chunk in chunks {
                guard chunk.translatable else {
                    assembled += chunk.text + chunk.trailing
                    onPartial?(assembled)
                    continue
                }
                completed += 1
                onProgress?(completed, translatableCount)

                let prefix = assembled
                let trailing = chunk.trailing
                let translated = try await request(
                    url: url, text: chunk.text, config: config,
                    targetCode: targetCode, isMarkdown: isMarkdown,
                    streaming: options.streaming,
                    onDelta: onPartial == nil ? nil : { partial in
                        onPartial?(prefix + partial + trailing)
                    }
                )
                assembled = prefix + translated + trailing
                onPartial?(assembled)
            }
        }

        return TranslationResult(
            text: cleanup(assembled),
            sourceCode: sourceCode,
            targetCode: targetCode
        )
    }

    private static func request(
        url: URL,
        text: String,
        config: TranslatorConfig,
        targetCode: String,
        isMarkdown: Bool,
        streaming: Bool,
        onDelta: ((String) -> Void)?
    ) async throws -> String {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        // 本地大模型的首次加载和推理可能较慢；仍可从面板随时取消。
        let isLocal = ["localhost", "127.0.0.1", "::1", "[::1]"].contains(url.host?.lowercased() ?? "")
        request.timeoutInterval = isLocal ? 180 : 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !config.apiKey.isEmpty {
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }

        let body: [String: Any] = [
            "model": config.model,
            "temperature": 0.2,
            "stream": streaming,
            "messages": [
                ["role": "system", "content": systemPrompt(targetCode: targetCode, isMarkdown: isMarkdown)],
                ["role": "user", "content": text]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        if streaming {
            return try await streamedContent(for: request, onDelta: onDelta)
        }
        return try await completeContent(for: request)
    }

    private static func completeContent(for request: URLRequest) async throws -> String {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw TranslationError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw TranslationError.malformed
        }
        guard (200..<300).contains(http.statusCode) else {
            throw TranslationError.http(http.statusCode, errorMessage(from: data))
        }

        return try parseContent(from: data)
    }

    /// 逐块读取 SSE；若服务商忽略 stream 参数返回普通 JSON，也能兼容。
    private static func streamedContent(
        for request: URLRequest,
        onDelta: ((String) -> Void)?
    ) async throws -> String {
        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await URLSession.shared.bytes(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw TranslationError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw TranslationError.malformed
        }

        if !(200..<300).contains(http.statusCode) {
            var data = Data()
            for try await byte in bytes { data.append(byte) }
            throw TranslationError.http(http.statusCode, errorMessage(from: data))
        }

        let contentType = http.value(forHTTPHeaderField: "Content-Type") ?? ""
        guard contentType.contains("text/event-stream") else {
            var data = Data()
            for try await byte in bytes { data.append(byte) }
            let content = try parseContent(from: data)
            onDelta?(content)
            return content
        }

        var content = ""
        for try await rawLine in bytes.lines {
            // 兼容 \r\n 结尾与个别实现的行首空格。
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("data:") else { continue }
            let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = object["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any],
                  let piece = delta["content"] as? String,
                  !piece.isEmpty
            else { continue }
            content += piece
            onDelta?(content)
        }

        guard !content.isEmpty else { throw TranslationError.malformed }
        return content
    }

    /// 提示词用目标语言书写，并明确混合文本的处理方式，避免模型以“已经是目标语言”为由整段跳过。
    private static func systemPrompt(targetCode: String, isMarkdown: Bool) -> String {
        if targetCode.hasPrefix("zh") {
            return """
            你是一名专业翻译。把用户提供的文本翻译成地道的简体中文。

            规则：
            1. 只输出译文本身，不要解释、不要前言、不要“译文：”之类的前缀、不要引号，也不要附上原文。
            2. 输入可能是中英混排或包含其他语言：把其中所有非中文的内容都翻译成中文，已经是中文的内容保持原意即可。不要因为部分内容已经是中文就整段跳过不译。
            3. 完整保留原文的意思、语气、段落结构和换行。
            4. 代码、变量名、命令、文件路径、URL、邮箱、专有名词和产品名保持原样，不翻译。
            5. 译文必须全部是中文，不要残留成句的英文；只有代码、专有名词这类内容允许保留原文。
            6. 只有当输入整段都已经是中文时，才原样返回，不要改写。
            \(isMarkdown ? "7. 输入包含 Markdown：保留标题、列表、引用、表格、链接和强调等语法标记，只翻译其中的自然语言；代码块与行内代码原样保留。" : "")
            """
        }
        return """
        You are a professional translator. Translate the user's text into natural English.

        Rules:
        1. Output only the translation — no explanation, no preamble, no "Translation:" prefix, no quotes, and do not repeat the source text.
        2. The input may mix languages. Translate every part that is not English into English, and keep the parts already in English as they are. Never skip the whole input just because part of it is already English.
        3. Preserve the original meaning, tone, paragraph structure and line breaks.
        4. Keep code, variable names, commands, file paths, URLs, emails, proper nouns and product names unchanged.
        5. The whole output must be in English. No sentence may be left in another language, except code, proper nouns and the like.
        6. Only when the input is already entirely English, return it unchanged.
        \(isMarkdown ? "7. The input is Markdown: keep headings, lists, quotes, tables, links and emphasis markers intact, translate only the natural language, and leave code blocks and inline code unchanged." : "")
        """
    }

    private static func parseContent(from data: Data) throws -> String {
        struct ChatResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String? }
                let message: Message
            }
            let choices: [Choice]
        }
        do {
            let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
            guard let content = decoded.choices.first?.message.content else {
                throw TranslationError.malformed
            }
            return content
        } catch {
            throw TranslationError.malformed
        }
    }

    private static func errorMessage(from data: Data) -> String {
        if let raw = try? JSONSerialization.jsonObject(with: data),
           let object = raw as? [String: Any] {
            if let error = object["error"] as? [String: Any],
               let message = error["message"] as? String {
                return message
            }
            if let message = object["message"] as? String {
                return message
            }
        }
        let raw = String(data: data.prefix(300), encoding: .utf8) ?? ""
        return raw.isEmpty ? "未知错误" : raw
    }

    /// 去掉模型偶尔加的包裹引号或“译文：”前缀。
    private static func cleanup(_ text: String) -> String {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = ["译文：", "译文:", "翻译：", "翻译:", "Translation:", "Translation："]
        for prefix in prefixes where value.hasPrefix(prefix) {
            value = String(value.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if value.count >= 2,
           (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
           (value.hasPrefix("“") && value.hasSuffix("”")) {
            value = String(value.dropFirst().dropLast())
        }
        return value
    }
}
