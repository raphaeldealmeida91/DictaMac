import Foundation

// The only mutable value, stopHandler, is accessed exclusively under lock.
final class EmergencyAudioRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var stopHandler: (@Sendable (TimeInterval) -> Bool)?

    init() {}

    func install(_ handler: @escaping @Sendable (TimeInterval) -> Bool) {
        lock.withLock { stopHandler = handler }
    }

    func stop(timeout: TimeInterval) -> Bool {
        let handler = lock.withLock { stopHandler }
        return handler?(timeout) ?? true
    }
}
