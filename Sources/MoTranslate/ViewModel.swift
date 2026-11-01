import AppKit
import SwiftUI

// MARK: - 翻译状态

@MainActor
final class TranslateViewModel: ObservableObject {
    @Published var input = ""
    @Published var output = ""
    @Published var isWorking = false
    @Published var errorText: String?
    @Published var sourceLabel = ""
    @Published var targetLabel = ""
    @Published var progressText: String?
    @Published var progressValue: Double?
    @Published var activeModelLabel = ""
    @Published var copied = false
    @Published var replaced = false
    @Published var focusTick = 0

    /// 划词翻译发生时的目标进程，用于把译文贴回去
    var targetPID: pid_t?
    /// 划词时的焦点元素，优先直接写回，避免抢焦点和覆盖剪贴板
    var targetElement: AXUIElement?
    /// 完成替换后的回调（用于收起浮窗）
    var onReplaced: (() -> Void)?

    private let settings: AppSettings
    private var currentTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private var generation = 0

    private let translate: (String, TranslatorConfig, TranslationOptions, ((Int, Int) -> Void)?, ((String) -> Void)?) async throws -> TranslationResult

    init(settings: AppSettings,
         translate: @escaping (String, TranslatorConfig, TranslationOptions, ((Int, Int) -> Void)?, ((String) -> Void)?) async throws -> TranslationResult = Translator.translate) {
        self.settings = settings
        self.translate = translate
    }

    var hasOutput: Bool { !output.isEmpty }

    var directionLabel: String {
        let source = sourceLabel.isEmpty ? "自动" : sourceLabel
        let target = targetLabel.isEmpty ? (settings.targetMode == .auto ? "中文 / English" : settings.targetMode.shortTitle) : targetLabel
        return "\(source) → \(target)"
    }

    func inputChanged() {
        cancelTranslation()
        output = ""
        errorText = nil
        copied = false
        replaced = false
        sourceLabel = ""
        targetLabel = ""
        guard settings.autoTranslate else { return }
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            self?.startTranslation()
        }
    }

    func startTranslation() {
        debounceTask?.cancel()
        cancelTranslation()
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            output = ""
            errorText = nil
            return
        }

        guard settings.isConfigured else {
            errorText = TranslationError.notConfigured.errorDescription
            return
        }

        generation += 1
        let currentGeneration = generation
        currentTask?.cancel()
        errorText = nil
        output = ""
        copied = false
        replaced = false
        progressText = nil
        progressValue = nil
        isWorking = true

        let config = settings.config
        let options = TranslationOptions(
            chunking: settings.chunkingEnabled,
            streaming: settings.streamingEnabled,
            markdown: settings.markdownEnabled,
            style: settings.style
        )
        activeModelLabel = config.model
        currentTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.translate(text, config, options, { [weak self] current, total in
                    DispatchQueue.main.async {
                        guard let self, currentGeneration == self.generation else { return }
                        self.progressText = "正在翻译 \(current)/\(total) 段"
                        self.progressValue = total > 0 ? Double(current) / Double(total) : nil
                    }
                }, { [weak self] partial in
                    DispatchQueue.main.async {
                        guard let self, currentGeneration == self.generation, self.isWorking else { return }
                        self.output = partial
                    }
                })
                guard !Task.isCancelled, currentGeneration == self.generation else { return }
                self.isWorking = false
                self.output = result.text
                self.sourceLabel = Translator.displayName(result.sourceCode)
                self.targetLabel = Translator.displayName(result.targetCode)
                self.progressText = nil
                self.progressValue = nil
            } catch is CancellationError {
                // 被新请求取代，保持新请求的状态
            } catch {
                guard !Task.isCancelled, currentGeneration == self.generation else { return }
                self.isWorking = false
                self.progressText = nil
                self.progressValue = nil
                self.errorText = error.localizedDescription
            }
        }
    }

    func cancelTranslation() {
        generation += 1
        currentTask?.cancel()
        debounceTask?.cancel()
        progressText = nil
        progressValue = nil
        isWorking = false
    }

    func targetChanged() {
        cancelTranslation()
        output = ""
        sourceLabel = ""
        targetLabel = ""
        if settings.autoTranslate { startTranslation() }
    }

    func pasteInput() {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        input = text
    }

    func useOutputAsInput() {
        guard hasOutput else { return }
        let text = output
        reset()
        input = text
    }

    func copyOutput() {
        guard hasOutput else { return }
        SelectionService.copyToClipboard(output)
        copied = true
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            self?.copied = false
        }
    }

    /// 把译文替换回原来的选区
    func replaceBack() {
        guard hasOutput else { return }

        // 首选：通过辅助功能直接写入选区，不碰剪贴板、不切前台
        if let element = targetElement,
           SelectionService.writeSelection(output, into: element) {
            replaced = true
            onReplaced?()
            return
        }

        guard let pid = targetPID else { return }
        replaced = true

        // 兜底：激活目标 App 后模拟粘贴
        if let app = NSRunningApplication(processIdentifier: pid) {
            app.activate(options: [.activateAllWindows])
        }
        let text = output
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            SelectionService.replaceSelection(with: text, in: pid)
            self?.onReplaced?()
        }
    }

    /// 划词入口：填入原文并立即翻译
    func beginSelectionTranslation(text: String, pid: pid_t?, element: AXUIElement?) {
        targetPID = pid
        targetElement = element
        input = text
        output = ""
        errorText = nil
        replaced = false
        startTranslation()
    }

    func showNoSelection() {
        cancelTranslation()
        targetPID = nil
        targetElement = nil
        input = ""
        output = ""
        isWorking = false
        progressText = nil
        progressValue = nil
        replaced = false
        errorText = "没有检测到选中的文字。先选中内容，再按快捷键。"
    }

    func reset() {
        currentTask?.cancel()
        debounceTask?.cancel()
        generation += 1
        input = ""
        output = ""
        errorText = nil
        sourceLabel = ""
        targetLabel = ""
        progressText = nil
        progressValue = nil
        activeModelLabel = ""
        isWorking = false
        copied = false
        replaced = false
        targetPID = nil
        targetElement = nil
    }

    func fillFromClipboardIfNeeded() {
        guard settings.fillFromClipboard, input.isEmpty else { return }
        guard let text = NSPasteboard.general.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        input = String(text.prefix(4000))
        if settings.autoTranslate { startTranslation() }
    }

    func requestFocus() {
        focusTick += 1
    }
}

// MARK: - 面板

/// 无标题栏圆角面板。主面板可成为 key 窗口用于输入；
/// 划词浮窗不抢焦点，避免破坏原 App 的选区。
final class FloatingPanel: NSPanel {
    var onResignKey: (() -> Void)?
    var allowsKey = true

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }

    /// 点击面板内部时才成为 key，避免显示瞬间抢走原 App 的焦点
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, !isKeyWindow, allowsKey {
            makeKey()
        }
        super.sendEvent(event)
    }
}

final class PanelController {
    let panel: FloatingPanel

    init<Content: View>(
        size: NSSize,
        nonactivating: Bool,
        allowsKey: Bool? = nil,
        content: Content
    ) {
        var style: NSWindow.StyleMask = [.titled, .fullSizeContentView, .closable]
        if nonactivating {
            style.insert(.nonactivatingPanel)
        }

        panel = FloatingPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: style,
            backing: .buffered,
            defer: false
        )
        panel.allowsKey = allowsKey ?? !nonactivating
        panel.isReleasedWhenClosed = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .utilityWindow
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.contentView = NSHostingView(rootView: content.ignoresSafeArea())
    }

    /// 主面板：居中显示并取得键盘焦点
    func showCentered() {
        if !panel.isVisible { centerOnActiveScreen() }
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(panel.contentView)
    }

    /// 浮窗：显示在鼠标附近，不抢焦点
    func showNearMouse(size: NSSize) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else {
            panel.setContentSize(size)
            panel.orderFrontRegardless()
            return
        }

        var x = mouse.x + 12
        var y = mouse.y - size.height - 12

        if x + size.width > visible.maxX {
            x = mouse.x - size.width - 12
        }
        if y < visible.minY + 8 {
            y = mouse.y + 16
        }
        x = max(visible.minX + 8, min(x, visible.maxX - size.width - 8))
        y = max(visible.minY + 8, min(y, visible.maxY - size.height - 8))

        panel.setContentSize(size)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    private func centerOnActiveScreen() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = panel.frame.size
        let x = visible.midX - size.width / 2
        let y = visible.midY - size.height / 2 + visible.height * 0.08
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
