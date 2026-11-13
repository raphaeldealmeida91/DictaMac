import Foundation

struct DictationTimings: Equatable, Sendable {
    let date: Date
    let stopAudio: TimeInterval
    let transcription: TimeInterval
    let cleanup: TimeInterval
    let injection: TimeInterval
    let total: TimeInterval
    let cleanupEngine: TextCleanupEngine
    let cleanupOutcome: CleanupOutcome
}
