import Foundation

protocol EmergencyCancellationRegistering: AnyObject {
    func replaceHandlers(_ handlers: [@Sendable () -> Void])
}

// The handler collection is copied and replaced exclusively under lock.
final class EmergencyCancellationHub: EmergencyCancellationRegistering, @unchecked Sendable {
    private let lock = NSLock()
    private var handlers: [@Sendable () -> Void] = []

    init() {}

    func replaceHandlers(_ handlers: [@Sendable () -> Void]) {
        lock.withLock { self.handlers = handlers }
    }

    func cancelAll() {
        let handlers = lock.withLock { self.handlers }
        handlers.forEach { $0() }
    }
}
