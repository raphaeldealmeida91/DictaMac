import AppKit
import Dispatch
import SwiftUI

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private var dictationCoordinator: DictationCoordinator?
    private let transcriptionSettings = StoredTranscriptionSettings()
    private let textCleanupSettings = StoredTextCleanupSettings()
    private let recordingSettings = StoredRecordingSettings()
    private let feedbackSoundSettings = StoredFeedbackSoundSettings()
    private let emergencyWatchdog = EmergencyWatchdog()
    private var heartbeatTimer: Timer?
    private var safeModeManager: SafeModeManager?
    private let memoryPressureSource = DispatchSource.makeMemoryPressureSource(
        eventMask: [.warning, .critical], queue: .global(qos: .utility)
    )

    override init() {
        super.init()
        memoryPressureSource.setEventHandler { [weak self] in
            guard let self else { return }
            let pressure = self.memoryPressureSource.data
            Task { @MainActor [weak self] in
                await self?.handleMemoryPressure(pressure)
            }
        }
        memoryPressureSource.resume()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        textCleanupSettings.migrate()
        _ = PersistentDiagnosticLog.shared
        configureSafeMode()
        Task { await PermissionsManager.primeSharedCache() }
        ProcessMemoryDiagnostics.logFootprint(.startup)
        startMainThreadHeartbeat()
        emergencyWatchdog.start()
        guard let cleanupEndpoint = URL(string: "https://api.openai.com/v1/responses") else { return }
        let registry = TextCleanupEngineRegistry(services: [
            .disabled: PassthroughTextCleanupService(),
            .fast: FastRulesTextCleanupService(settings: textCleanupSettings),
            .local: LocalTextCleanupService(
                generator: LocalCleanupModelManager.shared,
                settings: textCleanupSettings
            ),
            .cloud: CloudTextCleanupService(
                endpoint: cleanupEndpoint,
                settings: textCleanupSettings
            )
        ])
        let cleanupService = ConfiguredTextCleanupService(
            settings: textCleanupSettings,
            registry: registry
        )
        let coordinator = DictationCompositionRoot.makeCoordinator(
            textCleanupService: cleanupService,
            transcriptionSettings: transcriptionSettings,
            textCleanupSettings: textCleanupSettings,
            recordingSettings: recordingSettings,
            feedbackSoundSettings: feedbackSoundSettings
        )
        dictationCoordinator = coordinator
        coordinator.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        emergencyWatchdog.stop()
        dictationCoordinator?.stop()
        try? safeModeManager?.markCleanExit()
    }

    private func startMainThreadHeartbeat() {
        EmergencyRuntime.shared.heartbeat()
        let timer = Timer(timeInterval: 0.5, repeats: true) { _ in
            EmergencyRuntime.shared.heartbeat()
        }
        RunLoop.main.add(timer, forMode: .common)
        heartbeatTimer = timer
    }

    private func configureSafeMode() {
        guard let manager = try? SafeModeManager.live() else { return }
        safeModeManager = manager
        let abnormalExit = (try? manager.detectAbnormalExitAndMarkRunning()) ?? false
        SafeModeState.setEnabled(abnormalExit)
        guard abnormalExit else { return }

        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "DictaMac a démarré en mode sûr"
            alert.informativeText = "La sortie précédente était anormale. Le nettoyage Rapide (règles), les modèles légers et l’absence de préchauffage LLM sont activés pour cette session."
            alert.addButton(withTitle: "Continuer")
            alert.addButton(withTitle: "Ouvrir le journal")
            if alert.runModal() == .alertSecondButtonReturn,
               let directory = try? PersistentDiagnosticLog.logsDirectoryURL() {
                NSWorkspace.shared.open(directory)
            }
        }
    }

    private func handleMemoryPressure(_ pressure: DispatchSource.MemoryPressureEvent) async {
        let critical = pressure.contains(.critical)
        PersistentDiagnosticLog.shared.memoryPressure(critical: critical)
        ProcessMemoryDiagnostics.logFootprint(
            critical ? .memoryPressureCritical : .memoryPressureWarning
        )
        await LocalCleanupModelManager.shared.unload(reason: "Modèle local déchargé : pression mémoire")
        if critical {
            await WhisperKitTranscriptionService.shared.unload(
                reason: "Whisper déchargé : pression mémoire critique"
            )
        }
        textCleanupSettings.setEngine(.fast)

        let alert = NSAlert()
        alert.alertStyle = critical ? .critical : .warning
        alert.messageText = critical ? "Pression mémoire critique" : "Mémoire disponible faible"
        alert.informativeText = critical
            ? "DictaMac a déchargé les modèles Whisper et local. Le nettoyage repasse en Rapide (règles)."
            : "DictaMac a déchargé le modèle local. Le nettoyage repasse en Rapide (règles)."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

@main
struct DictaMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent()
        } label: {
            Image(systemName: "mic")
        }

        Settings {
            SettingsView()
        }
    }
}

private struct MenuBarContent: View {
    @ObservedObject private var transcriptionState = TranscriptionModelState.shared
    @ObservedObject private var cleanupState = LocalCleanupModelState.shared
    @ObservedObject private var history = TranscriptionHistoryStore.shared
    private let textCleanupSettings: any TextCleanupSettings = StoredTextCleanupSettings()
    #if DEBUG
    @ObservedObject private var benchmarkState = WhisperBenchmarkState.shared
    #endif

    var body: some View {
        Text("Whisper : \(transcriptionState.isReady ? "prêt" : transcriptionState.status)")
            .disabled(true)
        if textCleanupSettings.configuredEngine == .local {
            Text("LLM local : \(cleanupState.isReady ? "prêt" : cleanupState.status)")
                .disabled(true)
        }

        Divider()

        Menu("Dernières dictées") {
            if history.entries.isEmpty {
                Text("Aucune dictée")
            } else {
                ForEach(history.entries) { entry in
                    Button {
                        history.copyToPasteboard(entry)
                    } label: {
                        Text(menuTitle(for: entry))
                    }
                }
            }
        }

        Divider()

        SettingsLink { Text("Réglages…") }

        #if DEBUG
        Divider()
        Button("Benchmark Whisper (WAV)…") {
            WhisperBenchmarkState.shared.chooseWAVAndRun()
        }
        .disabled(benchmarkState.isRunning)
        #endif

        Divider()
        Button("Quitter") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func menuTitle(for entry: TranscriptionHistoryEntry) -> String {
        let oneLine = entry.text.replacingOccurrences(of: "\n", with: " ")
        let excerpt = oneLine.count > 52 ? String(oneLine.prefix(49)) + "…" : oneLine
        let date = entry.date.formatted(date: .omitted, time: .shortened)
        return "\(date) · \(entry.targetApplication) — \(excerpt)"
    }
}
