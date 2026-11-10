enum TextCleanupEngine: String, CaseIterable, Identifiable, Sendable {
    case disabled, fast, local, cloud

    var id: String { rawValue }

    var title: String {
        switch self {
        case .disabled: "Désactivé"
        case .fast: "Rapide"
        case .local: "Local"
        case .cloud: "Cloud"
        }
    }
}
