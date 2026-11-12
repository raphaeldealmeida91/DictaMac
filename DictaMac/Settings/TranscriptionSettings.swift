import Foundation

protocol TranscriptionSettings: Sendable {
    var configuredModel: String { get }
    var configuredLanguage: String? { get }
    var isLowMemoryMac: Bool { get }
}

protocol TranscriptionModelPathStoring: Sendable {
    func storedModelPath(for model: String) -> String?
    func setStoredModelPath(_ path: String, for model: String)
}
