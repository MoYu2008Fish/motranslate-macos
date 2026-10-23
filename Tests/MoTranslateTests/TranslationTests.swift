import Testing
import Foundation
@testable import MoTranslate

@Test func languageRouting() {
    #expect(Translator.resolveTarget(sourceCode: "zh-Hant", mode: .auto) == "en")
    #expect(Translator.resolveTarget(sourceCode: "ja", mode: .auto) == "zh-Hans")
    #expect(Translator.resolveTarget(sourceCode: "en", mode: .english) == "en")
    #expect(Translator.detectLanguage("这是一段中文 mixed with English") == "zh-Hans")
}

@Test func endpointNormalization() {
    #expect(Translator.endpoint(from: " example.com/v1/ ")?.absoluteString == "https://example.com/v1/chat/completions")
    #expect(Translator.endpoint(from: "http://localhost:11434")?.absoluteString == "http://localhost:11434/v1/chat/completions")
    #expect(Translator.endpoint(from: "https://example.com/v1/chat/completions")?.absoluteString == "https://example.com/v1/chat/completions")
    #expect(Translator.endpoint(from: "") == nil)
}

@MainActor private func fixture() -> (AppSettings, UserDefaults, String) {
    let name = "MoTranslateTests." + UUID().uuidString
    let defaults = UserDefaults(suiteName: name)!
    let settings = AppSettings(defaults: defaults, loadAPIKey: false)
    settings.baseURL = "http://localhost:12345/v1"
    settings.model = "test"
    settings.autoTranslate = false
    return (settings, defaults, name)
}

@MainActor @Test func editingCancelsStaleResults() async throws {
    let (settings, defaults, name) = fixture()
    defer { defaults.removePersistentDomain(forName: name) }
    let vm = TranslateViewModel(settings: settings) { text, _ in
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
    let vm = TranslateViewModel(settings: settings) { _, _ in
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
    let vm = TranslateViewModel(settings: settings) { text, _ in
        try Task.checkCancellation()
        return TranslationResult(text: "translated " + text, sourceCode: "en", targetCode: "zh-Hans")
    }
    vm.input = "hello"
    vm.inputChanged()
    try await Task.sleep(for: .milliseconds(850))
    #expect(vm.output == "translated hello")
    #expect(!vm.isWorking)
}
