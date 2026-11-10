protocol LocalTextGenerating: Sendable {
    var isReady: Bool { get async }
    func generate(text: String, messages: [[String: String]], maxTokens: Int) async throws -> String
}
