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
}

protocol TextCleanupSettingsWriting: Sendable {
    func migrate()
    func approveLocalDownload()
    func setEngine(_ engine: TextCleanupEngine)
}
