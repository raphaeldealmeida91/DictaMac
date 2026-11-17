protocol LearnedCorrectionStoring: Sendable {
    func load() throws -> [LearnedCorrectionEntry]
    func save(_ entries: [LearnedCorrectionEntry]) throws
    func clear() throws
}
