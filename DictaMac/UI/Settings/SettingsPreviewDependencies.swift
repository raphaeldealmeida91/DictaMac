import Combine
import Foundation

@MainActor
final class PreviewLaunchAtLoginManager: LaunchAtLoginManaging {
    @Published var isEnabled = true
    @Published var statusMessage: String?

    func setEnabled(_ enabled: Bool) { isEnabled = enabled }
    func refresh() {}
}

@MainActor
final class PreviewHistoryManager: HistoryManaging {
    @Published var entries: [TranscriptionHistoryEntry] = []
    func clear() throws { entries = [] }
}

@MainActor
final class PreviewPermissionManager: PermissionManaging {
    @Published private var revision = false
    private let store: any SettingsStoring
    private var statuses: [AppPermission: PermissionStatus] = [
        .microphone: .authorized,
        .inputMonitoring: .denied,
        .accessibility: .authorized
    ]

    init(store: any SettingsStoring) {
        self.store = store
    }

    func status(for permission: AppPermission) -> PermissionStatus {
        statuses[permission] ?? .denied
    }

    func request(_ permission: AppPermission) async -> PermissionStatus {
        statuses[permission] = .authorized
        revision.toggle()
        return .authorized
    }

    func startPeriodicRefresh() {}
    func stopPeriodicRefresh() {}
    func openSystemSettings(for permission: AppPermission) {}
}

@MainActor
final class PreviewTranscriptionModelState: TranscriptionModelStateProviding {
    @Published var status = "Modèle prêt"
    @Published var downloadProgress: Double?
    @Published var isBusy = false
    @Published var isReady = true
}

actor PreviewTranscriptionModelLoader: TranscriptionModelReloading {
    func reloadConfiguredModel() async throws {}
}

@MainActor
final class PreviewCleanupModelState: LocalCleanupModelStateProviding {
    @Published var status = "Modèle prêt"
    @Published var downloadProgress: Double?
    @Published var isBusy = false
    @Published var isReady = true
    @Published var hasError = false
}

actor PreviewCleanupModelManager: LocalCleanupModelManaging {
    func approveDownloadAndActivate() {}
    func cancelDownload() {}
    func unload(reason: String) {}
}

struct PreviewAPIKeyStore: APIKeyStoring {
    func load() throws -> String? { nil }
    func save(_ value: String) throws {}
}

final class PreviewPersonalDictionary: PersonalDictionary, @unchecked Sendable {
    private var storedEntries = DictionaryEntry.defaults

    func entries() -> [DictionaryEntry] { storedEntries }
    func replaceEntries(_ entries: [DictionaryEntry]) throws { storedEntries = entries }
    func addCanonicalTerm(_ canonical: String) throws -> Bool {
        storedEntries.append(DictionaryEntry(canonical: canonical, variants: []))
        return true
    }
}

@MainActor
struct PreviewDictionaryFileManager: DictionaryFileManaging {
    func importEntries() throws -> [DictionaryEntry]? { nil }
    func export(_ entries: [DictionaryEntry]) throws -> Bool { false }
}

@MainActor
final class PreviewDiagnostics: DictationDiagnosticsProviding {
    @Published var lastTimings: DictationTimings?
    @Published var lastWordDiagnostics: TextWordDiagnostics?
    private let store: any SettingsStoring

    init(store: any SettingsStoring, lastTimings: DictationTimings? = nil) {
        self.store = store
        self.lastTimings = lastTimings
        lastWordDiagnostics = nil
    }
}

struct PreviewDiagnosticLogOpener: DiagnosticLogOpening {
    func openLogsDirectory() {}
}

extension DictationTimings {
    static let preview = DictationTimings(
        date: Date(),
        stopAudio: 0.08,
        transcription: 0.74,
        cleanup: 0.12,
        injection: 0.05,
        total: 0.99,
        cleanupEngine: .fast
    )
}

#if DEBUG
@MainActor
final class PreviewBenchmarkManager: BenchmarkManaging {
    @Published var isRunning = false
    @Published var status = "Aucun benchmark lancé"
    @Published var results: [WhisperBenchmarkResult] = []
    func chooseWAVAndRun() {}
}
#endif
