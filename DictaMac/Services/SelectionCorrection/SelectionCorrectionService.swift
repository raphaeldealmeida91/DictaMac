protocol SelectionCorrectionService: Sendable {
    func correct(_ text: String, dictionary: [String]) async throws -> SelectionCorrection
}
