enum CleanupDecision: Equatable, Sendable {
    case cleaned(String)
    case fallback(reason: String)
}
