import Foundation

// File rotation and writes are serialized by the private lock; no mutable state escapes it.
final class PersistentDiagnosticLog: DiagnosticLogging, @unchecked Sendable {
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

    init() {
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

    func inputLost() { enqueue("event=input_lost") }

    func emergencyRecovery(reason: String) {
        enqueue("event=emergency_recovery reason=\(safeToken(reason))")
    }

    func emergencyExitAndFlush(reason: String) {
        queue.sync {
            writeLine("EMERGENCY_EXIT reason=\(safeToken(reason))")
            try? fileHandle?.synchronize()
        }
    }

    func modelLoadCompleted(duration: TimeInterval, reusedCompiledCache: Bool) {
        modelLoadEnded(
            duration: duration,
            reusedCompiledCache: reusedCompiledCache,
            outcome: "success"
        )
    }

    func modelLoadEnded(
        duration: TimeInterval,
        reusedCompiledCache: Bool?,
        outcome: String
    ) {
        let cache = reusedCompiledCache.map(String.init) ?? "unknown"
        enqueue(
            "event=stage_end stage=\(DiagnosticStage.modelLoad.rawValue) phase=end duration_s=\(fixed(duration)) compiled_cache_reused=\(cache) outcome=\(safeToken(outcome))"
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

    func wordCount(stage: TextWordDiagnosticStage, segmentIndex: Int?, count: Int) {
        var line = "event=text_word_count stage=\(stage.rawValue) words=\(count)"
        if let segmentIndex { line += " segment=\(segmentIndex)" }
        enqueue(line)
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
        rotateFiles(current: logURL)
        openLogIfNeeded()
    }

    private func rotateFiles(current logURL: URL) {
        try? fileManager.removeItem(at: rotatedURL(index: Self.retainedFileCount - 1))
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
