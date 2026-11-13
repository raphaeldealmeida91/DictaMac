protocol TextGenerating: Sendable {
    func generate(text: String, messages: [[String: String]], maxTokens: Int) async throws -> String
}

protocol LocalTextGenerating: TextGenerating {
    var isReady: Bool { get async }
}
