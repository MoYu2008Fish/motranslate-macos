import AppKit
import Carbon.HIToolbox

// MARK: - 全局热键

/// 基于 Carbon RegisterEventHotKey 的全局热键，无需额外系统权限。
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private struct Entry {
        let ref: EventHotKeyRef
        let action: () -> Void
    }

    private var entries: [UInt32: Entry] = [:]
    private var nextID: UInt32 = 1
    private var handlerInstalled = false

    private static let signature: OSType = 0x4D4F5954 // 'MOYT'

    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) -> UInt32? {
        installHandlerIfNeeded()

        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status != noErr || ref == nil {
            NSLog("MoTranslate: 热键注册失败 keyCode=\(keyCode) modifiers=\(modifiers) status=\(status)")
        }
        guard status == noErr, let ref else { return nil }
        entries[id] = Entry(ref: ref, action: action)
        return id
    }

    func unregister(_ id: UInt32) {
        guard let entry = entries.removeValue(forKey: id) else { return }
        UnregisterEventHotKey(entry.ref)
    }

    func unregisterAll() {
        for id in entries.keys { unregister(id) }
    }

    fileprivate func fire(_ id: UInt32) {
        entries[id]?.action()
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr else { return OSStatus(eventNotHandledErr) }
                DispatchQueue.main.async {
                    HotKeyCenter.shared.fire(hotKeyID.id)
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            nil
        )
    }
}
