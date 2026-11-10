import AppKit
import Darwin
import Foundation
import OSLog

extension Notification.Name {
    static let emergencyStopRequested = Notification.Name("DictaMac.emergencyStopRequested")
}

enum EmergencyStage: String, Sendable {
    case finalTranscription = "final_transcription"
    case cleanup
    case injection
}

struct EmergencyWatchdogPolicy: Sendable {
    struct Configuration: Sendable {
        var mainThreadTimeout: TimeInterval = 5
        var finalTranscriptionBudget: TimeInterval = 8
        var cleanupBudget: TimeInterval = 10
        var injectionBudget: TimeInterval = 2
        var recoveryGracePeriod: TimeInterval = 3
        var absoluteMemoryLimit: UInt64 = 6 * 1_024 * 1_024 * 1_024
        var physicalMemory: UInt64

        var memoryLimit: UInt64 {
            min(absoluteMemoryLimit, physicalMemory / 2)
        }

        func budget(for stage: EmergencyStage) -> TimeInterval {
            switch stage {
            case .finalTranscription: finalTranscriptionBudget
            case .cleanup: cleanupBudget
            case .injection: injectionBudget
            }
        }
    }

    struct Snapshot: Sendable {
        var now: TimeInterval
        var mainHeartbeat: TimeInterval
        var stage: EmergencyStage?
        var stageStartedAt: TimeInterval?
        var physicalFootprint: UInt64?
    }

    enum Decision: Equatable, Sendable {
        case none
        case recover(reason: String)
        case exit(reason: String)
    }

    let configuration: Configuration
    private(set) var recoveryStartedAt: TimeInterval?
    private(set) var recoveryReason: String?

    mutating func evaluate(_ snapshot: Snapshot) -> Decision {
        guard let reason = breachReason(snapshot) else {
            recoveryStartedAt = nil
            recoveryReason = nil
            return .none
        }

        if recoveryStartedAt == nil || recoveryReason != reason {
            recoveryStartedAt = snapshot.now
            recoveryReason = reason
            return .recover(reason: reason)
        }

        guard let recoveryStartedAt,
              snapshot.now - recoveryStartedAt >= configuration.recoveryGracePeriod else {
            return .none
        }
        return .exit(reason: reason)
    }

    private func breachReason(_ snapshot: Snapshot) -> String? {
        let mainDelay = snapshot.now - snapshot.mainHeartbeat
        if mainDelay > configuration.mainThreadTimeout {
            return "main_thread_stall"
        }
        if let stage = snapshot.stage,
           let startedAt = snapshot.stageStartedAt,
           snapshot.now - startedAt > configuration.budget(for: stage) {
            return "stage_timeout_\(stage.rawValue)"
        }
        if let footprint = snapshot.physicalFootprint,
           footprint > configuration.memoryLimit {
            return "memory_limit"
        }
        return nil
    }
}

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

final class EmergencyCancellationHub: @unchecked Sendable {
    static let shared = EmergencyCancellationHub()

    private let lock = NSLock()
    private var handlers: [@Sendable () -> Void] = []

    private init() {}

    func replaceHandlers(_ handlers: [@Sendable () -> Void]) {
        lock.withLock { self.handlers = handlers }
    }

    func cancelAll() {
        let handlers = lock.withLock { self.handlers }
        handlers.forEach { $0() }
    }
}

final class EmergencyAudioRegistry: @unchecked Sendable {
    static let shared = EmergencyAudioRegistry()

    private let lock = NSLock()
    private var stopHandler: (@Sendable (TimeInterval) -> Bool)?

    private init() {}

    func install(_ handler: @escaping @Sendable (TimeInterval) -> Bool) {
        lock.withLock { stopHandler = handler }
    }

    func stop(timeout: TimeInterval) -> Bool {
        let handler = lock.withLock { stopHandler }
        return handler?(timeout) ?? true
    }
}

enum EmergencyRecovery {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "DictaMac",
        category: "Emergency"
    )

    static func begin(reason: String, hotkey: Bool = false) {
        logger.fault("emergency recovery reason=\(reason, privacy: .public)")
        PersistentDiagnosticLog.shared.emergencyRecovery(reason: reason)
        if hotkey {
            // Arm before touching AVFAudio: stop/removeTap may themselves hang.
            EmergencyRuntime.shared.armHotkeyExit(reason: reason)
        }
        EmergencyCancellationHub.shared.cancelAll()
        let audioStopped = EmergencyAudioRegistry.shared.stop(timeout: 2)
        WhisperKitTranscriptionService.shared.requestEmergencyUnload()
        LocalCleanupModelManager.shared.requestEmergencyUnload()
        if audioStopped {
            EmergencyRuntime.shared.setIdle(true)
        }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .emergencyStopRequested, object: nil)
            EmergencyAlertPresenter.show(reason: reason)
        }
    }

    static func exit(reason: String) -> Never {
        PersistentDiagnosticLog.shared.emergencyExitAndFlush(reason: reason)
        _exit(0)
    }
}

@MainActor
private enum EmergencyAlertPresenter {
    private static var isShowing = false

    static func show(reason: String) {
        guard !isShowing else { return }
        isShowing = true
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Arrêt d’urgence DictaMac"
        alert.informativeText = "La dictée a été annulée et les modèles ont été déchargés (\(reason))."
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Ouvrir le journal")
        let response = alert.runModal()
        isShowing = false
        if response == .alertSecondButtonReturn,
           let directory = try? PersistentDiagnosticLog.logsDirectoryURL() {
            NSWorkspace.shared.open(directory)
        }
    }
}

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

        let snapshot = EmergencyWatchdogPolicy.Snapshot(
            now: now,
            mainHeartbeat: runtime.mainHeartbeat,
            stage: runtime.stage,
            stageStartedAt: runtime.stageStartedAt,
            physicalFootprint: ProcessMemoryDiagnostics.physicalFootprint
        )
        switch policy.evaluate(snapshot) {
        case .none:
            break
        case .recover(let reason):
            EmergencyRecovery.begin(reason: reason)
        case .exit(let reason):
            EmergencyRecovery.exit(reason: reason)
        }
    }
}

enum MonotonicClock {
    static var now: TimeInterval {
        var value = timespec()
        clock_gettime(CLOCK_MONOTONIC_RAW, &value)
        return TimeInterval(value.tv_sec) + TimeInterval(value.tv_nsec) / 1_000_000_000
    }
}

struct SafeModeManager: Sendable {
    let markerURL: URL

    static func live() throws -> SafeModeManager {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = support.appendingPathComponent("DictaMac", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return SafeModeManager(markerURL: directory.appendingPathComponent("running.marker"))
    }

    func detectAbnormalExitAndMarkRunning() throws -> Bool {
        let abnormalExit = FileManager.default.fileExists(atPath: markerURL.path)
        let data = Data("pid=\(getpid())\n".utf8)
        try data.write(to: markerURL, options: .atomic)
        return abnormalExit
    }

    func markCleanExit() throws {
        guard FileManager.default.fileExists(atPath: markerURL.path) else { return }
        try FileManager.default.removeItem(at: markerURL)
    }
}

enum SafeModeState {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var enabled = false

    static var isEnabled: Bool {
        lock.withLock { enabled }
    }

    static func setEnabled(_ value: Bool) {
        lock.withLock { enabled = value }
    }
}
