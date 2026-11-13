import Foundation

protocol TextCleanupSettings: Sendable {
    var configuredEngine: TextCleanupEngine { get }
    var isEnabled: Bool { get }
    var configuredModel: String { get }
    var configuredLocalModel: String { get }
    var cleanupStyle: CleanupStyle { get }
    var removeIsolatedGenre: Bool { get }
    var localTimeout: TimeInterval { get }
    var cloudTimeout: TimeInterval { get }
    var localDownloadApproved: Bool { get }
    var localModelInactivityTimeout: TimeInterval? { get }
}

extension TextCleanupSettings {
    var localModelInactivityTimeout: TimeInterval? {
        StoredTextCleanupSettings.defaultLocalModelInactivityTimeout
    }
}

protocol TextCleanupSettingsWriting: Sendable {
    func migrate()
    func approveLocalDownload()
    func setEngine(_ engine: TextCleanupEngine)
}
