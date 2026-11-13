enum CleanupOutcome: String, Equatable, Sendable {
    case cleaned
    case fallbackNotEnabled = "fallback_not_enabled"
    case fallbackModelNotReady = "fallback_model_not_ready"
    case fallbackDownloadNotApproved = "fallback_download_not_approved"
    case fallbackTimeout = "fallback_timeout"
    case fallbackRejected = "fallback_rejected"

    var title: String {
        switch self {
        case .cleaned: "Nettoyé"
        case .fallbackNotEnabled: "Nettoyage désactivé"
        case .fallbackModelNotReady: "Modèle non prêt"
        case .fallbackDownloadNotApproved: "Téléchargement non approuvé"
        case .fallbackTimeout: "Délai dépassé"
        case .fallbackRejected: "Résultat rejeté"
        }
    }
}
