enum TextWordDiagnosticStage: String, CaseIterable, Sendable {
    case whisperSegment = "whisper_segment"
    case whisperTotal = "whisper_total"
    case segmentedMerge = "segmented_merge"
    case dictionary = "dictionary"
    case deterministicRules = "deterministic_rules"
    case llmRaw = "llm_raw"
    case postProcessor = "post_processor"
    case injected = "injected"

    var title: String {
        switch self {
        case .whisperSegment: "Whisper — segments"
        case .whisperTotal: "Whisper — total brut"
        case .segmentedMerge: "Après fusion"
        case .dictionary: "Après dictionnaire"
        case .deterministicRules: "Après règles"
        case .llmRaw: "Sortie brute du LLM"
        case .postProcessor: "Après post-traitement"
        case .injected: "Texte injecté"
        }
    }
}
