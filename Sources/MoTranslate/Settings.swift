import Foundation
import SwiftUI
import Carbon.HIToolbox

// MARK: - 目标语言策略

enum TargetMode: String, CaseIterable, Identifiable {
    case auto
    case english
    case chinese

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return "自动（中 → 英，其他 → 中）"
        case .english: return "始终英文"
        case .chinese: return "始终中文"
        }
    }

    var shortTitle: String {
        switch self {
        case .auto: return "自动"
        case .english: return "英文"
        case .chinese: return "中文"
        }
    }
}

// MARK: - 全局快捷键预设

enum HotKeyPreset: String, CaseIterable, Identifiable {
    case optionD
    case optionS
    case optionT
    case optionG
    case controlOptionD

    var id: String { rawValue }

    var title: String {
        switch self {
        case .optionD: return "⌥ D"
        case .optionS: return "⌥ S"
        case .optionT: return "⌥ T"
        case .optionG: return "⌥ G"
        case .controlOptionD: return "⌃⌥ D"
        }
    }

    var keyCode: UInt32 {
        switch self {
        case .optionD, .controlOptionD: return UInt32(kVK_ANSI_D)
        case .optionS: return UInt32(kVK_ANSI_S)
        case .optionT: return UInt32(kVK_ANSI_T)
        case .optionG: return UInt32(kVK_ANSI_G)
        }
    }

    var modifiers: UInt32 {
        switch self {
        case .optionD, .optionS, .optionT, .optionG:
            return UInt32(optionKey)
        case .controlOptionD:
            return UInt32(optionKey | controlKey)
        }
    }
}

// MARK: - Keychain

enum Keychain {
    private static let service = "com.moyu.motranslate"
    private static let account = "openai-api-key"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    static func load() -> String {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let text = String(data: data, encoding: .utf8)
        else { return "" }
        return text
    }

    static func save(_ value: String) {
        SecItemDelete(baseQuery as CFDictionary)
        guard !value.isEmpty, let data = value.data(using: .utf8) else { return }
        var query = baseQuery
        query[kSecValueData as String] = data
        SecItemAdd(query as CFDictionary, nil)
    }
}

// MARK: - 设置

final class AppSettings: ObservableObject {
    private let defaults: UserDefaults

    @Published var baseURL: String {
        didSet { defaults.set(baseURL, forKey: "baseURL") }
    }

    @Published var model: String {
        didSet { defaults.set(model, forKey: "model") }
    }

    @Published var apiKey: String {
        didSet { Keychain.save(apiKey) }
    }

    @Published var targetMode: TargetMode {
        didSet { defaults.set(targetMode.rawValue, forKey: "targetMode") }
    }

    @Published var autoTranslate: Bool {
        didSet { defaults.set(autoTranslate, forKey: "autoTranslate") }
    }

    @Published var hotKeyPreset: HotKeyPreset {
        didSet { defaults.set(hotKeyPreset.rawValue, forKey: "hotKeyPreset") }
    }

    @Published var fillFromClipboard: Bool {
        didSet { defaults.set(fillFromClipboard, forKey: "fillFromClipboard") }
    }

    @Published var keepPanelOpen: Bool {
        didSet { defaults.set(keepPanelOpen, forKey: "keepPanelOpen") }
    }

    init(defaults: UserDefaults = .standard, loadAPIKey: Bool = true) {
        self.defaults = defaults
        let storedURL = defaults.string(forKey: "baseURL") ?? ""
        let storedModel = defaults.string(forKey: "model") ?? ""
        let storedMode = defaults.string(forKey: "targetMode") ?? ""
        let storedPreset = defaults.string(forKey: "hotKeyPreset") ?? ""

        keepPanelOpen = defaults.bool(forKey: "keepPanelOpen")
        baseURL = storedURL
        model = storedModel
        targetMode = TargetMode(rawValue: storedMode) ?? .auto
        hotKeyPreset = HotKeyPreset(rawValue: storedPreset) ?? .optionD
        autoTranslate = defaults.object(forKey: "autoTranslate") as? Bool ?? true
        fillFromClipboard = defaults.object(forKey: "fillFromClipboard") as? Bool ?? true
        apiKey = loadAPIKey ? Keychain.load() : ""
    }

    var isConfigured: Bool {
        !baseURL.trimmingCharacters(in: .whitespaces).isEmpty
            && !model.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var config: TranslatorConfig {
        TranslatorConfig(
            baseURL: baseURL,
            apiKey: apiKey,
            model: model,
            targetMode: targetMode
        )
    }
}
