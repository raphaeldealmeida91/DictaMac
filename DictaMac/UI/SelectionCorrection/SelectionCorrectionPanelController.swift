import AppKit
import SwiftUI

@MainActor
final class SelectionCorrectionPanelController: SelectionCorrectionPresenting {
    private let viewModel: SelectionCorrectionViewModel
    private var panel: SelectionCorrectionPanel?
    private var globalMonitor: Any?
    private var localMonitor: Any?

    init(viewModel: SelectionCorrectionViewModel) {
        self.viewModel = viewModel
    }

    func present(
        _ correction: SelectionCorrection,
        for snapshot: SelectionSnapshot,
        onDismiss: @escaping @MainActor () -> Void
    ) {
        let panel = panel ?? makePanel()
        viewModel.present(correction, snapshot: snapshot) { [weak self] in
            self?.hidePanel()
            onDismiss()
        }
        size(panel)
        position(panel, near: snapshot.screenRect)
        installEventMonitors()
        panel.orderFrontRegardless()
    }

    func dismiss() {
        if viewModel.state == .hidden {
            hidePanel()
        } else {
            viewModel.dismiss()
        }
    }

    private func makePanel() -> SelectionCorrectionPanel {
        let panel = SelectionCorrectionPanel(
            contentRect: NSRect(
                origin: .zero,
                size: NSSize(
                    width: Theme.SelectionCorrection.panelWidth,
                    height: Theme.SelectionCorrection.defaultPanelHeight
                )
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        configure(panel)
        panel.contentView = NSHostingView(rootView: SelectionCorrectionView(viewModel: viewModel))
        self.panel = panel
        return panel
    }

    private func configure(_ panel: NSPanel) {
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false
    }

    private func size(_ panel: NSPanel) {
        guard let hostingView = panel.contentView else { return }
        let fittingHeight = hostingView.fittingSize.height
        let height = min(fittingHeight, Theme.SelectionCorrection.panelMaximumHeight)
        panel.setContentSize(NSSize(width: Theme.SelectionCorrection.panelWidth, height: height))
    }

    private func position(_ panel: NSPanel, near selectionRect: CGRect?) {
        let anchor = selectionRect.map(appKitRect(from:))
        let screen = screen(containing: anchor?.center ?? NSEvent.mouseLocation)
        guard let screen else { return }
        panel.setFrameOrigin(origin(for: panel.frame.size, anchor: anchor, screen: screen))
    }

    private func origin(for size: CGSize, anchor: CGRect?, screen: NSScreen) -> CGPoint {
        let visible = screen.visibleFrame
        let reference = anchor ?? CGRect(origin: NSEvent.mouseLocation, size: .zero)
        let x = clamped(reference.midX - size.width / 2, min: visible.minX, max: visible.maxX - size.width)
        let below = reference.minY - size.height - Theme.SelectionCorrection.anchorSpacing
        let above = reference.maxY + Theme.SelectionCorrection.anchorSpacing
        let y = below >= visible.minY ? below : min(above, visible.maxY - size.height)
        return CGPoint(x: x, y: max(visible.minY, y))
    }

    private func appKitRect(from accessibilityRect: CGRect) -> CGRect {
        guard let screen = screenForAccessibilityRect(accessibilityRect) else { return accessibilityRect }
        let displayFrame = displayBounds(for: screen)
        let localY = accessibilityRect.minY - displayFrame.minY
        return CGRect(
            x: screen.frame.minX + accessibilityRect.minX - displayFrame.minX,
            y: screen.frame.maxY - localY - accessibilityRect.height,
            width: accessibilityRect.width,
            height: accessibilityRect.height
        )
    }

    private func screenForAccessibilityRect(_ rect: CGRect) -> NSScreen? {
        NSScreen.screens.first { displayBounds(for: $0).contains(rect.center) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    private func displayBounds(for screen: NSScreen) -> CGRect {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return screen.frame
        }
        return CGDisplayBounds(CGDirectDisplayID(number.uint32Value))
    }

    private func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.first(where: { $0.frame.contains(point) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    private func installEventMonitors() {
        removeEventMonitors()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .keyDown]
        ) { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .keyDown]
        ) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
            return event
        }
    }

    private func handle(_ event: NSEvent) {
        if event.type == .keyDown {
            handleKey(event)
            return
        }
        guard let panel, !panel.frame.contains(NSEvent.mouseLocation) else { return }
        dismiss()
    }

    private func handleKey(_ event: NSEvent) {
        if event.keyCode == Theme.SelectionCorrection.escapeKeyCode {
            dismiss()
        } else if event.keyCode == Theme.SelectionCorrection.returnKeyCode {
            viewModel.replace()
        } else if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "c" {
            viewModel.copy()
        }
    }

    private func hidePanel() {
        panel?.orderOut(nil)
        removeEventMonitors()
    }

    private func removeEventMonitors() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }

    private func clamped(_ value: CGFloat, min minimum: CGFloat, max maximum: CGFloat) -> CGFloat {
        Swift.max(minimum, Swift.min(value, maximum))
    }
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}
