import Foundation

final class EmergencyCancellationHub: @unchecked Sendable {
    static let shared = EmergencyCancellationHub()

    private let lock = NSLock()
    private var handlers: [@Sendable () -> Void] = []

    private init() {}

    func replaceHandlers(_ handlers: [@Sendable () -> Void]) {
        lock.withLock { self.handlers = handlers }
    }

    func cancelAll() {
        let handlers = lock.withLock { self.handlers }
        handlers.forEach { $0() }
    }
}
