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

// MARK: - 翻译风格

enum TranslationStyle: String, CaseIterable, Identifiable {
    case natural
    case precise
    case plain
    case colloquial
    case concise

    var id: String { rawValue }

    var title: String {
        switch self {
        case .natural: return "自然"
        case .precise: return "严谨"
        case .plain: return "大白话"
        case .colloquial: return "口语"
        case .concise: return "精简 + 总结"
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

    /// 旧版本的两个固定密钥条目，仅用于升级时迁移。
    static let legacyMainAccount = "openai-api-key"
    static let legacyOffPeakAccount = "offpeak-api-key"

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    static func load(account: String) -> String {
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

    static func save(_ value: String, account: String) {
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

    // MARK: 模型库

    @Published private(set) var customModels: [ModelEntry] {
        didSet { persistCustomModels() }
    }

    @Published var primaryEntryID: String {
        didSet { defaults.set(primaryEntryID, forKey: "primaryEntryID") }
    }

    /// 谷时使用的模型；空字符串表示未设置，此时沿用主接口。
    @Published var offPeakEntryID: String {
        didSet { defaults.set(offPeakEntryID, forKey: "offPeakEntryID") }
    }

    /// 按服务商缓存的 API Key，实际值存放在系统钥匙串。
    @Published private(set) var apiKeys: [String: String] = [:]

    /// 主面板手动选择的模型：只保留在本次运行内，重启后恢复按峰谷规则切换。
    @Published private(set) var manualEntryID: String?

    // MARK: 其他设置

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

    /// 长文本按 Markdown 结构分段翻译，逐段显示结果。
    @Published var chunkingEnabled: Bool {
        didSet { defaults.set(chunkingEnabled, forKey: "chunkingEnabled") }
    }

    /// 流式接收译文，边生成边显示。
    @Published var streamingEnabled: Bool {
        didSet { defaults.set(streamingEnabled, forKey: "streamingEnabled") }
    }

    /// 翻译风格：自然、严谨、大白话、精简加总结。
    @Published var style: TranslationStyle {
        didSet { defaults.set(style.rawValue, forKey: "translationStyle") }
    }

    /// 识别 Markdown 结构并在提示词中要求保留语法。
    @Published var markdownEnabled: Bool {
        didSet { defaults.set(markdownEnabled, forKey: "markdownEnabled") }
    }

    // MARK: 峰谷调度

    @Published var scheduleEnabled: Bool {
        didSet { defaults.set(scheduleEnabled, forKey: "scheduleEnabled") }
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

        let storedMode = defaults.string(forKey: "targetMode") ?? ""
        let storedPreset = defaults.string(forKey: "hotKeyPreset") ?? ""

        keepPanelOpen = defaults.bool(forKey: "keepPanelOpen")
        targetMode = TargetMode(rawValue: storedMode) ?? .auto
        hotKeyPreset = HotKeyPreset(rawValue: storedPreset) ?? .optionD
        autoTranslate = defaults.object(forKey: "autoTranslate") as? Bool ?? true
        fillFromClipboard = defaults.object(forKey: "fillFromClipboard") as? Bool ?? true
        chunkingEnabled = defaults.object(forKey: "chunkingEnabled") as? Bool ?? true
        streamingEnabled = defaults.object(forKey: "streamingEnabled") as? Bool ?? true
        style = TranslationStyle(rawValue: defaults.string(forKey: "translationStyle") ?? "") ?? .natural
        markdownEnabled = defaults.object(forKey: "markdownEnabled") as? Bool ?? true

        scheduleEnabled = defaults.object(forKey: "scheduleEnabled") as? Bool ?? false
        peakStart1 = defaults.object(forKey: "peakStart1") as? Int ?? 9 * 60
        peakEnd1 = defaults.object(forKey: "peakEnd1") as? Int ?? 12 * 60
        peakStart2 = defaults.object(forKey: "peakStart2") as? Int ?? 14 * 60
        peakEnd2 = defaults.object(forKey: "peakEnd2") as? Int ?? 18 * 60
        weekendIsOffPeak = defaults.object(forKey: "weekendIsOffPeak") as? Bool ?? true

        var custom = (defaults.data(forKey: "customModels").flatMap {
            try? JSONDecoder().decode([ModelEntry].self, from: $0)
        }) ?? []

        var primaryID = defaults.string(forKey: "primaryEntryID") ?? ""
        var offPeakID = defaults.string(forKey: "offPeakEntryID") ?? ""

        // 旧版本的 baseURL / model 字段迁移为模型库条目。
        let storedURL = defaults.string(forKey: "baseURL") ?? ""
        let storedModel = defaults.string(forKey: "model") ?? ""
        let storedOffPeakURL = defaults.string(forKey: "offPeakBaseURL") ?? ""
        let storedOffPeakModel = defaults.string(forKey: "offPeakModel") ?? ""

        func migratedEntry(url: String, model: String) -> ModelEntry {
            ModelEntry(
                id: "custom-" + Self.stableID("\(url)|\(model)"),
                name: model,
                baseURL: url,
                model: model,
                isBuiltIn: false
            )
        }

        if !custom.contains(where: { $0.id == primaryID }) {
            if !storedURL.isEmpty, !storedModel.isEmpty {
                if let preset = ModelLibrary.preset(baseURL: storedURL, model: storedModel) {
                    custom.append(preset.saved)
                    primaryID = preset.id
                } else {
                    let entry = migratedEntry(url: storedURL, model: storedModel)
                    custom.removeAll { $0.id == entry.id }
                    custom.append(entry)
                    primaryID = entry.id
                }
            } else if let fallback = ModelLibrary.preset(ModelLibrary.defaultEntryID) {
                custom.append(fallback.saved)
                primaryID = fallback.id
            }
        }

        if !offPeakID.isEmpty, !custom.contains(where: { $0.id == offPeakID }) {
            offPeakID = ""
        }
        if offPeakID.isEmpty, !storedOffPeakURL.isEmpty, !storedOffPeakModel.isEmpty {
            if let preset = ModelLibrary.preset(baseURL: storedOffPeakURL, model: storedOffPeakModel) {
                if !custom.contains(where: { $0.id == preset.id }) { custom.append(preset.saved) }
                offPeakID = preset.id
            } else {
                let entry = migratedEntry(url: storedOffPeakURL, model: storedOffPeakModel)
                custom.removeAll { $0.id == entry.id }
                custom.append(entry)
                offPeakID = entry.id
            }
        }

        self.customModels = custom
        self.primaryEntryID = primaryID
        self.offPeakEntryID = offPeakID
        self.manualEntryID = nil
        self.apiKeys = [:]

        if loadAPIKey {
            migrateLegacyKey(Keychain.legacyMainAccount, to: custom.first { $0.id == primaryID }?.keyAccount)
            migrateLegacyKey(Keychain.legacyOffPeakAccount, to: custom.first { $0.id == offPeakID }?.keyAccount)

            var keys: [String: String] = [:]
            for entry in custom {
                let value = Keychain.load(account: "api-key:" + entry.keyAccount)
                if !value.isEmpty { keys[entry.keyAccount] = value }
            }
            self.apiKeys = keys
        }

        // init 中的赋值不会触发 didSet，迁移结果需要显式写回。
        defaults.set(primaryID, forKey: "primaryEntryID")
        defaults.set(offPeakID, forKey: "offPeakEntryID")
        persistCustomModels()
    }

    // MARK: 模型库

    /// 只包含用户添加过的模型；内置预设不会自动出现在这里。
    var library: [ModelEntry] { customModels }

    var presets: [ModelEntry] { ModelLibrary.all }

    func entry(_ id: String) -> ModelEntry? {
        customModels.first { $0.id == id }
    }

    var primaryEntry: ModelEntry? {
        entry(primaryEntryID) ?? customModels.first
    }

    var offPeakEntry: ModelEntry? {
        offPeakEntryID.isEmpty ? nil : entry(offPeakEntryID)
    }

    /// 从内置预设添加模型到库；重复添加时返回已有条目。
    @discardableResult
    func addPreset(_ preset: ModelEntry) -> ModelEntry {
        if let existing = customModels.first(where: { $0.id == preset.id }) { return existing }
        let entry = preset.saved
        customModels.append(entry)
        return entry
    }

    @discardableResult
    func addCustomModel(name: String, baseURL: String, model: String) -> ModelEntry? {
        let url = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let identifier = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty, !identifier.isEmpty else { return nil }

        let entry = ModelEntry(
            id: "custom-" + Self.stableID("\(url)|\(identifier)"),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? identifier : name.trimmingCharacters(in: .whitespacesAndNewlines),
            baseURL: url,
            model: identifier,
            isBuiltIn: false
        )
        if let index = customModels.firstIndex(where: { $0.baseURL == url && $0.model == identifier }) {
            customModels[index] = entry
        } else if let index = customModels.firstIndex(where: { $0.id == entry.id }) {
            customModels[index] = entry
        } else {
            customModels.append(entry)
        }
        return entry
    }

    func removeCustomModel(_ id: String) {
        customModels.removeAll { $0.id == id }
        if primaryEntryID == id, let fallback = library.first(where: { $0.id == ModelLibrary.defaultEntryID }) ?? library.first {
            primaryEntryID = fallback.id
        }
        if offPeakEntryID == id { offPeakEntryID = "" }
        if manualEntryID == id { manualEntryID = nil }
    }

    // MARK: API Key

    func apiKey(for account: String) -> String { apiKeys[account] ?? "" }

    func setAPIKey(_ value: String, for account: String) {
        apiKeys[account] = value
        Keychain.save(value, account: "api-key:" + account)
    }

    // MARK: 模型选择

    var activeEntry: ModelEntry? {
        if let manualEntryID, let selected = entry(manualEntryID) { return selected }
        if scheduleEnabled, offPeakEntry != nil, currentTier() == .offPeak { return offPeakEntry }
        return primaryEntry
    }

    var activeModelName: String { activeEntry?.model ?? "" }

    var isManualModel: Bool { manualEntryID != nil }

    func selectModel(_ id: String) {
        manualEntryID = id
    }

    func clearManualModel() {
        manualEntryID = nil
    }

    var activeTierSummary: String {
        if manualEntryID != nil { return "手动 · \(activeModelName)" }
        guard scheduleEnabled, offPeakEntry != nil else { return "未启用" }
        return "\(currentTier().title) · \(activeModelName)"
    }

    // MARK: 时段判断

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

    var isConfigured: Bool {
        guard let entry = activeEntry else { return false }
        return !entry.baseURL.trimmingCharacters(in: .whitespaces).isEmpty
            && !entry.model.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var config: TranslatorConfig {
        guard let entry = activeEntry else {
            return TranslatorConfig(baseURL: "", apiKey: "", model: "", targetMode: targetMode)
        }
        return TranslatorConfig(
            baseURL: entry.baseURL,
            apiKey: apiKey(for: entry.keyAccount),
            model: entry.model,
            targetMode: targetMode
        )
    }

    // MARK: 私有

    private func persistCustomModels() {
        guard let data = try? JSONEncoder().encode(customModels) else { return }
        defaults.set(data, forKey: "customModels")
    }

    private func migrateLegacyKey(_ legacyAccount: String, to account: String?) {
        guard let account, !account.isEmpty else { return }
        let legacy = Keychain.load(account: legacyAccount)
        guard !legacy.isEmpty else { return }
        if Keychain.load(account: "api-key:" + account).isEmpty {
            Keychain.save(legacy, account: "api-key:" + account)
        }
    }

    /// 让迁移生成的条目 id 在多次启动之间保持稳定。
    private static func stableID(_ value: String) -> String {
        var hash: UInt64 = 5381
        for byte in value.utf8 {
            hash = (hash &* 33) ^ UInt64(byte)
        }
        return String(hash, radix: 16)
    }
}
