import Foundation
import OSLog

final class HotkeyEventProcessor: HotkeyEventProcessing, @unchecked Sendable {
    private static let escapeKeyCode: Int64 = 53
    private let triggerDelay: TimeInterval
    private let emergencyDetector: EmergencyHotkeyDetector
    private let callbackDelivery: HotkeyCallbackDelivery
    private let diagnosticLog: any DiagnosticLogging
    private let queue = DispatchQueue(
        label: "com.raphaeldealmeida.DictaMac.fn-event-processing",
        qos: .userInteractive
    )
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "DictaMac",
        category: "HotkeyProcessor"
    )
    private var gesture = FnGestureStateMachine()
    private var triggerWorkItem: DispatchWorkItem?
    private var reenableTap: (@Sendable () -> Void)?

    init(
        triggerDelay: TimeInterval,
        emergencyDetector: EmergencyHotkeyDetector,
        callbackDelivery: HotkeyCallbackDelivery,
        diagnosticLog: any DiagnosticLogging
    ) {
        precondition(triggerDelay >= 0, "triggerDelay must not be negative")
        self.triggerDelay = triggerDelay
        self.emergencyDetector = emergencyDetector
        self.callbackDelivery = callbackDelivery
        self.diagnosticLog = diagnosticLog
    }

    func setTapReactivation(_ action: @escaping @Sendable () -> Void) {
        queue.async { [weak self] in self?.reenableTap = action }
    }

    func enqueue(_ snapshot: HotkeyEventSnapshot) {
        queue.async { [weak self] in self?.handle(snapshot) }
    }

    func reset(publishRelease: Bool) {
        queue.async { [weak self] in self?.resetGesture(publishRelease: publishRelease) }
    }

    private func handle(_ snapshot: HotkeyEventSnapshot) {
        emergencyDetector.process(snapshot)
        switch snapshot.kind {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            handleTapDisabled(snapshot.kind)
        case .flagsChanged:
            handleFnTransition(isDown: snapshot.fnIsDown)
        case .keyDown, .systemDefined:
            handleKeyDown(snapshot)
        case .other:
            break
        }
    }

    private func handleTapDisabled(_ kind: HotkeyEventKind) {
        reenableTap?()
        let reason = kind == .tapDisabledByTimeout ? "timeout" : "user-input"
        logger.error("event tap re-enabled after disable reason=\(reason, privacy: .public)")
        diagnosticLog.eventTapDisabled(reason: reason)
    }

    private func handleKeyDown(_ snapshot: HotkeyEventSnapshot) {
        if gesture.isDown, !gesture.pressWasPublished { cancelTriggerTimer() }
        if snapshot.kind == .keyDown, snapshot.keyCode == Self.escapeKeyCode {
            callbackDelivery.deliver(.cancel)
        }
    }

    private func handleFnTransition(isDown: Bool) {
        switch gesture.transition(isDown: isDown) {
        case .none:
            break
        case .began:
            schedulePress()
        case let .ended(published):
            cancelTriggerTimer()
            if published { callbackDelivery.deliver(.release) }
        }
    }

    private func schedulePress() {
        cancelTriggerTimer()
        guard triggerDelay > 0 else {
            publishPressIfStillValid()
            return
        }
        let workItem = DispatchWorkItem { [weak self] in
            self?.publishPressIfStillValid()
        }
        triggerWorkItem = workItem
        queue.asyncAfter(deadline: .now() + triggerDelay, execute: workItem)
    }

    private func publishPressIfStillValid() {
        cancelTriggerTimer()
        if gesture.publishIfValid() { callbackDelivery.deliver(.press) }
    }

    private func cancelTriggerTimer() {
        triggerWorkItem?.cancel()
        triggerWorkItem = nil
    }

    private func resetGesture(publishRelease: Bool) {
        cancelTriggerTimer()
        let wasPublished = gesture.reset()
        emergencyDetector.reset()
        if publishRelease, wasPublished { callbackDelivery.deliver(.release) }
    }
}
