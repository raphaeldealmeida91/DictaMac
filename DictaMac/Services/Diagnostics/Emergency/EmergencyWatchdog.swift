import Darwin
import Foundation

// Thread lifecycle, stop state, and policy are all protected by lock.
final class EmergencyWatchdog: @unchecked Sendable {
    private let lock = NSLock()
    private var thread: Thread?
    private var shouldStop = false
    private var policy: EmergencyWatchdogPolicy
    private let runtime: EmergencyRuntime
    private let recovery: any EmergencyRecovering

    init(
        runtime: EmergencyRuntime,
        recovery: any EmergencyRecovering,
        configuration: EmergencyWatchdogPolicy.Configuration = .init(
            physicalMemory: ProcessInfo.processInfo.physicalMemory
        )
    ) {
        self.runtime = runtime
        self.recovery = recovery
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
        let runtime = runtime.snapshot()
        if let deadline = runtime.hotkeyDeadline, now >= deadline {
            if runtime.stateIsIdle {
                self.runtime.clearHotkeyExit()
            } else {
                recovery.exit(reason: runtime.hotkeyReason ?? "hotkey")
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
        case .recover(let reason): recovery.begin(reason: reason, hotkey: false)
        case .exit(let reason): recovery.exit(reason: reason)
        }
    }
}
