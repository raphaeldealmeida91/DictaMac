import Foundation

struct StoredTextCleanupSettings: TextCleanupSettings, TextCleanupSettingsWriting {
    static let defaultModel = "gpt-4.1-mini"
    static let defaultLocalModel = "mlx-community/Qwen2.5-3B-Instruct-4bit"
    static let lightLocalModel = "mlx-community/Qwen2.5-1.5B-Instruct-4bit"
    static let qualityLocalModel = "mlx-community/Qwen2.5-7B-Instruct-4bit"
    static let defaultLocalTimeout = 8.0
    static let defaultCloudTimeout = 8.0

    private let store: any SettingsStoring
    private let physicalMemory: @Sendable () -> UInt64

    init(
        store: any SettingsStoring = UserDefaultsSettingsStore(),
        physicalMemory: @escaping @Sendable () -> UInt64 = { ProcessInfo.processInfo.physicalMemory }
    ) {
        self.store = store
        self.physicalMemory = physicalMemory
    }

    var configuredEngine: TextCleanupEngine {
        if SafeModeState.isEnabled { return .fast }
        migrate()
        return store.string(for: .textCleanupEngine).flatMap(TextCleanupEngine.init(rawValue:)) ?? .fast
    }

    var isEnabled: Bool { configuredEngine != .disabled }
    var configuredModel: String { nonEmptyString(for: .textCleanupModel) ?? Self.defaultModel }

    var cleanupStyle: CleanupStyle {
        store.string(for: .textCleanupStyle).flatMap(CleanupStyle.init(rawValue:)) ?? .polished
    }

    var configuredLocalModel: String {
        if SafeModeState.isEnabled { return Self.lightLocalModel }
        return nonEmptyString(for: .textCleanupLocalModel) ?? recommendedLocalModel
    }

    var removeIsolatedGenre: Bool {
        store.bool(for: .textCleanupRemoveIsolatedGenre) ?? true
    }

    var localTimeout: TimeInterval {
        let value = store.double(for: .textCleanupLocalTimeout) ?? 0
        return value > 0 ? value : Self.defaultLocalTimeout
    }

    var cloudTimeout: TimeInterval {
        let value = store.double(for: .textCleanupCloudTimeout) ?? 0
        return value > 0 ? value : Self.defaultCloudTimeout
    }

    var localDownloadApproved: Bool {
        store.bool(for: .textCleanupLocalDownloadApproved) ?? false
    }

    var recommendedLocalModel: String {
        physicalMemory() < StoredTranscriptionSettings.lowMemoryThreshold
            ? Self.lightLocalModel
            : Self.defaultLocalModel
    }

    func migrate() {
        guard store.string(for: .textCleanupEngine) == nil else { return }
        let engine: TextCleanupEngine
        if let wasEnabled = store.bool(for: .legacyTextCleanupEnabled) {
            engine = wasEnabled ? .cloud : .disabled
        } else {
            engine = .fast
        }
        store.set(.string(engine.rawValue), for: .textCleanupEngine)
    }

    func approveLocalDownload() {
        store.set(.bool(true), for: .textCleanupLocalDownloadApproved)
    }

    func setEngine(_ engine: TextCleanupEngine) {
        store.set(.string(engine.rawValue), for: .textCleanupEngine)
    }

    private func nonEmptyString(for key: SettingsKey) -> String? {
        let value = store.string(for: key)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.flatMap { $0.isEmpty ? nil : $0 }
    }
}
