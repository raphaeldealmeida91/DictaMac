import Foundation

struct StoredTranscriptionSettings: TranscriptionSettings, TranscriptionModelPathStoring {
    static let defaultModel = "openai_whisper-large-v3-v20240930_turbo"
    static let fallbackModel = "small"
    static let lowMemoryThreshold: UInt64 = 16 * 1_024 * 1_024 * 1_024

    private let store: any SettingsStoring
    private let physicalMemory: @Sendable () -> UInt64

    init(
        store: any SettingsStoring = UserDefaultsSettingsStore(),
        physicalMemory: @escaping @Sendable () -> UInt64 = { ProcessInfo.processInfo.physicalMemory }
    ) {
        self.store = store
        self.physicalMemory = physicalMemory
    }

    var isLowMemoryMac: Bool { physicalMemory() < Self.lowMemoryThreshold }
    var recommendedModel: String { isLowMemoryMac ? Self.fallbackModel : Self.defaultModel }

    var configuredModel: String {
        if SafeModeState.isEnabled { return Self.fallbackModel }
        return nonEmptyString(for: .transcriptionModel) ?? recommendedModel
    }

    var configuredLanguage: String? {
        guard store.bool(for: .transcriptionAutomaticLanguage) != true else { return nil }
        return nonEmptyString(for: .transcriptionLanguage) ?? "fr"
    }

    func storedModelPath(for model: String) -> String? {
        store.stringDictionary(for: .transcriptionStoredModelPaths)?[model]
    }

    func setStoredModelPath(_ path: String, for model: String) {
        var paths = store.stringDictionary(for: .transcriptionStoredModelPaths) ?? [:]
        paths[model] = path
        store.set(.stringDictionary(paths), for: .transcriptionStoredModelPaths)
    }

    private func nonEmptyString(for key: SettingsKey) -> String? {
        let value = store.string(for: key)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.flatMap { $0.isEmpty ? nil : $0 }
    }
}
