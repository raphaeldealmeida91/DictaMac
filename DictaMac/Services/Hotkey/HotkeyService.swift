@preconcurrency import ApplicationServices
import Foundation
import OSLog

/// Publishes a single press/release pair when the Globe/Fn key is held on its own.
///
/// The CGEvent callback only snapshots primitive event data and enqueues it. Gesture
/// recognition lives on a separate serial queue, and consumer callbacks are
/// delivered on the main actor.
@MainActor
final class HotkeyService: HotkeyProviding {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var onCancel: (() -> Void)?

    private let worker: EventTapWorker
    private var permissionObserver: NSObjectProtocol?

    /// - Parameter triggerDelay: How long Fn must be held alone before `onPress`.
    ///   The default (300 ms) filters accidental Fn presses and recognises Fn+key combinations.
    init(
        triggerDelay: TimeInterval = 0.300,
        emergencySettings: any EmergencyHotkeySettings,
        emergencyRuntime: EmergencyRuntime,
        emergencyRecovery: any EmergencyRecovering,
        diagnosticLog: PersistentDiagnosticLog
    ) {
        precondition(triggerDelay >= 0, "triggerDelay must not be negative")

        worker = EventTapWorker(
            triggerDelay: triggerDelay,
            emergencySettings: emergencySettings,
            emergencyRuntime: emergencyRuntime,
            emergencyRecovery: emergencyRecovery,
            diagnosticLog: diagnosticLog
        )
        worker.onPress = { [weak self] in
            Task { @MainActor [weak self] in
                self?.onPress?()
            }
        }
        worker.onRelease = { [weak self] in
            Task { @MainActor [weak self] in
                self?.onRelease?()
            }
        }
        worker.onCancel = { [weak self] in
            Task { @MainActor [weak self] in
                self?.onCancel?()
            }
        }
        permissionObserver = NotificationCenter.default.addObserver(
            forName: .inputMonitoringPermissionDidChange,
            object: nil,
            queue: .main
        ) { [weak worker] notification in
            let authorized = notification.userInfo?["authorized"] as? Bool ?? false
            worker?.permissionDidChange(isAuthorized: authorized)
        }
    }

    deinit {
        if let permissionObserver {
            NotificationCenter.default.removeObserver(permissionObserver)
        }
        worker.stop()
    }

    func start() {
        worker.start()
    }

    func stop() {
        worker.stop()
    }
}

// All mutable event-tap state is confined to workerQueue; cross-thread flags use LockedAtomic.
private final class EventTapWorker: @unchecked Sendable {
    private struct EventSnapshot: Sendable {
        let type: CGEventType
        let flags: CGEventFlags
        let keyCode: Int64
    }

    private let triggerDelay: TimeInterval
    private let emergencySettings: any EmergencyHotkeySettings
    private let emergencyRuntime: EmergencyRuntime
    private let emergencyRecovery: any EmergencyRecovering
    private let diagnosticLog: PersistentDiagnosticLog
    private let lifecycleLock = NSLock()
    private let eventQueue = DispatchQueue(
        label: "com.raphaeldealmeida.DictaMac.fn-event-processing",
        qos: .userInteractive
    )
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "DictaMac",
        category: "EventTap"
    )

    private var thread: Thread?
    private var runLoop: CFRunLoop?
    private var shouldStop = false

    // Tap objects are owned by the event-tap run loop. Gesture state below is
    // confined to eventQueue and never touched by the CGEvent callback itself.
    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?
    private var triggerWorkItem: DispatchWorkItem?
    private var fnIsDown = false
    private var pressWasPublished = false
    // Accessed only by the event-tap thread, directly from its callback.
    private var emergencyChordIsDown = false

    var onPress: (@Sendable () -> Void)?
    var onRelease: (@Sendable () -> Void)?
    var onCancel: (@Sendable () -> Void)?

    init(
        triggerDelay: TimeInterval,
        emergencySettings: any EmergencyHotkeySettings,
        emergencyRuntime: EmergencyRuntime,
        emergencyRecovery: any EmergencyRecovering,
        diagnosticLog: PersistentDiagnosticLog
    ) {
        self.triggerDelay = triggerDelay
        self.emergencySettings = emergencySettings
        self.emergencyRuntime = emergencyRuntime
        self.emergencyRecovery = emergencyRecovery
        self.diagnosticLog = diagnosticLog
    }

    func start() {
        lifecycleLock.lock()
        guard thread == nil else {
            lifecycleLock.unlock()
            return
        }

        shouldStop = false
        let thread = Thread { [weak self] in
            self?.run()
        }
        thread.name = "com.raphaeldealmeida.DictaMac.fn-event-tap"
        thread.qualityOfService = .userInteractive
        self.thread = thread
        lifecycleLock.unlock()

        thread.start()
    }

    func stop() {
        lifecycleLock.lock()
        shouldStop = true
        let loop = runLoop
        lifecycleLock.unlock()

        guard let loop else { return }
        CFRunLoopPerformBlock(loop, CFRunLoopMode.commonModes.rawValue) {
            CFRunLoopStop(loop)
        }
        CFRunLoopWakeUp(loop)
    }

    private func run() {
        autoreleasepool {
            guard let currentRunLoop = CFRunLoopGetCurrent() else {
                finishRun()
                return
            }

            lifecycleLock.lock()
            runLoop = currentRunLoop
            let stopWasRequested = shouldStop
            lifecycleLock.unlock()

            guard !stopWasRequested else {
                finishRun()
                return
            }

            installEventTap(on: currentRunLoop)
            CFRunLoopRun()

            tearDownEventTap(publishRelease: true)
            finishRun()
        }
    }

    private func finishRun() {
        lifecycleLock.lock()
        runLoop = nil
        thread = nil
        lifecycleLock.unlock()
    }

    func permissionDidChange(isAuthorized: Bool) {
        lifecycleLock.lock()
        let loop = runLoop
        lifecycleLock.unlock()
        guard let loop else { return }
        CFRunLoopPerformBlock(loop, CFRunLoopMode.commonModes.rawValue) { [weak self] in
            guard let self else { return }
            if isAuthorized {
                if self.eventTap == nil { self.installEventTap(on: loop) }
            } else {
                self.tearDownEventTap(publishRelease: true)
            }
        }
        CFRunLoopWakeUp(loop)
    }

    private func installEventTap(on runLoop: CFRunLoop) {
        // keyDown is observed only to cancel a pending solo-Fn gesture. Modifier
        // transitions themselves continue to arrive exclusively as flagsChanged.
        let eventMask = mask(for: .flagsChanged)
            | mask(for: .keyDown)
            | mask(for: systemDefinedEventType)
        let context = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            // DictaMac never suppresses an input event. A listen-only tap cannot
            // stall the system input stream and is correct when macOS' “Press 🌐
            // key to” setting is “Do Nothing”. An active tap would only be justified
            // if the product intentionally swallowed Fn, which it does not.
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: eventTapCallback,
            userInfo: context
        ) else {
            return
        }

        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        eventTap = tap
        eventTapSource = source
        CFRunLoopAddSource(runLoop, source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func tearDownEventTap(publishRelease: Bool) {
        eventQueue.async { [weak self] in
            self?.resetGesture(publishRelease: publishRelease)
        }

        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        if let eventTapSource {
            CFRunLoopSourceInvalidate(eventTapSource)
        }
        eventTapSource = nil
        eventTap = nil
    }

    /// Called from the CGEvent callback. This is deliberately constant-time:
    /// primitive reads, one non-blocking enqueue, then return.
    fileprivate func enqueue(type: CGEventType, event: CGEvent) {
        let snapshot = EventSnapshot(
            type: type,
            flags: event.flags,
            keyCode: type == .keyDown ? event.getIntegerValueField(.keyboardEventKeycode) : -1
        )
        eventQueue.async { [weak self] in
            self?.handle(snapshot)
        }
    }

    /// Runs on the event-tap thread. It deliberately does not enqueue on the
    /// main actor and does not create or await a Swift concurrency task.
    fileprivate func handleEmergencyIfNeeded(type: CGEventType, event: CGEvent) {
        guard type == .flagsChanged || type == .keyDown else { return }
        let required = emergencySettings.configuredModifiers
        let chordIsDown = !required.isEmpty && event.flags.intersection(required) == required
        if chordIsDown, !emergencyChordIsDown {
            emergencyChordIsDown = true
            emergencyRuntime.setIdle(false)
            emergencyRecovery.begin(reason: "global_hotkey", hotkey: true)
        } else if !chordIsDown {
            emergencyChordIsDown = false
        }
    }

    private func handle(_ event: EventSnapshot) {
        switch event.type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            let reason = event.type == .tapDisabledByTimeout ? "timeout" : "user-input"
            logger.error("event tap re-enabled after disable reason=\(reason, privacy: .public)")
            diagnosticLog.eventTapDisabled(reason: reason)

        case .flagsChanged:
            handleFnTransition(isDown: event.flags.contains(.maskSecondaryFn))

        case .keyDown, systemDefinedEventType:
            // Modifier keys generate flagsChanged, so every keyDown here is a
            // non-modifier and invalidates a still-pending solo-Fn gesture.
            // systemDefined covers Fn+function-key media events on some keyboards.
            if fnIsDown, !pressWasPublished {
                cancelTriggerTimer()
            }
            if event.type == .keyDown, event.keyCode == 53 {
                onCancel?()
            }

        default:
            break
        }
    }

    private func handleFnTransition(isDown: Bool) {
        // flagsChanged can be emitted again when another modifier changes. Only
        // react to an actual transition of maskSecondaryFn.
        guard isDown != fnIsDown else { return }
        fnIsDown = isDown

        if isDown {
            schedulePress()
        } else {
            cancelTriggerTimer()
            if pressWasPublished {
                pressWasPublished = false
                onRelease?()
            }
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
        eventQueue.asyncAfter(deadline: .now() + triggerDelay, execute: workItem)
    }

    private func publishPressIfStillValid() {
        cancelTriggerTimer()
        guard fnIsDown, !pressWasPublished else { return }
        pressWasPublished = true
        onPress?()
    }

    private func cancelTriggerTimer() {
        triggerWorkItem?.cancel()
        triggerWorkItem = nil
    }

    private func resetGesture(publishRelease: Bool) {
        cancelTriggerTimer()
        if publishRelease, pressWasPublished {
            pressWasPublished = false
            onRelease?()
        }
        fnIsDown = false
    }

    private func mask(for type: CGEventType) -> CGEventMask {
        CGEventMask(1) << type.rawValue
    }
}

// AppKit exposes this as NSEvent.EventType.systemDefined (raw value 14), while
// Core Graphics accepts the value in an event mask without naming it in Swift.
private let systemDefinedEventType = CGEventType(rawValue: 14) ?? .null

private let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }

    let worker = Unmanaged<EventTapWorker>.fromOpaque(userInfo).takeUnretainedValue()
    worker.handleEmergencyIfNeeded(type: type, event: event)
    worker.enqueue(type: type, event: event)
    return Unmanaged.passUnretained(event)
}
