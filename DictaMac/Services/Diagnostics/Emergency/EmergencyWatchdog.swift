import Darwin
import Foundation

final class EmergencyWatchdog: @unchecked Sendable {
    private let lock = NSLock()
    private var thread: Thread?
    private var shouldStop = false
    private var policy: EmergencyWatchdogPolicy

    init(configuration: EmergencyWatchdogPolicy.Configuration = .init(
        physicalMemory: ProcessInfo.processInfo.physicalMemory
    )) {
        policy = EmergencyWatchdogPolicy(configuration: configuration)
    }

    func start() {
        let newThread: Thread? = lock.withLock {
            guard thread == nil else { return nil }
            shouldStop = false
            let thread = Thread { [weak self] in self?.run() }
            thread.name = "com.raphaeldealmeida.DictaMac.emergency-watchdog"
            thread.qualityOfService = .userInitiated
            self.thread = thread
            return thread
        }
        newThread?.start()
    }

    func stop() {
        lock.withLock { shouldStop = true }
    }

    private func run() {
        while !lock.withLock({ shouldStop }) {
            usleep(500_000)
            tick()
        }
        lock.withLock { thread = nil }
    }

    private func tick() {
        let now = MonotonicClock.now
        let runtime = EmergencyRuntime.shared.snapshot()
        if let deadline = runtime.hotkeyDeadline, now >= deadline {
            if runtime.stateIsIdle {
                EmergencyRuntime.shared.clearHotkeyExit()
            } else {
                EmergencyRecovery.exit(reason: runtime.hotkeyReason ?? "hotkey")
            }
        }
        evaluatePolicy(now: now, runtime: runtime)
    }

    private func evaluatePolicy(now: TimeInterval, runtime: EmergencyRuntime.Snapshot) {
        let snapshot = EmergencyWatchdogPolicy.Snapshot(
            now: now,
            mainHeartbeat: runtime.mainHeartbeat,
            stage: runtime.stage,
            stageStartedAt: runtime.stageStartedAt,
            physicalFootprint: ProcessMemoryDiagnostics.physicalFootprint
        )
        switch policy.evaluate(snapshot) {
        case .none: break
        case .recover(let reason): EmergencyRecovery.begin(reason: reason)
        case .exit(let reason): EmergencyRecovery.exit(reason: reason)
        }
    }
}
