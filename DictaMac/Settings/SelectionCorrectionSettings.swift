import Foundation

protocol SelectionCorrectionSettings: Sendable {
    var isEnabled: Bool { get }
    var isClipboardFallbackEnabled: Bool { get }
    var allowsCloud: Bool { get }
    var excludedBundleIDs: Set<String> { get }
}
