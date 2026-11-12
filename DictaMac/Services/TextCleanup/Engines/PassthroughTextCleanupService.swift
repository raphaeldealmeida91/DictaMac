struct PassthroughTextCleanupService: TextCleanupService {
    func cleanup(_ text: String, dictionary: [String]) async throws -> String { text }
}
