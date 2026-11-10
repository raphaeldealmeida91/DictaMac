import Foundation

/// Connects the event tap to isolated gesture processing and main-actor callbacks.
@MainActor
final class HotkeyService: HotkeyProviding {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var onCancel: (() -> Void)?

    private let eventTapController: any HotkeyEventTapControlling
    private let eventProcessor: any HotkeyEventProcessing
    private let permissionObserver: any HotkeyPermissionObserving
    private let callbackDelivery: HotkeyCallbackDelivery
    private var isRunning = false

    convenience init(
        triggerDelay: TimeInterval = 0.300,
        emergencySettings: any EmergencyHotkeySettings,
        emergencyRuntime: EmergencyRuntime,
        emergencyRecovery: any EmergencyRecovering,
        diagnosticLog: any DiagnosticLogging
    ) {
        let controller = CGEventTapController()
        let delivery = HotkeyCallbackDelivery()
        let emergencyDetector = EmergencyHotkeyDetector(
            settings: emergencySettings,
            runtime: emergencyRuntime,
            recovery: emergencyRecovery
        )
        let processor = HotkeyEventProcessor(
            triggerDelay: triggerDelay,
            emergencyDetector: emergencyDetector,
            callbackDelivery: delivery,
            diagnosticLog: diagnosticLog
        )
        processor.setTapReactivation { [weak controller] in controller?.reenable() }
        self.init(
            eventTapController: controller,
            eventProcessor: processor,
            permissionObserver: HotkeyPermissionObserver(),
            callbackDelivery: delivery
        )
    }

    init(
        eventTapController: any HotkeyEventTapControlling,
        eventProcessor: any HotkeyEventProcessing,
        permissionObserver: any HotkeyPermissionObserving,
        callbackDelivery: HotkeyCallbackDelivery
    ) {
        self.eventTapController = eventTapController
        self.eventProcessor = eventProcessor
        self.permissionObserver = permissionObserver
        self.callbackDelivery = callbackDelivery
        eventTapController.setEventHandler { [weak eventProcessor] snapshot in
            eventProcessor?.enqueue(snapshot)
        }
        callbackDelivery.setHandlers(
            onPress: { [weak self] in self?.onPress?() },
            onRelease: { [weak self] in self?.onRelease?() },
            onCancel: { [weak self] in self?.onCancel?() }
        )
    }

    deinit {
        permissionObserver.stop()
        eventTapController.stop()
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        permissionObserver.start { [weak self] isAuthorized in
            self?.permissionDidChange(isAuthorized: isAuthorized)
        }
        eventTapController.start()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        permissionObserver.stop()
        eventProcessor.reset(publishRelease: true)
        eventTapController.stop()
    }

    nonisolated private func permissionDidChange(isAuthorized: Bool) {
        if !isAuthorized { eventProcessor.reset(publishRelease: true) }
        eventTapController.permissionDidChange(isAuthorized: isAuthorized)
    }
}
