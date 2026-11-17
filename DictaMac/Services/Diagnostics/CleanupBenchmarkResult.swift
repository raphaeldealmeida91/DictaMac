#if DEBUG
import Foundation

struct CleanupBenchmarkResult: Sendable, Equatable {
    enum Outcome: Sendable, Equatable {
        case completed
        case skipped(String)
        case failed(String)
    }

    let modelID: String
    let caseCount: Int
    let medianLatency: TimeInterval?
    let percentile95Latency: TimeInterval?
    let validatorRejectionRate: Double?
    let normalizedEditDistance: Double?
    let outcome: Outcome

    static func skipped(modelID: String, reason: String) -> Self {
        empty(modelID: modelID, outcome: .skipped(reason))
    }

    static func failed(modelID: String, reason: String) -> Self {
        empty(modelID: modelID, outcome: .failed(reason))
    }

    private static func empty(modelID: String, outcome: Outcome) -> Self {
        Self(
            modelID: modelID,
            caseCount: 0,
            medianLatency: nil,
            percentile95Latency: nil,
            validatorRejectionRate: nil,
            normalizedEditDistance: nil,
            outcome: outcome
        )
    }
}
#endif
