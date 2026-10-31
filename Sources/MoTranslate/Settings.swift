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

// MARK: - 峰谷档位

/// 服务商按时间段计价的档位，如 DeepSeek 的高峰/空闲定价。
enum ModelTier {
    case peak
    case offPeak

    var title: String {
        switch self {
        case .peak: return "高峰期"
        case .offPeak: return "空闲时段"
        }
    }
}

// MARK: - Keychain

enum Keychain {
    private static let service = "com.moyu.motranslate"
    static let mainAccount = "openai-api-key"
    static let offPeakAccount = "offpeak-api-key"

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    static func load(account: String = mainAccount) -> String {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let text = String(data: data, encoding: .utf8)
        else { return "" }
        return text
    }

    static func save(_ value: String, account: String = mainAccount) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard !value.isEmpty, let data = value.data(using: .utf8) else { return }
        var query = baseQuery(account: account)
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

    // MARK: 峰谷调度

    @Published var scheduleEnabled: Bool {
        didSet { defaults.set(scheduleEnabled, forKey: "scheduleEnabled") }
    }

    @Published var offPeakBaseURL: String {
        didSet { defaults.set(offPeakBaseURL, forKey: "offPeakBaseURL") }
    }

    @Published var offPeakModel: String {
        didSet { defaults.set(offPeakModel, forKey: "offPeakModel") }
    }

    @Published var offPeakAPIKey: String {
        didSet { Keychain.save(offPeakAPIKey, account: Keychain.offPeakAccount) }
    }

    /// 高峰时段以“距零点的分钟数”保存，方便用较短的时间控件编辑。
    @Published var peakStart1: Int {
        didSet { defaults.set(peakStart1, forKey: "peakStart1") }
    }

    @Published var peakEnd1: Int {
        didSet { defaults.set(peakEnd1, forKey: "peakEnd1") }
    }

    @Published var peakStart2: Int {
        didSet { defaults.set(peakStart2, forKey: "peakStart2") }
    }

    @Published var peakEnd2: Int {
        didSet { defaults.set(peakEnd2, forKey: "peakEnd2") }
    }

    /// 周末是否整日按空闲时段处理（DeepSeek 等按工作日划分的服务商为此行为）。
    @Published var weekendIsOffPeak: Bool {
        didSet { defaults.set(weekendIsOffPeak, forKey: "weekendIsOffPeak") }
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

        scheduleEnabled = defaults.object(forKey: "scheduleEnabled") as? Bool ?? false
        offPeakBaseURL = defaults.string(forKey: "offPeakBaseURL") ?? ""
        offPeakModel = defaults.string(forKey: "offPeakModel") ?? ""
        offPeakAPIKey = loadAPIKey ? Keychain.load(account: Keychain.offPeakAccount) : ""
        peakStart1 = defaults.object(forKey: "peakStart1") as? Int ?? 9 * 60
        peakEnd1 = defaults.object(forKey: "peakEnd1") as? Int ?? 12 * 60
        peakStart2 = defaults.object(forKey: "peakStart2") as? Int ?? 14 * 60
        peakEnd2 = defaults.object(forKey: "peakEnd2") as? Int ?? 18 * 60
        weekendIsOffPeak = defaults.object(forKey: "weekendIsOffPeak") as? Bool ?? true
    }

    // MARK: 时段判断

    var offPeakConfigured: Bool {
        !offPeakBaseURL.trimmingCharacters(in: .whitespaces).isEmpty
            && !offPeakModel.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func currentTier(at date: Date = Date(), calendar: Calendar = .current) -> ModelTier {
        if weekendIsOffPeak {
            let weekday = calendar.component(.weekday, from: date) // 1 = 周日，7 = 周六
            if weekday == 1 || weekday == 7 { return .offPeak }
        }
        let minutes = calendar.component(.hour, from: date) * 60
            + calendar.component(.minute, from: date)
        let ranges = [(peakStart1, peakEnd1), (peakStart2, peakEnd2)]
        let isPeak = ranges.contains { range in
            range.0 < range.1 && minutes >= range.0 && minutes < range.1
        }
        return isPeak ? .peak : .offPeak
    }

    /// 实际使用的档位：未开启调度或谷时配置不完整时，一律使用主配置。
    var activeTier: ModelTier {
        guard scheduleEnabled, offPeakConfigured else { return .peak }
        return currentTier()
    }

    var activeTierSummary: String {
        guard scheduleEnabled else { return "未启用" }
        guard offPeakConfigured else { return "\(currentTier().title) · 谷时配置未填写，沿用主配置" }
        let activeModel = activeTier == .offPeak ? offPeakModel : model
        return "\(activeTier.title) · \(activeModel)"
    }

    var isConfigured: Bool {
        !config.baseURL.trimmingCharacters(in: .whitespaces).isEmpty
            && !config.model.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var config: TranslatorConfig {
        if activeTier == .offPeak {
            return TranslatorConfig(
                baseURL: offPeakBaseURL,
                apiKey: offPeakAPIKey,
                model: offPeakModel,
                targetMode: targetMode
            )
        }
        return TranslatorConfig(
            baseURL: baseURL,
            apiKey: apiKey,
            model: model,
            targetMode: targetMode
        )
    }
}
