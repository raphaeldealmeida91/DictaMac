protocol TextCleanupService: Sendable {
    func cleanup(_ text: String, dictionary: [String]) async throws -> String
}

extension TextCleanupService {
    func cleanup(_ text: String) async throws -> String {
        try await cleanup(text, dictionary: [])
    }
}
