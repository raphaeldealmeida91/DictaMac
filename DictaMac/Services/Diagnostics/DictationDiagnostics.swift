import Combine
import Foundation
import OSLog

@MainActor
final class DictationDiagnostics: ObservableObject, DictationMetricsRecording {
    @Published private(set) var lastTimings: DictationTimings?
    @Published private(set) var lastWordDiagnostics: TextWordDiagnostics?
    private let diagnosticLog: any DiagnosticLogging
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "DictaMac",
        category: "Latency"
    )

    init(diagnosticLog: any DiagnosticLogging) {
        self.diagnosticLog = diagnosticLog
    }

    func beginWordDiagnostics() {
        lastWordDiagnostics = TextWordDiagnostics(date: Date(), entries: [])
    }

    func recordWordCount(
        _ count: Int,
        stage: TextWordDiagnosticStage,
        segmentIndex: Int? = nil
    ) {
        let entry = TextWordDiagnosticEntry(stage: stage, segmentIndex: segmentIndex, wordCount: count)
        let current = lastWordDiagnostics ?? TextWordDiagnostics(date: Date(), entries: [])
        lastWordDiagnostics = TextWordDiagnostics(date: current.date, entries: current.entries + [entry])
        diagnosticLog.wordCount(stage: stage, segmentIndex: segmentIndex, count: count)
    }

    func record(_ timings: DictationTimings) {
        lastTimings = timings
        logger.info(
            "dictation latency stop_audio=\(timings.stopAudio, format: .fixed(precision: 3))s transcription=\(timings.transcription, format: .fixed(precision: 3))s cleanup=\(timings.cleanup, format: .fixed(precision: 3))s injection=\(timings.injection, format: .fixed(precision: 3))s total_release_to_paste=\(timings.total, format: .fixed(precision: 3))s cleanup_engine=\(timings.cleanupEngine.rawValue, privacy: .public)"
        )
    }
}

extension DictationDiagnostics: TextWordDiagnosticsRecording {}
