import Testing
import Foundation
@testable import MoTranslate

@Test func languageRouting() {
    #expect(Translator.resolveTarget(sourceCode: "zh-Hant", mode: .auto) == "en")
    #expect(Translator.resolveTarget(sourceCode: "ja", mode: .auto) == "zh-Hans")
    #expect(Translator.resolveTarget(sourceCode: "en", mode: .english) == "en")
    #expect(Translator.detectLanguage("这是一段中文 mixed with English") == "zh-Hans")
}

@Test func mixedLanguageUsesDominantLanguage() {
    // 大段英文夹少量中文注释，应按英文处理，否则自动模式会翻错方向。
    let mostlyEnglish = "The quick brown fox jumps over the lazy dog. 备注：仅供参考。"
    #expect(Translator.detectLanguage(mostlyEnglish) == "en")
    #expect(Translator.resolveTarget(sourceCode: Translator.detectLanguage(mostlyEnglish), mode: .auto) == "zh-Hans")

    // 大段中文夹少量英文术语，仍按中文处理。
    let mostlyChinese = "这个接口返回的是 JSON 格式，需要先解析再渲染到页面上。"
    #expect(Translator.detectLanguage(mostlyChinese) == "zh-Hans")
    #expect(Translator.resolveTarget(sourceCode: Translator.detectLanguage(mostlyChinese), mode: .auto) == "en")
}

@Test func detectsJapaneseAndKorean() {
    #expect(Translator.detectLanguage("これはテストです") == "ja")
    #expect(Translator.detectLanguage("안녕하세요") == "ko")
}

@Test func endpointNormalization() {
    #expect(Translator.endpoint(from: " example.com/v1/ ")?.absoluteString == "https://example.com/v1/chat/completions")
    #expect(Translator.endpoint(from: "http://localhost:11434")?.absoluteString == "http://localhost:11434/v1/chat/completions")
    #expect(Translator.endpoint(from: "https://example.com/v1/chat/completions")?.absoluteString == "https://example.com/v1/chat/completions")
    // 智谱与 Gemini 的兼容端点已经带版本段，不能再拼一层 /v1。
    #expect(Translator.endpoint(from: "https://open.bigmodel.cn/api/paas/v4")?.absoluteString == "https://open.bigmodel.cn/api/paas/v4/chat/completions")
    #expect(Translator.endpoint(from: "https://generativelanguage.googleapis.com/v1beta/openai")?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")
    #expect(Translator.endpoint(from: "") == nil)
}

@MainActor private func fixture() -> (AppSettings, UserDefaults, String) {
    let name = "MoTranslateTests." + UUID().uuidString
    let defaults = UserDefaults(suiteName: name)!
    let settings = AppSettings(defaults: defaults, loadAPIKey: false)
    if let entry = settings.addCustomModel(name: "Test", baseURL: "http://localhost:12345/v1", model: "test") {
        settings.primaryEntryID = entry.id
    }
    settings.autoTranslate = false
    return (settings, defaults, name)
}

@MainActor @Test func editingCancelsStaleResults() async throws {
    let (settings, defaults, name) = fixture()
    defer { defaults.removePersistentDomain(forName: name) }
    let vm = TranslateViewModel(settings: settings) { text, _, _, _, _ in
        // Simulate a transport that returns even after cancellation.
        try? await Task.sleep(for: .milliseconds(40))
        return TranslationResult(text: "translated " + text, sourceCode: "en", targetCode: "zh-Hans")
    }
    vm.input = "old"
    vm.startTranslation()
    await Task.yield()
    vm.input = "new"
    vm.inputChanged()
    try await Task.sleep(for: .milliseconds(70))
    #expect(vm.output.isEmpty)
    #expect(!vm.isWorking)
    vm.startTranslation()
    try await Task.sleep(for: .milliseconds(70))
    #expect(vm.output == "translated new")
}

@MainActor @Test func emptyAndMissingSelectionInvalidateWork() async throws {
    let (settings, defaults, name) = fixture()
    defer { defaults.removePersistentDomain(forName: name) }
    let vm = TranslateViewModel(settings: settings) { _, _, _, _, _ in
        try? await Task.sleep(for: .milliseconds(40))
        return TranslationResult(text: "stale", sourceCode: "en", targetCode: "zh-Hans")
    }
    vm.input = "old"
    vm.startTranslation()
    await Task.yield()
    vm.showNoSelection()
    try await Task.sleep(for: .milliseconds(70))
    #expect(vm.output.isEmpty)
    #expect(vm.errorText != nil)
    vm.input = "old"
    vm.startTranslation()
    await Task.yield()
    vm.input = " "
    vm.startTranslation()
    try await Task.sleep(for: .milliseconds(70))
    #expect(vm.output.isEmpty)
    #expect(!vm.isWorking)
    vm.reset()
    #expect(vm.targetElement == nil)
    #expect(vm.errorText == nil)
}

@MainActor @Test func changingTargetClearsPreviousTranslation() {
    let (settings, defaults, name) = fixture()
    defer { defaults.removePersistentDomain(forName: name) }
    let vm = TranslateViewModel(settings: settings)
    vm.output = "old result"
    vm.targetLabel = "中文"
    settings.targetMode = .english
    vm.targetChanged()
    #expect(vm.output.isEmpty)
    #expect(vm.directionLabel == "自动 → 英文")
}

@MainActor @Test func automaticTranslationRunsAfterDebounce() async throws {
    let (settings, defaults, name) = fixture()
    defer { defaults.removePersistentDomain(forName: name) }
    settings.autoTranslate = true
    let vm = TranslateViewModel(settings: settings) { text, _, _, _, _ in
        try Task.checkCancellation()
        return TranslationResult(text: "translated " + text, sourceCode: "en", targetCode: "zh-Hans")
    }
    vm.input = "hello"
    vm.inputChanged()
    try await Task.sleep(for: .milliseconds(850))
    #expect(vm.output == "translated hello")
    #expect(!vm.isWorking)
}

@Test func splitsLongTextAndKeepsCodeBlocks() {
    let paragraph = String(repeating: "这是一段用于测试分段的文字。", count: 120)
    let text = "# 标题\n\n\(paragraph)\n\n```swift\nlet value = 1\n```\n\n结尾段落。"
    let chunks = TextSegmenter.chunks(from: text, maxCharacters: 1200)

    #expect(chunks.count > 1)
    #expect(chunks.contains { !$0.translatable && $0.text.contains("let value = 1") })
    // 分段不丢字符，拼接后能还原原文。
    #expect(chunks.map { $0.text + $0.trailing }.joined() == text)
}

@Test func detectsMarkdownStructures() {
    #expect(TextSegmenter.looksLikeMarkdown("# 标题\n\n正文。"))
    #expect(TextSegmenter.looksLikeMarkdown("示例：\n\n```js\nconsole.log(1)\n```"))
    #expect(TextSegmenter.looksLikeMarkdown("- 第一项\n- 第二项\n- 第三项"))
    #expect(TextSegmenter.looksLikeMarkdown("| A | B |\n| --- | --- |\n| 1 | 2 |"))
    #expect(!TextSegmenter.looksLikeMarkdown("这是一段普通的中文文本，没有任何标记。"))
}

@MainActor @Test func scheduleSwitchesTierByWeekdayAndHour() {
    let (settings, defaults, name) = fixture()
    defer { defaults.removePersistentDomain(forName: name) }

    settings.peakStart1 = 9 * 60
    settings.peakEnd1 = 12 * 60
    settings.peakStart2 = 14 * 60
    settings.peakEnd2 = 18 * 60
    settings.weekendIsOffPeak = true

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!

    let thursdayMorning = calendar.date(from: DateComponents(year: 2026, month: 10, day: 29, hour: 10))!
    let thursdayLunch = calendar.date(from: DateComponents(year: 2026, month: 10, day: 29, hour: 13))!
    let saturdayMorning = calendar.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 10))!

    #expect(settings.currentTier(at: thursdayMorning, calendar: calendar) == .peak)
    #expect(settings.currentTier(at: thursdayLunch, calendar: calendar) == .offPeak)
    #expect(settings.currentTier(at: saturdayMorning, calendar: calendar) == .offPeak)
}

@MainActor @Test func manualModelOverridesScheduleAndResetsOnRestart() {
    let (settings, defaults, name) = fixture()
    defer { defaults.removePersistentDomain(forName: name) }

    let local = settings.addCustomModel(name: "Local", baseURL: "http://localhost:11434/v1", model: "local-4b")!
    let cloud = settings.addCustomModel(name: "Cloud", baseURL: "https://api.deepseek.com/v1", model: "deepseek-chat")!
    settings.primaryEntryID = local.id
    settings.offPeakEntryID = cloud.id
    settings.scheduleEnabled = false

    #expect(settings.activeEntry?.id == local.id)
    #expect(settings.activeModelName == "local-4b")

    settings.selectModel(cloud.id)
    #expect(settings.isManualModel)
    #expect(settings.activeEntry?.id == cloud.id)
    #expect(settings.config.model == "deepseek-chat")

    settings.clearManualModel()
    #expect(!settings.isManualModel)
    #expect(settings.activeEntry?.id == local.id)

    // 手动选择只存在于本次运行内：新实例读同一份 defaults 时应恢复默认。
    settings.selectModel(cloud.id)
    let restarted = AppSettings(defaults: defaults, loadAPIKey: false)
    #expect(restarted.manualEntryID == nil)
    #expect(restarted.activeEntry?.id == local.id)
}

@MainActor @Test func customModelIsPersistedAndSelectable() {
    let (settings, defaults, name) = fixture()
    defer { defaults.removePersistentDomain(forName: name) }

    let entry = settings.addCustomModel(name: "自建", baseURL: "https://api.example.com/v1", model: "my-model")!
    settings.primaryEntryID = entry.id
    #expect(settings.customModels.contains { $0.id == entry.id })
    #expect(settings.activeEntry?.model == "my-model")

    let restarted = AppSettings(defaults: defaults, loadAPIKey: false)
    #expect(restarted.customModels.contains { $0.id == entry.id })
    #expect(restarted.primaryEntry?.model == "my-model")

    restarted.removeCustomModel(entry.id)
    #expect(!restarted.customModels.contains { $0.id == entry.id })
    #expect(restarted.primaryEntry != nil)
}

@MainActor @Test func presetsDoNotEnterLibraryUntilAdded() {
    let (settings, defaults, name) = fixture()
    defer { defaults.removePersistentDomain(forName: name) }

    // 内置预设只是模板，未添加前不应出现在模型库里。
    #expect(!settings.library.contains { $0.model == "gpt-6.1-terra" })
    #expect(settings.library.count < ModelLibrary.all.count)

    let preset = ModelLibrary.preset("deepseek-flash")!
    let added = settings.addPreset(preset)
    #expect(settings.library.contains { $0.id == added.id })
    #expect(settings.library.count == 3)

    // 重复添加同一条预设不会产生副本。
    settings.addPreset(preset)
    #expect(settings.library.count == 3)
}

@MainActor @Test func partialOutputAppearsDuringTranslation() async throws {
    let (settings, defaults, name) = fixture()
    defer { defaults.removePersistentDomain(forName: name) }

    let vm = TranslateViewModel(settings: settings) { _, _, _, _, partial in
        partial?("第一段")
        try? await Task.sleep(for: .milliseconds(60))
        return TranslationResult(text: "第一段第二段", sourceCode: "en", targetCode: "zh-Hans")
    }
    vm.input = "hello"
    vm.startTranslation()

    try await Task.sleep(for: .milliseconds(30))
    #expect(vm.output == "第一段")
    #expect(vm.isWorking)

    try await Task.sleep(for: .milliseconds(80))
    #expect(vm.output == "第一段第二段")
    #expect(!vm.isWorking)
}
