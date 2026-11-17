import Foundation
import OSLog

actor LocalTextCleanupService: TextCleanupService {
    private let generator: any LocalTextGenerating
    private let settings: any TextCleanupSettings
    private let timeout: Duration?
    private let promptBuilder: CleanupPromptBuilder
    private let validator: DictationCleanupValidator
    private let wordDiagnostics: (any TextWordDiagnosticsRecording)?
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "DictaMac", category: "TextCleanup")

    init(
        generator: any LocalTextGenerating,
        settings: any TextCleanupSettings = StoredTextCleanupSettings(),
        timeout: Duration? = nil,
        promptBuilder: CleanupPromptBuilder = CleanupPromptBuilder(),
        validator: DictationCleanupValidator = DictationCleanupValidator(),
        wordDiagnostics: (any TextWordDiagnosticsRecording)? = nil
    ) {
        self.generator = generator
        self.settings = settings
        self.timeout = timeout
        self.promptBuilder = promptBuilder
        self.validator = validator
        self.wordDiagnostics = wordDiagnostics
    }

    func cleanup(
        _ text: String,
        dictionary: [String],
        context: DictationContext
    ) async throws -> String {
        guard TextCleanupPostProcessor.shouldClean(text) else {
            logger.info("cleanup engine=local decision=fast-rules reason=under-two-words")
            return FastRulesTextCleanupService.cleanup(text, context: context)
        }
        try await generator.prepare()
        return try await generateCleanup(for: text, dictionary: dictionary, context: context)
    }

    private func generateCleanup(
        for text: String,
        dictionary: [String],
        context: DictationContext
    ) async throws -> String {
        let start = ContinuousClock.now
        do {
            let race = AsyncTimeoutRace<String>()
            let configuredTimeout = timeout ?? .milliseconds(Int64(settings.localTimeout * 1_000))
            let messages = messages(for: text, dictionary: dictionary, context: context)
            let candidate = try await race.run(timeout: configuredTimeout) { [generator] in
                try await generator.generate(text: text, messages: messages, maxTokens: .max)
            }
            await wordDiagnostics?.recordWordCount(candidate, stage: .llmRaw)
            let decision = validatedDecision(raw: text, candidate: candidate, dictionary: dictionary)
            logDuration(since: start, decision: decision)
            return validatedText(
                from: decision,
                original: text,
                candidateLength: candidate.count,
                context: context
            )
        } catch is CancellationError {
            logger.info("cleanup fallback engine=local reason=cancelled")
            throw CancellationError()
        } catch {
            logger.warning("cleanup fallback engine=local reason=\(error.localizedDescription, privacy: .private)")
            logDuration(since: start, decision: .fallback(reason: "generation error"))
            throw error
        }
    }

    private func validatedDecision(
        raw: String,
        candidate: String,
        dictionary: [String]
    ) -> CleanupDecision {
        switch validator.validate(original: raw, candidate: candidate, dictionary: dictionary) {
        case .accepted(let cleaned):
            return .cleaned(cleaned)
        case .rejected(let reason):
            return .fallback(reason: reason.rawValue)
        }
    }

    private func validatedText(
        from decision: CleanupDecision,
        original: String,
        candidateLength: Int,
        context: DictationContext
    ) -> String {
        switch decision {
        case .cleaned(let cleaned):
            return cleaned
        case .fallback(let reason):
            logger.warning(
                "cleanup rejected reason=\(reason, privacy: .public) input_length=\(original.count) output_length=\(candidateLength)"
            )
            return FastRulesTextCleanupService.cleanup(
                original,
                removeIsolatedGenre: settings.removeIsolatedGenre,
                context: context
            )
        }
    }

    private func messages(
        for text: String,
        dictionary: [String],
        context: DictationContext
    ) -> [[String: String]] {
        [
            ["role": "system", "content": promptBuilder.systemPrompt(
                style: settings.cleanupStyle,
                dictionary: dictionary,
                context: context
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
