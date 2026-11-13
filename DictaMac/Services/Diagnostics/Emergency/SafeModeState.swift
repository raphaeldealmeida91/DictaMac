import Foundation

protocol SafeModeControlling: Sendable {
    var isEnabled: Bool { get }
    func setEnabled(_ value: Bool)
}

struct SafeModeState: SafeModeControlling {
    static let localCleanupUnavailableMessage = "Mode sûr actif : redémarrez DictaMac normalement"
    static let cleanupSuspendedMessage = "Mode sûr actif (la dernière sortie était anormale). Le nettoyage local est suspendu."

    private static let lock = NSLock()
    private nonisolated(unsafe) static var enabled = false

    static var isEnabled: Bool {
        lock.withLock { enabled }
    }

    static func setEnabled(_ value: Bool) {
        lock.withLock { enabled = value }
    }

    var isEnabled: Bool { Self.isEnabled }

    func setEnabled(_ value: Bool) {
        Self.setEnabled(value)
    }
}
