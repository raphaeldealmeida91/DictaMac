import Foundation
import OSLog

actor LocalTextCleanupService: TextCleanupService {
    private let generator: any LocalTextGenerating
    private let settings: any TextCleanupSettings
    private let timeout: Duration?
    private let promptBuilder: CleanupPromptBuilder
    private let wordDiagnostics: (any TextWordDiagnosticsRecording)?
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "DictaMac", category: "TextCleanup")

    init(
        generator: any LocalTextGenerating,
        settings: any TextCleanupSettings = StoredTextCleanupSettings(),
        timeout: Duration? = nil,
        promptBuilder: CleanupPromptBuilder = CleanupPromptBuilder(),
        wordDiagnostics: (any TextWordDiagnosticsRecording)? = nil
    ) {
        self.generator = generator
        self.settings = settings
        self.timeout = timeout
        self.promptBuilder = promptBuilder
        self.wordDiagnostics = wordDiagnostics
    }

    func cleanup(_ text: String, dictionary: [String]) async throws -> String {
        guard TextCleanupPostProcessor.shouldClean(text) else {
            logger.info("cleanup engine=local decision=fast-rules reason=under-two-words")
            return FastRulesTextCleanupService.cleanup(text)
        }
        guard await generator.isReady else {
            logger.info("cleanup fallback engine=local reason=model not ready")
            throw LocalCleanupError.modelNotReady
        }
        return try await generateCleanup(for: text, dictionary: dictionary)
    }

    private func generateCleanup(for text: String, dictionary: [String]) async throws -> String {
        let start = ContinuousClock.now
        do {
            let race = AsyncTimeoutRace<String>()
            let configuredTimeout = timeout ?? .milliseconds(Int64(settings.localTimeout * 1_000))
            let messages = messages(for: text, dictionary: dictionary)
            let candidate = try await race.run(timeout: configuredTimeout) { [generator] in
                try await generator.generate(text: text, messages: messages, maxTokens: .max)
            }
            await wordDiagnostics?.recordWordCount(candidate, stage: .llmRaw)
            let decision = TextCleanupPostProcessor.process(
                raw: text,
                candidate: candidate,
                style: settings.cleanupStyle,
                dictionary: dictionary
            )
            logDuration(since: start, decision: decision)
            return try validatedText(from: decision)
        } catch is CancellationError {
            logger.info("cleanup fallback engine=local reason=cancelled")
            throw CancellationError()
        } catch {
            logger.warning("cleanup fallback engine=local reason=\(error.localizedDescription, privacy: .private)")
            logDuration(since: start, decision: .fallback(reason: "generation error"))
            throw error
        }
    }

    private func validatedText(from decision: CleanupDecision) throws -> String {
        switch decision {
        case .cleaned(let cleaned):
            return cleaned
        case .fallback(let reason):
            logger.warning("cleanup rejected: \(reason, privacy: .private)")
            throw TextCleanupError.outputRejected(reason: reason)
        }
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

    private func logDuration(since start: ContinuousClock.Instant, decision: CleanupDecision) {
        let duration = start.duration(to: .now)
        let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        let value = if case .cleaned = decision { "cleaned" } else { "fallback" }
        logger.info(
            "cleanup engine=local duration=\(seconds, format: .fixed(precision: 3))s decision=\(value, privacy: .private)"
        )
    }
}

// Continuation resolution and task ownership are single-shot and protected by lock.
private final class AsyncTimeoutRace<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var pendingResult: Result<Value, Error>?
    private var operationTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?

    func run(
        timeout: Duration,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                install(continuation)
                let operationTask = Task {
                    do { resolve(.success(try await operation())) }
                    catch { resolve(.failure(error)) }
                }
                let timeoutTask = Task {
                    do { try await ContinuousClock().sleep(for: timeout) }
                    catch { return }
                    resolve(.failure(LocalCleanupError.timeout))
                }
                install(operationTask: operationTask, timeoutTask: timeoutTask)
            }
        } onCancel: {
            resolve(.failure(CancellationError()))
        }
    }

    private func install(_ newContinuation: CheckedContinuation<Value, Error>) {
        let pending = lock.withLock { () -> Result<Value, Error>? in
            if let pendingResult {
                self.pendingResult = nil
                return pendingResult
            }
            continuation = newContinuation
            return nil
        }
        if let pending { newContinuation.resume(with: pending) }
    }

    private func install(operationTask: Task<Void, Never>, timeoutTask: Task<Void, Never>) {
        let alreadyResolved = lock.withLock {
            if continuation == nil { return true }
            self.operationTask = operationTask
            self.timeoutTask = timeoutTask
            return false
        }
        if alreadyResolved {
            operationTask.cancel()
            timeoutTask.cancel()
        }
    }

    private func resolve(_ result: Result<Value, Error>) {
        let values = lock.withLock {
            () -> (CheckedContinuation<Value, Error>?, Task<Void, Never>?, Task<Void, Never>?) in
            guard pendingResult == nil else { return (nil, nil, nil) }
            guard let continuation else {
                pendingResult = result
                return (nil, operationTask, timeoutTask)
            }
            self.continuation = nil
            return (continuation, operationTask, timeoutTask)
        }
        values.1?.cancel()
        values.2?.cancel()
        values.0?.resume(with: result)
    }
}
