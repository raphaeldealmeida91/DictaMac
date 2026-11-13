import Foundation

struct SelectionCorrectionExecution: Sendable {
    let correction: SelectionCorrection
    let engine: SelectionCorrectionEngine
    let inferenceStartedAt: ContinuousClock.Instant
    let inferenceFinishedAt: ContinuousClock.Instant
    let modelAlreadyLoaded: Bool
}
