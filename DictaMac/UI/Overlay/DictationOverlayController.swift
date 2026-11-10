import AppKit
import SwiftUI

@MainActor
final class DictationOverlayController: OverlayPresenting {
    private let model: DictationOverlayModel
    private var panel: NonActivatingOverlayPanel?
    private var dismissalTask: Task<Void, Never>?

    init(model: DictationOverlayModel = DictationOverlayModel()) {
        self.model = model
    }

    func showRecording() {
        cancelDismissal()
        model.startRecording()
        show()
    }

    func updateLevel(_ rms: Float) {
        model.updateLevel(rms)
    }

    func showTranscribing(message: String = "Transcription…") {
        cancelDismissal()
        model.showTranscribing(message)
        show()
    }

    func showMessage(_ message: String) {
        model.showMessage(message)
        showTemporarily()
    }

    func showError(_ message: String) {
        model.showError(message)
        showTemporarily()
    }

    func hide() {
        cancelDismissal()
        panel?.orderOut(nil)
    }

    private func showTemporarily() {
        cancelDismissal()
        show()
        dismissalTask = Task { [weak self] in
            try? await Task.sleep(for: Theme.Overlay.messageDisplayDuration)
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    private func cancelDismissal() {
        dismissalTask?.cancel()
        dismissalTask = nil
    }

    private func show() {
        let panel = panel ?? makePanel()
        if let screen = screenContainingCursor() {
            position(panel, on: screen)
        }
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NonActivatingOverlayPanel {
        let panel = NonActivatingOverlayPanel(
            contentRect: NSRect(
                x: .zero,
                y: .zero,
                width: Theme.Overlay.panelWidth,
                height: Theme.Overlay.panelHeight
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        configure(panel)
        panel.contentView = NSHostingView(rootView: DictationOverlayView(model: model))
        self.panel = panel
        return panel
    }

    private func configure(_ panel: NSPanel) {
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false
    }

    private func screenContainingCursor() -> NSScreen? {
        let cursor = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { NSMouseInRect(cursor, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    private func position(_ panel: NSPanel, on screen: NSScreen) {
        let visibleFrame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(
            x: visibleFrame.midX - panel.frame.width / 2,
            y: visibleFrame.minY + Theme.Overlay.bottomInset
        ))
    }
}

private final class NonActivatingOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
