import Foundation
import Security

enum TextCleanupError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case requestFailed(statusCode: Int)
    case outputRejected(reason: String)
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: "Ajoutez une clé API OpenAI dans Réglages."
        case .invalidResponse: "La réponse du service de nettoyage est invalide."
        case .requestFailed(let statusCode): "Le service de nettoyage a répondu avec le code HTTP \(statusCode)."
        case .outputRejected: "Le résultat du nettoyage a été rejeté."
        case .keychain(let status): "Erreur Keychain (\(status))."
        }
    }
}
