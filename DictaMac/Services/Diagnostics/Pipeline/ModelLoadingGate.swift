import Foundation

final class ModelLoadingGate: ModelLoadingGating, @unchecked Sendable {
    private let lock = NSLock()
    private var isLocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    var isLoading: Bool {
        lock.withLock { isLocked }
    }

    func run<Value: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        await acquire()
        do {
            let value = try await operation()
            release()
            return value
        } catch {
            release()
            throw error
        }
    }

    private func acquire() async {
        await withCheckedContinuation { continuation in
            let acquired = lock.withLock {
                guard isLocked else {
                    isLocked = true
                    return true
                }
                waiters.append(continuation)
                return false
            }
            if acquired {
                continuation.resume()
            }
        }
    }

    private func release() {
        let waiter = lock.withLock {
            guard !waiters.isEmpty else {
                isLocked = false
                return nil as CheckedContinuation<Void, Never>?
            }
            return waiters.removeFirst()
        }
        waiter?.resume()
    }
}
