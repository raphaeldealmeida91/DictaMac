import AppKit
import Combine
import Foundation

@MainActor
protocol LaunchAtLoginManaging: ObservableObject where ObjectWillChangePublisher == ObservableObjectPublisher {
    var isEnabled: Bool { get }
    var statusMessage: String? { get }
    func setEnabled(_ enabled: Bool)
    func refresh()
}

@MainActor
protocol HistoryManaging: ObservableObject where ObjectWillChangePublisher == ObservableObjectPublisher {
    var entries: [TranscriptionHistoryEntry] { get }
    func clear() throws
}

@MainActor
protocol PermissionManaging: ObservableObject where ObjectWillChangePublisher == ObservableObjectPublisher {
    func status(for permission: AppPermission) -> PermissionStatus
    func request(_ permission: AppPermission) async -> PermissionStatus
    func startPeriodicRefresh()
    func stopPeriodicRefresh()
    func openSystemSettings(for permission: AppPermission)
}

@MainActor
protocol TranscriptionModelStateProviding: ObservableObject where ObjectWillChangePublisher == ObservableObjectPublisher {
    var status: String { get }
    var downloadProgress: Double? { get }
    var isBusy: Bool { get }
    var isReady: Bool { get }
}

protocol TranscriptionModelReloading: Actor {
    func reloadConfiguredModel() async throws
}

@MainActor
protocol DictationActivityProviding: ObservableObject where ObjectWillChangePublisher == ObservableObjectPublisher {
    var state: DictationState { get }
}

@MainActor
protocol LocalCleanupModelStateProviding: ObservableObject where ObjectWillChangePublisher == ObservableObjectPublisher {
    var status: String { get }
    var downloadProgress: Double? { get }
    var isBusy: Bool { get }
    var isReady: Bool { get }
    var hasError: Bool { get }
}

protocol LocalCleanupModelManaging: Actor {
    func approveDownloadAndActivate()
    func cancelDownload()
    func unload(reason: String)
}

protocol APIKeyStoring: Sendable {
    func load() throws -> String?
    func save(_ value: String) throws
}

@MainActor
protocol DictationDiagnosticsProviding: ObservableObject where ObjectWillChangePublisher == ObservableObjectPublisher {
    var lastTimings: DictationTimings? { get }
}

protocol DiagnosticLogOpening: Sendable {
    func openLogsDirectory()
}

#if DEBUG
@MainActor
protocol BenchmarkManaging: ObservableObject where ObjectWillChangePublisher == ObservableObjectPublisher {
    var isRunning: Bool { get }
    var status: String { get }
    var results: [WhisperBenchmarkResult] { get }
    func chooseWAVAndRun()
}
#endif

extension LaunchAtLoginService: LaunchAtLoginManaging {}
extension TranscriptionHistoryStore: HistoryManaging {}
extension PermissionsManager: PermissionManaging {}
extension TranscriptionModelState: TranscriptionModelStateProviding {}
extension WhisperKitTranscriptionService: TranscriptionModelReloading {}
extension AppActivityModel: DictationActivityProviding {}
extension LocalCleanupModelState: LocalCleanupModelStateProviding {}
extension LocalCleanupModelManager: LocalCleanupModelManaging {}
extension DictationDiagnostics: DictationDiagnosticsProviding {}

#if DEBUG
extension WhisperBenchmarkState: BenchmarkManaging {}
#endif

struct KeychainAPIKeyStore: APIKeyStoring {
    func load() throws -> String? {
        try TextCleanupAPIKeyStore.load()
    }

    func save(_ value: String) throws {
        try TextCleanupAPIKeyStore.save(value)
    }
}

struct SystemDiagnosticLogOpener: DiagnosticLogOpening {
    func openLogsDirectory() {
        guard let directory = try? PersistentDiagnosticLog.logsDirectoryURL() else { return }
        NSWorkspace.shared.open(directory)
    }
}
