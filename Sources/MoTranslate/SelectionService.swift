import AppKit
import ApplicationServices
import Carbon.HIToolbox

// MARK: - 选区读取与本地替换

/// 通过辅助功能（Accessibility）读取任意 App 中选中的文字；
/// AX 不可用时用模拟 ⌘C 兜底。替换文字统一走模拟 ⌘V。
enum SelectionService {

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// 弹出系统授权提示；已授权时无副作用。
    static func promptForTrust() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        if let url { NSWorkspace.shared.open(url) }
    }

    static func frontmostPID() -> pid_t? {
        NSWorkspace.shared.frontmostApplication?.processIdentifier
    }

    // MARK: 取词

    /// 当前焦点元素，供读取选区与写回译文复用。
    static func currentFocusedElement() -> AXUIElement? {
        guard isTrusted else { return nil }
        return focusedElement()
    }

    /// 优先用 AX 直接读取选区，失败返回 nil。
    static func selectedText(from element: AXUIElement? = nil) -> String? {
        guard let element = element ?? currentFocusedElement() else { return nil }

        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &value
        )
        guard status == .success,
              let text = value as? String,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return text
    }

    /// 直接把译文写回选区，不经过剪贴板，也不会抢焦点。
    @discardableResult
    static func writeSelection(_ text: String, into element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        let check = AXUIElementIsAttributeSettable(
            element,
            kAXSelectedTextAttribute as CFString,
            &settable
        )
        guard check == .success, settable.boolValue else { return false }

        let result = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFString
        )
        return result == .success
    }

    /// 兜底方案：向目标进程发送 ⌘C，取剪贴板内容后还原。
    /// 会短暂阻塞，需在后台线程调用。
    static func selectedTextViaCopy(in pid: pid_t) -> String? {
        let board = NSPasteboard.general
        let snapshot = snapshot(board)
        let before = board.changeCount

        postCommandKey(UInt32(kVK_ANSI_C), to: pid)

        let deadline = Date().addingTimeInterval(0.7)
        while Date() < deadline {
            if board.changeCount != before {
                let text = board.string(forType: .string)
                restore(snapshot, ifUnchangedSince: board.changeCount, board: board)
                guard let text,
                      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else { return nil }
                return text
            }
            usleep(20_000)
        }
        return nil
    }

    // MARK: 替换

    /// 把译文粘贴回目标 App 的当前位置，随后还原用户剪贴板。
    static func replaceSelection(with text: String, in pid: pid_t) {
        let board = NSPasteboard.general
        let snapshot = snapshot(board)

        board.clearContents()
        board.setString(text, forType: .string)
        let mark = board.changeCount

        postCommandKey(UInt32(kVK_ANSI_V), to: pid)

        // 给目标 App 留出读取时间，之后仅在剪贴板未被他人改写时还原
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.8) {
            restore(snapshot, ifUnchangedSince: mark, board: board)
        }
    }

    static func copyToClipboard(_ text: String) {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(text, forType: .string)
    }

    // MARK: AX 辅助

    private static func focusedElement() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        if let element = copyFocusedElement(of: appElement) {
            return element
        }

        // 部分 App 只通过 system-wide 对象暴露焦点元素
        let systemElement = AXUIElementCreateSystemWide()
        guard let element = copyFocusedElement(of: systemElement) else { return nil }
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success,
              pid == app.processIdentifier
        else { return nil }
        return element
    }

    private static func copyFocusedElement(of element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            element,
            kAXFocusedUIElementAttribute as CFString,
            &value
        )
        guard status == .success, let value,
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    // MARK: 键盘事件

    private static func postCommandKey(_ keyCode: UInt32, to pid: pid_t) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: false)
        up?.flags = .maskCommand
        down?.postToPid(pid)
        up?.postToPid(pid)
    }

    // MARK: 剪贴板快照

    private struct BoardSnapshot {
        let items: [[String: Data]]
    }

    private static func snapshot(_ board: NSPasteboard) -> BoardSnapshot {
        let items = (board.pasteboardItems ?? []).map { item -> [String: Data] in
            var map: [String: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    map[type.rawValue] = data
                }
            }
            return map
        }
        return BoardSnapshot(items: items)
    }

    private static func restore(
        _ snapshot: BoardSnapshot,
        ifUnchangedSince expected: Int,
        board: NSPasteboard
    ) {
        guard board.changeCount == expected else { return }
        board.clearContents()
        let items = snapshot.items.map { types -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in types {
                item.setData(data, forType: NSPasteboard.PasteboardType(type))
            }
            return item
        }
        if !items.isEmpty {
            board.writeObjects(items)
        }
    }
}
