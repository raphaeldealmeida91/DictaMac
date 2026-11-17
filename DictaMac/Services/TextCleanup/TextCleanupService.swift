protocol TextCleanupService: Sendable {
    func cleanup(
        _ text: String,
        dictionary: [String],
        context: DictationContext
    ) async throws -> String
}

extension TextCleanupService {
    func cleanup(_ text: String) async throws -> String {
        try await cleanup(text, dictionary: [], context: .empty)
    }

    func cleanup(_ text: String, dictionary: [String]) async throws -> String {
        try await cleanup(text, dictionary: dictionary, context: .empty)
    }
}
