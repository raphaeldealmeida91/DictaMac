protocol TranscriptionService: Sendable {
    func prepare() async throws
    func transcribe(_ samples: [Float], language: String?) async throws -> String
}
