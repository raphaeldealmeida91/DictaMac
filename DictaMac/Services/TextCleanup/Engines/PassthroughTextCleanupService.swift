struct PassthroughTextCleanupService: TextCleanupService {
    func cleanup(
        _ text: String,
        dictionary: [String],
        context: DictationContext
    ) async throws -> String { text }
}
