protocol TextCleanupService: Sendable {
    func cleanup(_ text: String) async throws -> String
}
