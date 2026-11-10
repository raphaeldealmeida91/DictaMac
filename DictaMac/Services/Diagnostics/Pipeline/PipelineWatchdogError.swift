import Foundation

enum PipelineWatchdogError: LocalizedError {
    case timedOut(stage: String)

    var errorDescription: String? {
        switch self {
        case .timedOut(let stage): "L’étape « \(stage) » a dépassé 10 secondes."
        }
    }
}
