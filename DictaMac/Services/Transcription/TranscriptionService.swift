protocol TranscriptionService: Sendable {
    func prepare() async throws
    func transcribe(
        _ samples: [Float],
        language: String?,
        context: DictationContext
    ) async throws -> String
}

extension TranscriptionService {
    func transcribe(_ samples: [Float], language: String?) async throws -> String {
        try await transcribe(samples, language: language, context: .empty)
    }
}
