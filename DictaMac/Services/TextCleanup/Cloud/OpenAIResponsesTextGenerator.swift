import Foundation
import OSLog

actor OpenAIResponsesTextGenerator: TextGenerating {
    private enum Constants {
        static let resourceTimeout: TimeInterval = 60
    }

    private let session: URLSession
    private let endpoint: URL
    private let apiKeyProvider: @Sendable () throws -> String?
    private let modelProvider: @Sendable () -> String
    private let requestTimeout: @Sendable () -> TimeInterval
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "DictaMac",
        category: "TextGeneration"
    )

    init(
        session: URLSession? = nil,
        endpoint: URL,
        apiKeyProvider: @escaping @Sendable () throws -> String?,
        modelProvider: @escaping @Sendable () -> String,
        requestTimeout: @escaping @Sendable () -> TimeInterval
    ) {
        self.endpoint = endpoint
        self.apiKeyProvider = apiKeyProvider
        self.modelProvider = modelProvider
        self.requestTimeout = requestTimeout
        self.session = session ?? Self.makeSession(timeout: requestTimeout())
    }

    func generate(
        text: String,
        messages: [[String: String]],
        maxTokens: Int
    ) async throws -> String {
        let request = try makeRequest(text: text, messages: messages, maxTokens: maxTokens)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw TextCleanupError.invalidResponse }
        logger.info("text generation HTTP status=\(http.statusCode)")
        guard (200..<300).contains(http.statusCode) else {
            throw TextCleanupError.requestFailed(statusCode: http.statusCode)
        }
        return try candidate(from: data)
    }

    private func makeRequest(
        text: String,
        messages: [[String: String]],
        maxTokens: Int
    ) throws -> URLRequest {
        guard let key = try apiKeyProvider(), !key.isEmpty else { throw TextCleanupError.missingAPIKey }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeout()
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(OpenAIResponsesRequest(
            model: modelProvider(),
            instructions: content(for: "system", in: messages),
            input: content(for: "user", in: messages) ?? text,
            maxOutputTokens: maxTokens == .max ? nil : maxTokens,
            store: false
        ))
        return request
    }

    private func content(for role: String, in messages: [[String: String]]) -> String? {
        messages.first(where: { $0["role"] == role })?["content"]
    }

    private func candidate(from data: Data) throws -> String {
        let body = try JSONDecoder().decode(OpenAIResponsesResponse.self, from: data)
        guard let candidate = body.output
            .flatMap({ $0.content ?? [] })
            .first(where: { $0.type == "output_text" })?.text else {
            throw TextCleanupError.invalidResponse
        }
        return candidate
    }

    private static func makeSession(timeout: TimeInterval) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = Constants.resourceTimeout
        return URLSession(configuration: configuration)
    }
}

private struct OpenAIResponsesRequest: Encodable {
    let model: String
    let instructions: String?
    let input: String
    let maxOutputTokens: Int?
    let store: Bool

    enum CodingKeys: String, CodingKey {
        case model, instructions, input, store
        case maxOutputTokens = "max_output_tokens"
    }
}

private struct OpenAIResponsesResponse: Decodable {
    struct Output: Decodable { let content: [Content]? }
    struct Content: Decodable { let type: String; let text: String? }
    let output: [Output]
}
