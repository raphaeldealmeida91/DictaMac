protocol SelectionCorrectionService: Sendable {
    func correct(_ text: String, dictionary: [String]) async throws -> SelectionCorrection
    func engineStatus() async -> SelectionCorrectionEngine
    func engineUnavailableMessage() async -> String?
    func prepare() async
    func requiresPreparation() async -> Bool
    func correctWithMetrics(
        _ text: String,
        dictionary: [String]
    ) async throws -> SelectionCorrectionExecution
}

extension SelectionCorrectionService {
    func engineStatus() async -> SelectionCorrectionEngine { .rulesOnly }
    func engineUnavailableMessage() async -> String? { nil }
    func prepare() async {}
    func requiresPreparation() async -> Bool { false }

    func correctWithMetrics(
        _ text: String,
        dictionary: [String]
    ) async throws -> SelectionCorrectionExecution {
        let engine = await engineStatus()
        let startedAt = ContinuousClock.now
        let correction = try await correct(text, dictionary: dictionary)
        return SelectionCorrectionExecution(
            correction: correction,
            engine: engine,
            inferenceStartedAt: startedAt,
            inferenceFinishedAt: .now,
            modelAlreadyLoaded: true
        )
    }
}

enum SelectionCorrectionEngine: String, Equatable, Sendable {
    case cloud
    case local
    case rulesOnly
}
