import AppKit
import SwiftUI

// MARK: - 权限状态

@MainActor
final class PermissionsModel: ObservableObject {
    @Published var accessibilityGranted = SelectionService.isTrusted

    private var timer: Timer?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        let granted = SelectionService.isTrusted
        if granted != accessibilityGranted {
            accessibilityGranted = granted
        }
    }

    func requestAccessibility() {
        SelectionService.promptForTrust()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.refresh()
        }
    }

    func openSystemSettings() {
        SelectionService.openAccessibilitySettings()
    }
}
