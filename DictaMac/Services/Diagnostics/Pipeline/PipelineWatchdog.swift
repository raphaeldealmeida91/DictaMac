import Foundation

enum PipelineWatchdog {
    static func run<Value: Sendable>(
        stage: String,
        timeout: Duration = .seconds(10),
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        try await PipelineTimeoutRace<Value>().run(
            stage: stage,
            timeout: timeout,
            operation: operation
        )
    }
}

private final class PipelineTimeoutRace<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var resolved = false
    private var operationTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?

    func run(
        stage: String,
        timeout: Duration,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                operationTask = Task {
                    do { finish(.success(try await operation())) }
                    catch { finish(.failure(error)) }
                }
                timeoutTask = Task {
                    do { try await ContinuousClock().sleep(for: timeout) }
                    catch { return }
                    finish(.failure(PipelineWatchdogError.timedOut(stage: stage)))
                }
            }
        } onCancel: {
            finish(.failure(CancellationError()))
        }
    }

    private func finish(_ result: Result<Value, Error>) {
        let values = lock.withLock {
            () -> (CheckedContinuation<Value, Error>?, Task<Void, Never>?, Task<Void, Never>?) in
            guard !resolved else { return (nil, nil, nil) }
            resolved = true
            let continuation = self.continuation
            self.continuation = nil
            return (continuation, operationTask, timeoutTask)
        }
        values.1?.cancel()
        values.2?.cancel()
        values.0?.resume(with: result)
    }
}
