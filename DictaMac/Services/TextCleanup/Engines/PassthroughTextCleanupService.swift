struct PassthroughTextCleanupService: TextCleanupService {
    func cleanup(_ text: String) async throws -> String { text }
}
