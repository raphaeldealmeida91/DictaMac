import Foundation

final class EmergencyAudioRegistry: @unchecked Sendable {
    static let shared = EmergencyAudioRegistry()

    private let lock = NSLock()
    private var stopHandler: (@Sendable (TimeInterval) -> Bool)?

    private init() {}

    func install(_ handler: @escaping @Sendable (TimeInterval) -> Bool) {
        lock.withLock { stopHandler = handler }
    }

    func stop(timeout: TimeInterval) -> Bool {
        let handler = lock.withLock { stopHandler }
        return handler?(timeout) ?? true
    }
}
