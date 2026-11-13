import AppKit
import SwiftUI

@MainActor
final class FirstLaunchAssistantController: NSObject, NSWindowDelegate {
    private enum WindowMetrics {
        static let initialContentSize = NSSize(width: 620, height: 620)
        static let minimumContentSize = NSSize(width: 540, height: 420)
    }

    private let store: any SettingsStoring
    private let makeViewModel: () -> FirstLaunchAssistantViewModel
    private var window: NSWindow?

    init<Permissions: PermissionManaging, Model: TranscriptionModelStateProviding,
         Loader: TranscriptionModelReloading, CleanupState: LocalCleanupModelStateProviding,
         CleanupManager: LocalCleanupModelManaging, Activity: DictationActivityProviding>(
        store: any SettingsStoring,
        permissions: Permissions,
        modelState: Model,
        modelLoader: Loader,
        cleanupModelState: CleanupState,
        cleanupModelManager: CleanupManager,
        activity: Activity
    ) {
        self.store = store
        makeViewModel = {
            FirstLaunchAssistantViewModel(
                store: store,
                permissions: permissions,
                modelState: modelState,
                modelLoader: modelLoader,
                cleanupModelState: cleanupModelState,
                cleanupModelManager: cleanupModelManager,
                activity: activity,
                openKeyboardSettings: Self.openKeyboardSettings
            )
        }
    }

    func presentIfNeeded() {
        guard store.bool(for: .firstLaunchAssistantCompleted) != true else { return }
        present()
    }

    func present() {
        if let window {
            show(window)
            return
        }

        let view = FirstLaunchAssistantView(viewModel: makeViewModel()) { [weak self] in
            self?.window?.close()
        }
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "Assistant de configuration DictaMac"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(WindowMetrics.initialContentSize)
        window.contentMinSize = WindowMetrics.minimumContentSize
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self
        self.window = window
        show(window)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }

    private func show(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private static func openKeyboardSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}
