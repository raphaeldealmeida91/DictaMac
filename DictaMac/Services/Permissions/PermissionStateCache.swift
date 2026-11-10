import Foundation

// The cached authorization bit is accessed exclusively under lock.
final class PermissionStateCache: AccessibilityPermissionCaching, @unchecked Sendable {
    private let lock = NSLock()
    private var accessibilityAuthorized = false

    var isAccessibilityAuthorized: Bool {
        lock.withLock { accessibilityAuthorized }
    }

    func updateAccessibility(_ authorized: Bool) {
        lock.withLock { accessibilityAuthorized = authorized }
    }
}
