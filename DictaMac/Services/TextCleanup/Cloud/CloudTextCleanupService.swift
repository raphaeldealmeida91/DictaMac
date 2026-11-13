import Foundation
import OSLog

actor CloudTextCleanupService: TextCleanupService {
    private let generator: any TextGenerating
    private let settings: any TextCleanupSettings
    private let promptBuilder: CleanupPromptBuilder
    private let wordDiagnostics: (any TextWordDiagnosticsRecording)?
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "DictaMac", category: "TextCleanup")

    init(
        session: URLSession? = nil,
        endpoint: URL,
        apiKeyProvider: @escaping @Sendable () throws -> String? = { try TextCleanupAPIKeyStore.load() },
        settings: any TextCleanupSettings = StoredTextCleanupSettings(),
        modelProvider: (@Sendable () -> String)? = nil,
        promptBuilder: CleanupPromptBuilder = CleanupPromptBuilder(),
        wordDiagnostics: (any TextWordDiagnosticsRecording)? = nil
    ) {
        self.settings = settings
        self.promptBuilder = promptBuilder
        self.wordDiagnostics = wordDiagnostics
        generator = OpenAIResponsesTextGenerator(
            session: session,
            endpoint: endpoint,
            apiKeyProvider: apiKeyProvider,
            modelProvider: modelProvider ?? { settings.configuredModel },
            requestTimeout: { settings.cloudTimeout }
        )
    }

    init(
        generator: any TextGenerating,
        settings: any TextCleanupSettings = StoredTextCleanupSettings(),
        promptBuilder: CleanupPromptBuilder = CleanupPromptBuilder(),
        wordDiagnostics: (any TextWordDiagnosticsRecording)? = nil
    ) {
        self.generator = generator
        self.settings = settings
        self.promptBuilder = promptBuilder
        self.wordDiagnostics = wordDiagnostics
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
        let candidate = try await generator.generate(
            text: text,
            messages: messages(for: text, dictionary: dictionary),
            maxTokens: .max
        )
        await wordDiagnostics?.recordWordCount(candidate, stage: .llmRaw)
        return candidate
    }

    private func messages(for text: String, dictionary: [String]) -> [[String: String]] {
        [
            ["role": "system", "content": promptBuilder.systemPrompt(
                style: settings.cleanupStyle,
                dictionary: dictionary
            )],
            ["role": "user", "content": "<dictation>\(text)</dictation>"]
        ]
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
