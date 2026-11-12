enum CleanupStyle: String, CaseIterable, Identifiable, Sendable {
    case correction
    case polished

    var id: String { rawValue }

    var title: String {
        switch self {
        case .correction: "Correction"
        case .polished: "Rédaction soignée"
        }
    }

    var explanation: String {
        switch self {
        case .correction: "Corrige toutes les fautes sans modifier inutilement la formulation."
        case .polished: "Corrige et reformule pour obtenir un texte clair, lisible et bien structuré."
        }
    }
}
