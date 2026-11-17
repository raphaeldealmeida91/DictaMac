import AppKit

@MainActor
final class GlobalSelectionEventMonitor: SelectionEventMonitoring {
    private static let selectionNavigationKeyCodes: Set<UInt16> = [
        115, 116, 119, 121, 123, 124, 125, 126
    ]
    private static let selectAllKeyCode: UInt16 = 0

    private var continuation: AsyncStream<SelectionMonitorEvent>.Continuation?
    private var monitor: Any?
    private var observedDrag = false

    struct MonitoredEvent: Sendable {
        let type: NSEvent.EventType
        let clickCount: Int
        let keyCode: UInt16
        let modifierFlags: NSEvent.ModifierFlags

        init(event: NSEvent) {
            type = event.type
            clickCount = event.type == .leftMouseUp ? event.clickCount : 0
            keyCode = event.type == .keyUp ? event.keyCode : 0
            modifierFlags = event.modifierFlags
        }
    }

    func events() -> AsyncStream<SelectionMonitorEvent> {
        stop()
        let stream = AsyncStream<SelectionMonitorEvent> { continuation in
            self.continuation = continuation
        }
        installMonitor()
        return stream
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        continuation?.finish()
        continuation = nil
        observedDrag = false
    }

    private func installMonitor() {
        let mask: NSEvent.EventTypeMask = [.leftMouseDragged, .leftMouseUp, .keyUp]
        monitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            let eventData = MonitoredEvent(event: event)
            Task { @MainActor [weak self] in
                self?.handle(eventData)
            }
        }
    }

    private func handle(_ event: MonitoredEvent) {
        switch event.type {
        case .leftMouseDragged:
            observedDrag = true
        case .leftMouseUp:
            if observedDrag || event.clickCount >= 2 { continuation?.yield(.selectionChanged) }
            observedDrag = false
        case .keyUp:
            continuation?.yield(isSelectionShortcut(event) ? .selectionChanged : .textChanged)
        default:
            break
        }
    }

    private func isSelectionShortcut(_ event: MonitoredEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let shiftNavigation = modifiers.contains(.shift)
            && Self.selectionNavigationKeyCodes.contains(event.keyCode)
        let selectAll = modifiers.contains(.command) && event.keyCode == Self.selectAllKeyCode
        return shiftNavigation || selectAll
    }
}
