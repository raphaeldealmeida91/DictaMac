import Foundation
import OSLog

actor CloudTextCleanupService: TextCleanupService {
    private enum Constants {
        static let resourceTimeout: TimeInterval = 60
    }

    private let session: URLSession
    private let endpoint: URL
    private let apiKeyProvider: @Sendable () throws -> String?
    private let modelProvider: @Sendable () -> String
    private let settings: any TextCleanupSettings
    private let promptBuilder: CleanupPromptBuilder
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "DictaMac", category: "TextCleanup")

    init(
        session: URLSession? = nil,
        endpoint: URL,
        apiKeyProvider: @escaping @Sendable () throws -> String? = { try TextCleanupAPIKeyStore.load() },
        settings: any TextCleanupSettings = StoredTextCleanupSettings(),
        modelProvider: (@Sendable () -> String)? = nil,
        promptBuilder: CleanupPromptBuilder = CleanupPromptBuilder()
    ) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = settings.cloudTimeout
            config.timeoutIntervalForResource = Constants.resourceTimeout
            self.session = URLSession(configuration: config)
        }
        self.endpoint = endpoint
        self.apiKeyProvider = apiKeyProvider
        self.modelProvider = modelProvider ?? { settings.configuredModel }
        self.settings = settings
        self.promptBuilder = promptBuilder
    }

    func cleanup(_ text: String, dictionary: [String]) async throws -> String {
        guard TextCleanupPostProcessor.shouldClean(text) else {
            logger.info("cleanup engine=cloud decision=fast-rules reason=under-two-words")
            return FastRulesTextCleanupService.cleanup(text)
        }
        let start = ContinuousClock.now
        do {
            let candidate = try await requestCleanup(text, dictionary: dictionary)
            return try processed(raw: text, candidate: candidate, dictionary: dictionary, start: start)
        } catch is CancellationError {
            logger.info("cleanup fallback engine=cloud reason=cancelled")
            throw CancellationError()
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                logger.info("cleanup fallback engine=cloud reason=cancelled")
                throw CancellationError()
            }
            logger.warning("cleanup fallback engine=cloud reason=\(error.localizedDescription, privacy: .private)")
            logDuration(since: start, decision: "fallback")
            throw error
        }
    }

    private func requestCleanup(_ text: String, dictionary: [String]) async throws -> String {
        guard let key = try apiKeyProvider(), !key.isEmpty else { throw TextCleanupError.missingAPIKey }
        let request = try makeRequest(text: text, dictionary: dictionary, key: key)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw TextCleanupError.invalidResponse }
        logger.info("cleanup cloud HTTP status=\(http.statusCode)")
        guard (200..<300).contains(http.statusCode) else {
            throw TextCleanupError.requestFailed(statusCode: http.statusCode)
        }
        return try candidate(from: data)
    }

    private func makeRequest(text: String, dictionary: [String], key: String) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = settings.cloudTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(CleanupRequest(
            model: modelProvider(),
            instructions: promptBuilder.systemPrompt(style: settings.cleanupStyle, dictionary: dictionary),
            input: "<dictation>\(text)</dictation>",
            store: false
        ))
        return request
    }

    private func candidate(from data: Data) throws -> String {
        let body = try JSONDecoder().decode(CleanupResponse.self, from: data)
        guard let candidate = body.output
            .flatMap({ $0.content ?? [] })
            .first(where: { $0.type == "output_text" })?.text else {
            throw TextCleanupError.invalidResponse
        }
        return candidate
    }

    private func processed(
        raw: String,
        candidate: String,
        dictionary: [String],
        start: ContinuousClock.Instant
    ) throws -> String {
        switch TextCleanupPostProcessor.process(
            raw: raw,
            candidate: candidate,
            style: settings.cleanupStyle,
            dictionary: dictionary
        ) {
        case .cleaned(let cleaned):
            logDuration(since: start, decision: "cleaned")
            return cleaned
        case .fallback(let reason):
            logger.warning("cleanup rejected: \(reason, privacy: .private)")
            logDuration(since: start, decision: "fallback")
            throw TextCleanupError.outputRejected(reason: reason)
        }
    }

    private func logDuration(since start: ContinuousClock.Instant, decision: String) {
        let duration = start.duration(to: .now)
        let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        logger.info(
            "cleanup engine=cloud duration=\(seconds, format: .fixed(precision: 3))s decision=\(decision, privacy: .private)"
        )
    }
}

private struct CleanupRequest: Encodable {
    let model: String
    let instructions: String
    let input: String
    let store: Bool
}

private struct CleanupResponse: Decodable {
    struct Output: Decodable { let content: [Content]? }
    struct Content: Decodable { let type: String; let text: String? }
    let output: [Output]
}
