import AppKit
import Foundation

@MainActor
final class AppEnvironment {
    let settingsStore: any SettingsStoring
    let apiKeyStore: any APIKeyStoring
    let diagnosticLogOpener: any DiagnosticLogOpening
    let activity: AppActivityModel
    let transcriptionState: TranscriptionModelState
    let cleanupModelState: LocalCleanupModelState
    let history: TranscriptionHistoryStore
    let diagnostics: DictationDiagnostics
    let permissions: PermissionsManager
    let launchAtLogin: LaunchAtLoginService
    let transcriptionSettings: StoredTranscriptionSettings
    let textCleanupSettings: StoredTextCleanupSettings
    let localModelManager: LocalCleanupModelManager
    let transcriptionService: WhisperKitTranscriptionService
    #if DEBUG
    let benchmarkState: WhisperBenchmarkState
    #endif

    private let coordinator: DictationCoordinator
    private let memoryPressureMonitor: MemoryPressureMonitor
    private let safeModeLauncher: SafeModeLauncher
    private let heartbeat: MainThreadHeartbeat
    private let emergencyWatchdog: EmergencyWatchdog

    init() {
        let composition = Self.compose()
        settingsStore = composition.settingsStore
        apiKeyStore = composition.apiKeyStore
        diagnosticLogOpener = composition.diagnosticLogOpener
        activity = composition.activity
        transcriptionState = composition.models.transcriptionState
        cleanupModelState = composition.models.cleanupState
        history = composition.models.history
        diagnostics = composition.models.diagnostics
        permissions = composition.permissions
        launchAtLogin = composition.launchAtLogin
        transcriptionSettings = composition.settings.transcription
        textCleanupSettings = composition.settings.cleanup
        localModelManager = composition.models.localManager
        transcriptionService = composition.models.transcriptionService
        coordinator = composition.coordinator
        memoryPressureMonitor = composition.lifecycle.memoryMonitor
        safeModeLauncher = composition.lifecycle.safeModeLauncher
        heartbeat = composition.lifecycle.heartbeat
        emergencyWatchdog = composition.emergency.watchdog
        #if DEBUG
        benchmarkState = composition.benchmarkState
        #endif
    }

    func start() {
        textCleanupSettings.migrate()
        safeModeLauncher.launch()
        Task { await PermissionsManager.primeSharedCache() }
        ProcessMemoryDiagnostics.logFootprint(.startup)
        heartbeat.start()
        emergencyWatchdog.start()
        memoryPressureMonitor.start()
        coordinator.start()
    }

    func stop() {
        memoryPressureMonitor.stop()
        heartbeat.stop()
        emergencyWatchdog.stop()
        coordinator.stop()
        safeModeLauncher.terminate()
    }
}
