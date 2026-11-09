import AppKit
import Dispatch
import SwiftUI

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private var dictationCoordinator: DictationCoordinator?
    private let mainThreadWatchdog = MainThreadWatchdog()
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
        TextCleanupPreferences.migrate()
        _ = PersistentDiagnosticLog.shared
        Task { await PermissionsManager.primeSharedCache() }
        ProcessMemoryDiagnostics.logFootprint(.startup)
        mainThreadWatchdog.start()
        let coordinator = DictationCoordinator()
        dictationCoordinator = coordinator
        coordinator.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        mainThreadWatchdog.stop()
        dictationCoordinator?.stop()
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
        UserDefaults.standard.set(TextCleanupEngine.fast.rawValue, forKey: TextCleanupPreferences.engineKey)

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
    #if DEBUG
    @ObservedObject private var benchmarkState = WhisperBenchmarkState.shared
    #endif

    var body: some View {
        Text("Whisper : \(transcriptionState.isReady ? "prêt" : transcriptionState.status)")
            .disabled(true)
        if TextCleanupPreferences.configuredEngine == .local {
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
