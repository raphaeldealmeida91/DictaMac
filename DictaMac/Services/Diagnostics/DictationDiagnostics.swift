import Foundation
import OSLog
import Darwin

enum DiagnosticStage: String, Sendable {
    case modelLoad = "model_load"
    case recording
    case transcription
    case cleanup
    case injection
}

enum DiagnosticMemoryContext: String, Sendable {
    case startup
    case memoryPressureWarning = "memory_pressure_warning"
    case memoryPressureCritical = "memory_pressure_critical"
    case dictationStarted = "dictation_started"
    case dictationFinished = "dictation_finished"
    case whisperUnloaded = "whisper_unloaded"
    case whisperLoaded = "whisper_loaded"
    case mlxUnloaded = "mlx_unloaded"
    case mlxLoadFinished = "mlx_load_finished"
}

/// A deliberately narrow diagnostics sink: its API accepts only operational
/// metadata, so dictated text and credentials cannot accidentally reach disk.
final class PersistentDiagnosticLog: @unchecked Sendable {
    static let shared = PersistentDiagnosticLog()
    static let maximumFileSize = 2 * 1_024 * 1_024
    static let retainedFileCount = 3

    static func logsDirectoryURL() throws -> URL {
        let library = try FileManager.default.url(
            for: .libraryDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = library
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("DictaMac", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return directory
    }

    private let queue = DispatchQueue(
        label: "com.raphaeldealmeida.DictaMac.persistent-diagnostics",
        qos: .utility
    )
    private let fileManager = FileManager.default
    private var fileHandle: FileHandle?
    private var logURL: URL?
    private let formatter: ISO8601DateFormatter

    private init() {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.formatter = formatter
        queue.sync {
            openLogIfNeeded()
            writeLine("event=session_start")
        }
    }

    func stage(
        _ stage: DiagnosticStage,
        phase: String,
        duration: TimeInterval? = nil,
        audioDuration: TimeInterval? = nil,
        segmentCount: Int? = nil
    ) {
        let event = switch phase {
        case "begin": "stage_begin"
        case "end": "stage_end"
        default: "stage"
        }
        var line = "event=\(event) stage=\(stage.rawValue) phase=\(safeToken(phase))"
        if let duration { line += " duration_s=\(fixed(duration))" }
        if let audioDuration { line += " audio_s=\(fixed(audioDuration))" }
        if let segmentCount { line += " segments=\(segmentCount)" }
        enqueue(line)
    }

    func inputLost() {
        enqueue("event=input_lost")
    }

    func emergencyRecovery(reason: String) {
        enqueue("event=emergency_recovery reason=\(safeToken(reason))")
    }

    /// Synchronous by design: `_exit` does not run process teardown or flush stdio.
    func emergencyExitAndFlush(reason: String) {
        queue.sync {
            writeLine("EMERGENCY_EXIT reason=\(safeToken(reason))")
            try? fileHandle?.synchronize()
        }
    }

    func modelLoadCompleted(duration: TimeInterval, reusedCompiledCache: Bool) {
        enqueue(
            "event=stage stage=\(DiagnosticStage.modelLoad.rawValue) phase=end duration_s=\(fixed(duration)) compiled_cache_reused=\(reusedCompiledCache)"
        )
    }

    func memory(context: DiagnosticMemoryContext, bytes: UInt64?) {
        let value = bytes.map(String.init) ?? "unavailable"
        enqueue("event=memory context=\(context.rawValue) phys_footprint_bytes=\(value)")
    }

    func memoryPressure(critical: Bool) {
        enqueue("event=memory_pressure level=\(critical ? "critical" : "warning")")
    }

    func mainThreadStall(duration: TimeInterval) {
        enqueue("event=main_thread_stall duration_s=\(fixed(duration))")
    }

    func eventTapDisabled(reason: String) {
        enqueue("event=event_tap_disabled reason=\(safeToken(reason))")
    }

    private func enqueue(_ message: String) {
        queue.async { [weak self] in self?.writeLine(message) }
    }

    private func writeLine(_ message: String) {
        openLogIfNeeded()
        let line = "\(formatter.string(from: Date())) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        rotateIfNeeded(adding: data.count)
        do {
            try fileHandle?.write(contentsOf: data)
            try fileHandle?.synchronize()
        } catch {
            fileHandle = nil
        }
    }

    private func openLogIfNeeded() {
        guard fileHandle == nil else { return }
        do {
            let directory = try Self.logsDirectoryURL()
            let url = directory.appendingPathComponent("session.log")
            if !fileManager.fileExists(atPath: url.path) {
                _ = fileManager.createFile(
                    atPath: url.path,
                    contents: nil,
                    attributes: [.posixPermissions: 0o600]
                )
            }
            logURL = url
            fileHandle = try FileHandle(forWritingTo: url)
            try fileHandle?.seekToEnd()
        } catch {
            fileHandle = nil
        }
    }

    private func rotateIfNeeded(adding byteCount: Int) {
        guard let logURL,
              let size = try? fileManager.attributesOfItem(atPath: logURL.path)[.size] as? NSNumber,
              size.intValue + byteCount > Self.maximumFileSize else { return }
        try? fileHandle?.close()
        fileHandle = nil

        let oldest = rotatedURL(index: Self.retainedFileCount - 1)
        try? fileManager.removeItem(at: oldest)
        if Self.retainedFileCount > 2 {
            for index in stride(from: Self.retainedFileCount - 2, through: 1, by: -1) {
                let source = rotatedURL(index: index)
                let destination = rotatedURL(index: index + 1)
                if fileManager.fileExists(atPath: source.path) {
                    try? fileManager.moveItem(at: source, to: destination)
                }
            }
        }
        if fileManager.fileExists(atPath: logURL.path) {
            try? fileManager.moveItem(at: logURL, to: rotatedURL(index: 1))
        }
        openLogIfNeeded()
    }

    private func rotatedURL(index: Int) -> URL {
        let directory = logURL?.deletingLastPathComponent() ?? fileManager.temporaryDirectory
        return directory.appendingPathComponent("session.log.\(index)")
    }

    private func safeToken(_ value: String) -> String {
        String(value.unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
                .contains(scalar) ? Character(String(scalar)) : "_"
        })
    }

    private func fixed(_ value: TimeInterval) -> String {
        String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}

struct DictationTimings: Equatable, Sendable {
    let date: Date
    let stopAudio: TimeInterval
    let transcription: TimeInterval
    let cleanup: TimeInterval
    let injection: TimeInterval
    let total: TimeInterval
    let cleanupEngine: TextCleanupEngine
}

@MainActor
final class DictationDiagnostics: ObservableObject {
    static let shared = DictationDiagnostics()

    @Published private(set) var lastTimings: DictationTimings?
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "DictaMac",
        category: "Latency"
    )

    private init() {}

    func record(_ timings: DictationTimings) {
        lastTimings = timings
        logger.info(
            "dictation latency stop_audio=\(timings.stopAudio, format: .fixed(precision: 3))s transcription=\(timings.transcription, format: .fixed(precision: 3))s cleanup=\(timings.cleanup, format: .fixed(precision: 3))s injection=\(timings.injection, format: .fixed(precision: 3))s total_release_to_paste=\(timings.total, format: .fixed(precision: 3))s cleanup_engine=\(timings.cleanupEngine.rawValue, privacy: .public)"
        )
    }
}

enum ProcessMemoryDiagnostics {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "DictaMac",
        category: "Memory"
    )

    static func logFootprint(_ context: DiagnosticMemoryContext) {
        let bytes = physicalFootprint
        PersistentDiagnosticLog.shared.memory(context: context, bytes: bytes)
        guard let bytes else {
            logger.error("phys_footprint unavailable context=\(context.rawValue, privacy: .public)")
            return
        }
        logger.info(
            "phys_footprint context=\(context.rawValue, privacy: .public) bytes=\(bytes) mib=\(Double(bytes) / 1_048_576, format: .fixed(precision: 1))"
        )
    }

    static var physicalFootprint: UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return status == KERN_SUCCESS ? info.phys_footprint : nil
    }
}

enum PerformanceSignposts {
    static let signposter = OSSignposter(
        subsystem: Bundle.main.bundleIdentifier ?? "DictaMac",
        category: "Pipeline"
    )
}

/// Async mutex used only for heavyweight model loading. It prevents Core ML and
/// MLX from allocating their large working sets concurrently.
actor ModelLoadingGate {
    static let shared = ModelLoadingGate()
    private var isLocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func run<Value: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        await acquire()
        do {
            let value = try await operation()
            release()
            return value
        } catch {
            release()
            throw error
        }
    }

    private func acquire() async {
        if !isLocked {
            isLocked = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        if waiters.isEmpty {
            isLocked = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}

enum PipelineWatchdogError: LocalizedError {
    case timedOut(stage: String)

    var errorDescription: String? {
        switch self {
        case .timedOut(let stage): "L’étape « \(stage) » a dépassé 10 secondes."
        }
    }
}

private final class PipelineTimeoutRace<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var resolved = false
    private var operationTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?

    func run(
        stage: String,
        timeout: Duration,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                operationTask = Task {
                    do { finish(.success(try await operation())) }
                    catch { finish(.failure(error)) }
                }
                timeoutTask = Task {
                    do { try await ContinuousClock().sleep(for: timeout) }
                    catch { return }
                    finish(.failure(PipelineWatchdogError.timedOut(stage: stage)))
                }
            }
        } onCancel: {
            finish(.failure(CancellationError()))
        }
    }

    private func finish(_ result: Result<Value, Error>) {
        let values = lock.withLock { () -> (CheckedContinuation<Value, Error>?, Task<Void, Never>?, Task<Void, Never>?) in
            guard !resolved else { return (nil, nil, nil) }
            resolved = true
            let continuation = self.continuation
            self.continuation = nil
            return (continuation, operationTask, timeoutTask)
        }
        values.1?.cancel()
        values.2?.cancel()
        values.0?.resume(with: result)
    }
}

enum PipelineWatchdog {
    static func run<Value: Sendable>(
        stage: String,
        timeout: Duration = .seconds(10),
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        try await PipelineTimeoutRace<Value>().run(
            stage: stage,
            timeout: timeout,
            operation: operation
        )
    }
}

final class MainThreadWatchdog: @unchecked Sendable {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "DictaMac",
        category: "MainThreadWatchdog"
    )
    private let queue = DispatchQueue(label: "com.raphaeldealmeida.DictaMac.main-watchdog", qos: .utility)
    private var timer: DispatchSourceTimer?
    private let lock = NSLock()
    private var pingOutstanding = false

    func start() {
        lock.lock()
        guard timer == nil else { lock.unlock(); return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        self.timer = timer
        lock.unlock()

        timer.schedule(deadline: .now() + .milliseconds(250), repeating: .milliseconds(250))
        timer.setEventHandler { [weak self] in self?.ping() }
        timer.resume()
    }

    func stop() {
        let timer = lock.withLock { () -> DispatchSourceTimer? in
            defer { self.timer = nil }
            return self.timer
        }
        timer?.cancel()
    }

    private func ping() {
        let shouldSend = lock.withLock {
            guard !pingOutstanding else { return false }
            pingOutstanding = true
            return true
        }
        guard shouldSend else { return }
        let sent = DispatchTime.now().uptimeNanoseconds
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let delay = Double(DispatchTime.now().uptimeNanoseconds - sent) / 1_000_000_000
            self.lock.withLock { self.pingOutstanding = false }
            if delay > 0.5 {
                self.logger.fault("main thread stall duration=\(delay, format: .fixed(precision: 3))s")
                PersistentDiagnosticLog.shared.mainThreadStall(duration: delay)
            }
        }
    }
}
