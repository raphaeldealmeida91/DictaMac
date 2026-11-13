import Foundation

// Every mutable runtime field is read and written while holding lock.
final class EmergencyRuntime: @unchecked Sendable {
    struct Snapshot: Sendable {
        let stateIsIdle: Bool
        let mainThreadMonitoringActive: Bool
        let isSleeping: Bool
        let lastWakeAt: TimeInterval?
        let mainHeartbeat: TimeInterval
        let stage: EmergencyStage?
        let stageStartedAt: TimeInterval?
        let hotkeyDeadline: TimeInterval?
        let hotkeyReason: String?
    }

    private let lock = NSLock()
    private let clock: MonotonicClock
    private var stateIsIdle = true
    private var mainThreadMonitoringActive = false
    private var isSleeping = false
    private var lastWakeAt: TimeInterval?
    private var mainHeartbeat: TimeInterval
    private var stage: EmergencyStage?
    private var stageStartedAt: TimeInterval?
    private var hotkeyDeadline: TimeInterval?
    private var hotkeyReason: String?

    init(clock: MonotonicClock = .live) {
        self.clock = clock
        mainHeartbeat = clock.now()
    }

    func heartbeat(windowIsVisible: Bool = false) {
        lock.withLock {
            mainHeartbeat = clock.now()
            mainThreadMonitoringActive = !stateIsIdle || windowIsVisible
        }
    }

    func setIdle(_ idle: Bool) {
        lock.withLock {
            stateIsIdle = idle
            if idle {
                stage = nil
                stageStartedAt = nil
            }
        }
    }

    func begin(_ stage: EmergencyStage) {
        lock.withLock {
            self.stage = stage
            stageStartedAt = clock.now()
        }
    }

    func end(_ stage: EmergencyStage) {
        lock.withLock {
            guard self.stage == stage else { return }
            self.stage = nil
            stageStartedAt = nil
        }
    }

    func armHotkeyExit(reason: String, timeout: TimeInterval = 1.5) {
        lock.withLock {
            hotkeyReason = reason
            hotkeyDeadline = clock.now() + timeout
        }
    }

    func willSleep() {
        lock.withLock {
            isSleeping = true
            mainHeartbeat = clock.now()
        }
    }

    func didWake() {
        lock.withLock {
            isSleeping = false
            let now = clock.now()
            lastWakeAt = now
            mainHeartbeat = now
        }
    }

    func currentTime() -> TimeInterval { clock.now() }

    func clearHotkeyExit() {
        lock.withLock {
            hotkeyReason = nil
            hotkeyDeadline = nil
        }
    }

    func snapshot() -> Snapshot {
        lock.withLock {
            Snapshot(
                stateIsIdle: stateIsIdle,
                mainThreadMonitoringActive: mainThreadMonitoringActive,
                isSleeping: isSleeping,
                lastWakeAt: lastWakeAt,
                mainHeartbeat: mainHeartbeat,
                stage: stage,
                stageStartedAt: stageStartedAt,
                hotkeyDeadline: hotkeyDeadline,
                hotkeyReason: hotkeyReason
            )
        }
    }
}
