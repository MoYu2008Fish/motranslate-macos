import Foundation

/// 模型库条目：一套 Base URL + 模型标识；同一服务商的条目共用一份 API Key。
struct ModelEntry: Identifiable, Codable, Equatable {
    let id: String
    var name: String
    var baseURL: String
    var model: String
    var isBuiltIn: Bool

    /// API Key 按服务商（host + 端口）共享，切换模型时不用重复填写。
    var keyAccount: String {
        var value = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.lowercased().hasPrefix("http") { value = "https://" + value }
        guard let url = URL(string: value), let host = url.host?.lowercased() else {
            return value
        }
        if let port = url.port { return "\(host):\(port)" }
        return host
    }

    var saved: ModelEntry {
        ModelEntry(id: id, name: name, baseURL: baseURL, model: model, isBuiltIn: false)
    }
}

/// 内置预设只出现在「添加模型」流程里，不会自动进入模型库。
enum ModelLibrary {
    /// 首次启动的默认条目：本地 Ollama，符合墨译的本地优先定位。
    static let defaultEntryID = "local-qwen3-4b"

    /// 2026-10 核对：模型代号来自 models.dev 目录与各服务商文档。
    static let all: [ModelEntry] = [
        // 本地 Ollama
        entry("local-qwen3-4b", "Ollama · Qwen3 4B", "http://localhost:11434/v1", "qwen3-4b:latest"),
        entry("local-qwen3-1.7b", "Ollama · Qwen3 1.7B", "http://localhost:11434/v1", "qwen3-1.7b:latest"),

        // DeepSeek
        entry("deepseek-flash", "DeepSeek · V4.1 Flash", "https://api.deepseek.com/v1", "deepseek-flash"),
        entry("deepseek-v4-pro", "DeepSeek · V4 Pro", "https://api.deepseek.com/v1", "deepseek-v4-pro"),

        // OpenAI
        entry("openai-gpt-6.1-terra", "OpenAI · GPT-6.1 Terra", "https://api.openai.com/v1", "gpt-6.1-terra"),
        entry("openai-gpt-6.1-sol", "OpenAI · GPT-6.1 Sol", "https://api.openai.com/v1", "gpt-6.1-sol"),

        // Anthropic（官方 OpenAI 兼容端点）
        entry("anthropic-claude-sonnet-5-5", "Anthropic · Claude Sonnet 5.5", "https://api.anthropic.com/v1", "claude-sonnet-5-5"),
        entry("anthropic-claude-haiku-5-5", "Anthropic · Claude Haiku 5.5", "https://api.anthropic.com/v1", "claude-haiku-5-5"),

        // Google Gemini（OpenAI 兼容端点）
        entry("google-gemini-4-argon", "Google · Gemini 4 Argon", "https://generativelanguage.googleapis.com/v1beta/openai", "gemini-4-argon"),
        entry("google-gemini-3.8-flash", "Google · Gemini 3.8 Flash", "https://generativelanguage.googleapis.com/v1beta/openai", "gemini-3.8-flash"),

        // 月之暗面 Kimi
        entry("moonshot-kimi-k3.1-pro", "Moonshot · Kimi K3.1 Pro", "https://api.moonshot.cn/v1", "kimi-k3.1-pro"),
        entry("moonshot-kimi-k2.6", "Moonshot · Kimi K2.6", "https://api.moonshot.cn/v1", "kimi-k2.6"),

        // 智谱 GLM
        entry("zhipu-glm-5.3-flash", "智谱 · GLM-5.3-Flash", "https://open.bigmodel.cn/api/paas/v4", "glm-5.3-flash"),
        entry("zhipu-glm-5.3", "智谱 · GLM-5.3", "https://open.bigmodel.cn/api/paas/v4", "glm-5.3"),

        // 阿里通义千问
        entry("dashscope-qwen3.8-flash", "通义 · Qwen3.8 Flash", "https://dashscope.aliyuncs.com/compatible-mode/v1", "qwen3.8-flash"),
        entry("dashscope-qwen3.8-max", "通义 · Qwen3.8 Max", "https://dashscope.aliyuncs.com/compatible-mode/v1", "qwen3.8-max"),

        // 硅基流动
        entry("siliconflow-deepseek-v4-pro", "硅基流动 · DeepSeek V4 Pro", "https://api.siliconflow.cn/v1", "deepseek-ai/DeepSeek-V4-Pro"),
        entry("siliconflow-glm-5.2", "硅基流动 · GLM-5.2", "https://api.siliconflow.cn/v1", "zai-org/GLM-5.2"),

        // OpenRouter
        entry("openrouter-gpt-6.1-terra", "OpenRouter · GPT-6.1 Terra", "https://openrouter.ai/api/v1", "openai/gpt-6.1-terra"),
        entry("openrouter-kimi-k3.1-pro", "OpenRouter · Kimi K3.1 Pro", "https://openrouter.ai/api/v1", "moonshotai/kimi-k3.1-pro")
    ]

    static func preset(_ id: String) -> ModelEntry? {
        all.first { $0.id == id }
    }

    static func preset(baseURL: String, model: String) -> ModelEntry? {
        all.first { $0.baseURL == baseURL && $0.model == model }
    }

    private static func entry(_ id: String, _ name: String, _ baseURL: String, _ model: String) -> ModelEntry {
        ModelEntry(id: id, name: name, baseURL: baseURL, model: model, isBuiltIn: true)
    }
}
