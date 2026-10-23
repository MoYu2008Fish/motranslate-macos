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

    /// 汉字优先判断，其余交给 NaturalLanguage，避免中英混排被误判。
    static func detectLanguage(_ text: String) -> String {
        if text.range(of: "\\p{Han}", options: .regularExpression) != nil {
            return "zh-Hans"
        }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        if let language = recognizer.dominantLanguage {
            return language.rawValue
        }
        return "en"
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
        if value.lowercased().hasSuffix("/chat/completions") {
            return URL(string: value)
        }
        if value.lowercased().hasSuffix("/v1") {
            return URL(string: value + "/chat/completions")
        }
        return URL(string: value + "/v1/chat/completions")
    }

    static func translate(_ text: String, config: TranslatorConfig) async throws -> TranslationResult {
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
        let targetName = displayName(targetCode)

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
            "stream": false,
            "messages": [
                ["role": "system", "content": systemPrompt(target: targetName)],
                ["role": "user", "content": trimmed]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

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

        let content = try parseContent(from: data)
        return TranslationResult(
            text: cleanup(content),
            sourceCode: sourceCode,
            targetCode: targetCode
        )
    }

    private static func systemPrompt(target: String) -> String {
        """
        You are a professional translator. Translate the user's text into \(target).
        Rules:
        - Output ONLY the translation. No explanations, prefixes, quotes, or notes.
        - Preserve the original meaning, tone, formatting and line breaks.
        - Keep proper nouns, code, URLs and technical terms accurate.
        - If the text is already in \(target), return it unchanged.
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
