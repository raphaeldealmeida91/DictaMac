import Foundation

final class EmergencyRuntime: @unchecked Sendable {
    static let shared = EmergencyRuntime()

    struct Snapshot: Sendable {
        let stateIsIdle: Bool
        let mainHeartbeat: TimeInterval
        let stage: EmergencyStage?
        let stageStartedAt: TimeInterval?
        let hotkeyDeadline: TimeInterval?
        let hotkeyReason: String?
    }

    private let lock = NSLock()
    private var stateIsIdle = true
    private var mainHeartbeat = MonotonicClock.now
    private var stage: EmergencyStage?
    private var stageStartedAt: TimeInterval?
    private var hotkeyDeadline: TimeInterval?
    private var hotkeyReason: String?

    private init() {}

    func heartbeat() {
        lock.withLock { mainHeartbeat = MonotonicClock.now }
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
            stageStartedAt = MonotonicClock.now
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
            hotkeyDeadline = MonotonicClock.now + timeout
        }
    }

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
                mainHeartbeat: mainHeartbeat,
                stage: stage,
                stageStartedAt: stageStartedAt,
                hotkeyDeadline: hotkeyDeadline,
                hotkeyReason: hotkeyReason
            )
        }
    }
}
