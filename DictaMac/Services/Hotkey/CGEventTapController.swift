@preconcurrency import ApplicationServices
import Foundation

// Tap ownership stays on its run-loop thread; lifecycle fields are protected by lifecycleLock.
final class CGEventTapController: HotkeyEventTapControlling, @unchecked Sendable {
    private let lifecycleLock = NSLock()
    private var eventHandler: (@Sendable (HotkeyEventSnapshot) -> Void)?
    private var thread: Thread?
    private var runLoop: CFRunLoop?
    private var shouldStop = false
    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?

    func setEventHandler(_ handler: @escaping @Sendable (HotkeyEventSnapshot) -> Void) {
        lifecycleLock.withLock { eventHandler = handler }
    }

    func start() {
        let newThread: Thread? = lifecycleLock.withLock {
            guard thread == nil else { return nil }
            shouldStop = false
            let thread = Thread { [weak self] in self?.run() }
            thread.name = "com.raphaeldealmeida.DictaMac.fn-event-tap"
            thread.qualityOfService = .userInteractive
            self.thread = thread
            return thread
        }
        newThread?.start()
    }

    func stop() {
        let loop = lifecycleLock.withLock {
            shouldStop = true
            return runLoop
        }
        perform(on: loop) { [weak self] in
            self?.uninstallEventTap()
            if let loop { CFRunLoopStop(loop) }
        }
    }

    func permissionDidChange(isAuthorized: Bool) {
        let loop = lifecycleLock.withLock { runLoop }
        perform(on: loop) { [weak self] in
            guard let self, let loop else { return }
            if isAuthorized { installEventTapIfNeeded(on: loop) } else { uninstallEventTap() }
        }
    }

    func reenable() {
        let loop = lifecycleLock.withLock { runLoop }
        perform(on: loop) { [weak self] in
            guard let tap = self?.eventTap else { return }
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    fileprivate func receive(type: CGEventType, event: CGEvent) {
        let snapshot = HotkeyEventSnapshot(type: type, event: event)
        let handler = lifecycleLock.withLock { eventHandler }
        handler?(snapshot)
    }

    private func run() {
        autoreleasepool {
            guard let currentRunLoop = CFRunLoopGetCurrent() else { return finishRun() }
            let stopWasRequested = lifecycleLock.withLock {
                runLoop = currentRunLoop
                return shouldStop
            }
            guard !stopWasRequested else { return finishRun() }
            installEventTapIfNeeded(on: currentRunLoop)
            CFRunLoopRun()
            uninstallEventTap()
            finishRun()
        }
    }

    private func finishRun() {
        lifecycleLock.withLock {
            runLoop = nil
            thread = nil
        }
    }

    private func installEventTapIfNeeded(on runLoop: CFRunLoop) {
        guard eventTap == nil else { return }
        let eventMask = mask(for: .flagsChanged)
            | mask(for: .keyDown)
            | mask(for: hotkeySystemDefinedEventType)
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: hotkeyEventTapCallback,
            userInfo: context
        ) else { return }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        eventTap = tap
        eventTapSource = source
        CFRunLoopAddSource(runLoop, source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func uninstallEventTap() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        if let eventTapSource { CFRunLoopSourceInvalidate(eventTapSource) }
        eventTapSource = nil
        eventTap = nil
    }

    private func perform(on loop: CFRunLoop?, action: @escaping @Sendable () -> Void) {
        guard let loop else { return }
        CFRunLoopPerformBlock(loop, CFRunLoopMode.commonModes.rawValue, action)
        CFRunLoopWakeUp(loop)
    }

    private func mask(for type: CGEventType) -> CGEventMask {
        CGEventMask(1) << type.rawValue
    }
}

private let hotkeyEventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let controller = Unmanaged<CGEventTapController>.fromOpaque(userInfo).takeUnretainedValue()
    controller.receive(type: type, event: event)
    return Unmanaged.passUnretained(event)
}
