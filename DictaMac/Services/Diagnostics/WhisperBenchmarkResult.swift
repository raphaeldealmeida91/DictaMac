#if DEBUG
import Foundation

struct WhisperBenchmarkResult: Identifiable, Sendable {
    let id = UUID()
    let model: String
    let duration: TimeInterval
    let text: String
    let error: String?
}
#endif
