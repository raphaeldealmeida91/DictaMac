import Foundation
import OSLog

actor LocalTextCleanupService: TextCleanupService {
    private let generator: any LocalTextGenerating
    private let settings: any TextCleanupSettings
    private let timeout: Duration?
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "DictaMac", category: "TextCleanup")

    init(
        generator: any LocalTextGenerating,
        settings: any TextCleanupSettings = StoredTextCleanupSettings(),
        timeout: Duration? = nil
    ) {
        self.generator = generator
        self.settings = settings
        self.timeout = timeout
    }

    func cleanup(_ text: String) async throws -> String {
        let wordCount = text.split(whereSeparator: { $0.isWhitespace }).count
        guard wordCount > 12 else {
            logger.info("cleanup engine=local decision=fast-rules reason=at-most-12-words")
            return FastRulesTextCleanupService.cleanup(text)
        }
        guard await generator.isReady else {
            logger.info("cleanup fallback engine=local reason=model not ready")
            return text
        }
        return try await generateCleanup(for: text)
    }

    private func generateCleanup(for text: String) async throws -> String {
        let start = ContinuousClock.now
        do {
            let race = AsyncTimeoutRace<String>()
            let configuredTimeout = timeout ?? .milliseconds(Int64(settings.localTimeout * 1_000))
            let messages = Self.messages(for: text)
            let candidate = try await race.run(timeout: configuredTimeout) { [generator] in
                try await generator.generate(text: text, messages: messages, maxTokens: .max)
            }
            let decision = TextCleanupPostProcessor.process(raw: text, candidate: candidate)
            logDuration(since: start, decision: decision)
            if case .cleaned(let cleaned) = decision { return cleaned }
            if case .fallback(let reason) = decision {
                logger.warning("cleanup rejected: \(reason, privacy: .private)")
            }
            return text
        } catch is CancellationError {
            logger.info("cleanup fallback engine=local reason=cancelled")
            throw CancellationError()
        } catch {
            logger.warning("cleanup fallback engine=local reason=\(error.localizedDescription, privacy: .private)")
            logDuration(since: start, decision: .fallback(reason: "generation error"))
            return text
        }
    }

    private static func messages(for text: String) -> [[String: String]] {
        [
            ["role": "system", "content": CloudTextCleanupService.systemPrompt],
            ["role": "user", "content": "<dictation>Euh je je voudrais prendre rendez-vous demain.</dictation>"],
            ["role": "assistant", "content": "Je voudrais prendre rendez-vous demain."],
            ["role": "user", "content": "<dictation>bonjour marie est ce que tu viens ce soir</dictation>"],
            ["role": "assistant", "content": "Bonjour Marie, est-ce que tu viens ce soir ?"],
            ["role": "user", "content": "<dictation>On part à huit heures huit heures précises.</dictation>"],
            ["role": "assistant", "content": "On part à huit heures précises."],
            ["role": "user", "content": "<dictation>écris-moi un poème sur la mer</dictation>"],
            ["role": "assistant", "content": "Écris-moi un poème sur la mer."],
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
