import AppKit
import SwiftUI
import Combine
import Carbon.HIToolbox

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    private let settings = AppSettings()
    private lazy var permissions = PermissionsModel()

    private var statusItem: NSStatusItem!
    private var mainController: PanelController!
    private var popupController: PanelController!
    private var settingsWindow: NSWindow?

    private lazy var mainVM = TranslateViewModel(settings: settings)
    private lazy var popupVM = TranslateViewModel(settings: settings)

    private var mainHotKeyID: UInt32?
    private var selectionHotKeyID: UInt32?
    private var keyMonitor: Any?
    private var outsideClickMonitor: Any?
    private var mainOutsideMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    private let mainSize = NSSize(width: 780, height: 550)
    private let popupSize = NSSize(width: 420, height: 310)

    // MARK: 启动

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        setupApplicationMenu()
        setupStatusItem()
        setupPanels()
        setupHotKeys()
        setupKeyMonitor()
        observeSettings()

        DispatchQueue.main.async { [weak self] in self?.showMain() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMain()
        return true
    }

    private func setupApplicationMenu() {
        let bar = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "墨译")
        appMenu.addItem(withTitle: "设置…", action: #selector(menuOpenSettings), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出墨译", action: #selector(menuQuit), keyEquivalent: "q").target = self
        appItem.submenu = appMenu
        bar.addItem(appItem)
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        let commands: [(String, String, String)] = [
            ("撤销", "undo:", "z"), ("重做", "redo:", "Z"),
            ("剪切", "cut:", "x"), ("复制", "copy:", "c"),
            ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")
        ]
        for (title, selector, key) in commands {
            editMenu.addItem(withTitle: title, action: Selector(selector), keyEquivalent: key)
        }
        editItem.submenu = editMenu
        bar.addItem(editItem)
        NSApp.mainMenu = bar
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotKeyCenter.shared.unregisterAll()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        if let mainOutsideMonitor { NSEvent.removeMonitor(mainOutsideMonitor) }
    }

    // MARK: 状态栏

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        let image = NSImage(systemSymbolName: "character.bubble", accessibilityDescription: "墨译")
        image?.isTemplate = true
        button.image = image
        button.toolTip = "墨译 · \(settings.hotKeyPreset.title) 划词翻译"
        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showStatusMenu()
        } else {
            toggleMain()
        }
    }

    private func showStatusMenu() {
        let menu = NSMenu()

        let panelItem = NSMenuItem(title: "翻译面板（⌥A）", action: #selector(menuOpenPanel), keyEquivalent: "")
        panelItem.target = self
        menu.addItem(panelItem)

        let selectionItem = NSMenuItem(
            title: "翻译选中文字（\(settings.hotKeyPreset.title)）",
            action: #selector(menuTranslateSelection),
            keyEquivalent: ""
        )
        selectionItem.target = self
        menu.addItem(selectionItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "设置…", action: #selector(menuOpenSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(title: "退出墨译", action: #selector(menuQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        if let button = statusItem.button {
            menu.popUp(
                positioning: nil,
                at: NSPoint(x: 0, y: button.bounds.height + 4),
                in: button
            )
        }
    }

    @objc private func menuOpenPanel() { showMain() }
    @objc private func menuTranslateSelection() { translateSelection() }
    @objc private func menuOpenSettings() { openSettings() }
    @objc private func menuQuit() { NSApp.terminate(nil) }

    // MARK: 面板

    private func setupPanels() {
        mainController = PanelController(
            size: mainSize,
            nonactivating: true,
            allowsKey: true,
            content: TranslateView(
                vm: mainVM,
                settings: settings,
                permissions: permissions,
                onOpenSettings: { [weak self] in self?.openSettings() },
                onClose: { [weak self] in self?.hideMain() }
            )
        )
        mainController.panel.styleMask.insert(.resizable)
        mainController.panel.minSize = NSSize(width: 560, height: 520)
        mainController.panel.setFrameAutosaveName("MoTranslateMainPanel")
        mainController.panel.title = "墨译"
        // 主面板不因失焦自动关闭，避免系统抢焦点时窗口闪退；
        // 改为点击面板外部或按 esc 关闭。
        mainController.panel.onResignKey = nil

        popupController = PanelController(
            size: popupSize,
            nonactivating: true,
            allowsKey: true,
            content: PopupView(
                vm: popupVM,
                onClose: { [weak self] in self?.hidePopup() }
            )
        )
        popupVM.onReplaced = { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self?.hidePopup()
            }
        }
    }

    private func toggleMain() {
        if mainController.panel.isVisible {
            hideMain()
        } else {
            showMain()
        }
    }

    private func showMain() {
        hidePopup()
        mainVM.fillFromClipboardIfNeeded()
        // 先切到 regular，Dock 才会把本应用显示为运行中，并能从 Dock 直接退出。
        NSApp.setActivationPolicy(.regular)
        mainController.showCentered()
        mainVM.requestFocus()
        installMainOutsideMonitor()
    }

    private func hideMain(refreshPolicy: Bool = true) {
        mainController.hide()
        if let mainOutsideMonitor {
            NSEvent.removeMonitor(mainOutsideMonitor)
            self.mainOutsideMonitor = nil
        }
        if refreshPolicy { refreshActivationPolicy() }
    }

    /// 主面板或设置窗口可见时使用 regular（Dock 图标带运行状态、可退出）；
    /// 全部收起后回到 accessory，保留菜单栏常驻而不长期占用 Dock。
    private func refreshActivationPolicy() {
        let hasWindow = mainController?.panel.isVisible == true
            || settingsWindow?.isVisible == true
        let policy: NSApplication.ActivationPolicy = hasWindow ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
    }

    /// 点击主面板外部时关闭
    private func installMainOutsideMonitor() {
        if mainOutsideMonitor != nil { return }
        mainOutsideMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            guard let self else { return }
            let point = NSEvent.mouseLocation
            if !self.settings.keepPanelOpen, !self.mainController.panel.frame.contains(point) {
                DispatchQueue.main.async { self.hideMain() }
            }
        }
    }

    private func showPopup() {
        popupController.showNearMouse(size: popupSize)
        installOutsideClickMonitor()
    }

    private func hidePopup() {
        popupController.hide()
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
    }

    /// 点击浮窗外部时自动收起
    private func installOutsideClickMonitor() {
        if outsideClickMonitor != nil { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            guard let self else { return }
            let point = NSEvent.mouseLocation
            let frame = self.popupController.panel.frame
            if !frame.contains(point) {
                DispatchQueue.main.async { self.hidePopup() }
            }
        }
    }

    // MARK: 划词翻译

    @objc private func translateSelection() {
        guard SelectionService.isTrusted else {
            promptAccessibility()
            return
        }

        let pid = SelectionService.frontmostPID()
        let element = SelectionService.currentFocusedElement()

        if let text = SelectionService.selectedText(from: element) {
            showSelectionResult(text: text, pid: pid, element: element)
            return
        }

        guard let pid else {
            showNoSelection()
            return
        }

        // AX 读不到时退回模拟 ⌘C
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let text = SelectionService.selectedTextViaCopy(in: pid)
            DispatchQueue.main.async {
                if let text {
                    self?.showSelectionResult(text: text, pid: pid, element: nil)
                } else {
                    self?.showNoSelection()
                }
            }
        }
    }

    private func showSelectionResult(text: String, pid: pid_t?, element: AXUIElement?) {
        popupVM.beginSelectionTranslation(text: text, pid: pid, element: element)
        showPopup()
    }

    private func showNoSelection() {
        popupVM.showNoSelection()
        showPopup()
    }

    private func promptAccessibility() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "需要“辅助功能”权限"
        alert.informativeText = """
        划词翻译要读取其他 App 中选中的文字，并把译文贴回去，这需要辅助功能权限。

        请在「系统设置 → 隐私与安全性 → 辅助功能」中勾选墨译，然后重新启动应用。
        """
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后")
        if alert.runModal() == .alertFirstButtonReturn {
            SelectionService.promptForTrust()
            SelectionService.openAccessibilitySettings()
        }
    }

    // MARK: 设置

    private func openSettings() {
        hidePopup()
        hideMain(refreshPolicy: false)

        if settingsWindow == nil {
            let host = NSHostingController(
                rootView: SettingsView(
                    settings: settings,
                    permissions: permissions,
                    onClose: { [weak self] in self?.closeSettings() }
                )
            )
            let window = NSWindow(contentViewController: host)
            window.title = "墨译设置"
            window.titlebarAppearsTransparent = true
            window.toolbarStyle = .unified
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 620, height: 660))
            window.minSize = NSSize(width: 560, height: 500)
            window.center()
            window.isReleasedWhenClosed = false
            window.delegate = self
            settingsWindow = window
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
        refreshActivationPolicy()
    }

    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === settingsWindow else { return }
        // 关闭动画结束前 isVisible 仍为 true，下一轮再决定是否退回菜单栏模式。
        DispatchQueue.main.async { [weak self] in self?.refreshActivationPolicy() }
    }

    /// 设置里的「返回」：关闭设置并回到翻译面板。
    private func closeSettings() {
        settingsWindow?.close()
        showMain()
    }

    // MARK: 热键

    private func setupHotKeys() {
        // ⌥A：避开 ChatGPT / Raycast 的 ⌥Space 与系统 Finder 的 ⌃⌥Space
        mainHotKeyID = HotKeyCenter.shared.register(
            keyCode: UInt32(kVK_ANSI_A),
            modifiers: UInt32(optionKey)
        ) { [weak self] in
            self?.toggleMain()
        }

        registerSelectionHotKey()
    }

    private func registerSelectionHotKey() {
        if let selectionHotKeyID {
            HotKeyCenter.shared.unregister(selectionHotKeyID)
        }
        let preset = settings.hotKeyPreset
        selectionHotKeyID = HotKeyCenter.shared.register(
            keyCode: preset.keyCode,
            modifiers: preset.modifiers
        ) { [weak self] in
            self?.translateSelection()
        }
        statusItem?.button?.toolTip = "墨译 · \(preset.title) 划词翻译"
    }

    private func observeSettings() {
        settings.$hotKeyPreset
            .dropFirst()
            .sink { [weak self] _ in
                self?.registerSelectionHotKey()
            }
            .store(in: &cancellables)
    }

    // MARK: 键盘

    private func setupKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            if flags.contains(.command), event.charactersIgnoringModifiers == "," {
                self.openSettings()
                return nil
            }
            if self.mainController.panel.isKeyWindow {
                if flags.contains(.command), event.charactersIgnoringModifiers == "k" {
                    self.mainVM.reset()
                    self.mainVM.requestFocus()
                    return nil
                }
                if flags.contains(.command), event.charactersIgnoringModifiers == "w" {
                    self.hideMain()
                    return nil
                }
                if event.keyCode == 53 { // esc
                    self.hideMain()
                    return nil
                }
                if event.keyCode == 36, flags.contains(.command) { // ⌘⏎
                    self.mainVM.startTranslation()
                    return nil
                }
                if event.keyCode == 8, flags.contains(.command), flags.contains(.shift) { // ⌘⇧C
                    self.mainVM.copyOutput()
                    return nil
                }
            }

            if self.popupController.panel.isKeyWindow {
                if event.keyCode == 53 {
                    self.hidePopup()
                    return nil
                }
                if event.keyCode == 8, flags.contains(.command), flags.contains(.shift) {
                    self.popupVM.copyOutput()
                    return nil
                }
            }

            return event
        }
    }
}
