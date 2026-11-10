import Combine
import Foundation
import OSLog

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
