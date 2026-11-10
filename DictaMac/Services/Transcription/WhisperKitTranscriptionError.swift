import Foundation

enum WhisperKitTranscriptionError: LocalizedError {
    case modelNotPrepared

    var errorDescription: String? {
        switch self {
        case .modelNotPrepared: "Le modèle WhisperKit n’est pas chargé."
        }
    }
}
