import Foundation

enum SafeModeState {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var enabled = false

    static var isEnabled: Bool {
        lock.withLock { enabled }
    }

    static func setEnabled(_ value: Bool) {
        lock.withLock { enabled = value }
    }
}
