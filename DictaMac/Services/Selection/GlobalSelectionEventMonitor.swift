import AppKit

@MainActor
final class GlobalSelectionEventMonitor: SelectionEventMonitoring {
    private static let arrowKeyCodes: Set<UInt16> = [123, 124, 125, 126]
    private static let selectAllKeyCode: UInt16 = 0

    private var continuation: AsyncStream<Void>.Continuation?
    private var monitor: Any?
    private var observedDrag = false

    private struct MonitoredEvent: Sendable {
        let type: NSEvent.EventType
        let clickCount: Int
        let keyCode: UInt16
        let modifierFlags: NSEvent.ModifierFlags

        init(event: NSEvent) {
            type = event.type
            clickCount = event.clickCount
            keyCode = event.keyCode
            modifierFlags = event.modifierFlags
        }
    }

    func events() -> AsyncStream<Void> {
        stop()
        let stream = AsyncStream<Void> { continuation in
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
            if observedDrag || event.clickCount >= 2 { continuation?.yield() }
            observedDrag = false
        case .keyUp:
            if isSelectionShortcut(event) { continuation?.yield() }
        default:
            break
        }
    }

    private func isSelectionShortcut(_ event: MonitoredEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let shiftArrow = modifiers.contains(.shift) && Self.arrowKeyCodes.contains(event.keyCode)
        let selectAll = modifiers.contains(.command) && event.keyCode == Self.selectAllKeyCode
        return shiftArrow || selectAll
    }
}
