import Dispatch

protocol ModelUnloading: Sendable {
    func unload(reason: String) async
}

enum MemoryPressureLevel: Sendable, Equatable {
    case warning
    case critical
}

@MainActor
final class MemoryPressureMonitor {
    private let localModelUnloader: any ModelUnloading
    private let transcriptionModelUnloader: any ModelUnloading
    private let textCleanupSettings: any TextCleanupSettingsWriting
    private let alertPresenter: any UserAlertPresenting
    private let diagnosticLog: any DiagnosticLogging
    private let source: DispatchSourceMemoryPressure
    private var isRunning = false

    init(
        localModelUnloader: any ModelUnloading,
        transcriptionModelUnloader: any ModelUnloading,
        textCleanupSettings: any TextCleanupSettingsWriting,
        alertPresenter: any UserAlertPresenting,
        diagnosticLog: any DiagnosticLogging,
        source: DispatchSourceMemoryPressure = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .global(qos: .utility)
        )
    ) {
        self.localModelUnloader = localModelUnloader
        self.transcriptionModelUnloader = transcriptionModelUnloader
        self.textCleanupSettings = textCleanupSettings
        self.alertPresenter = alertPresenter
        self.diagnosticLog = diagnosticLog
        self.source = source
        source.setEventHandler { [weak self, weak source] in
            guard let pressure = source?.data else { return }
            let level: MemoryPressureLevel = pressure.contains(.critical) ? .critical : .warning
            Task { @MainActor [weak self] in await self?.handle(level) }
        }
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        source.resume()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        source.cancel()
    }

    func handle(_ level: MemoryPressureLevel) async {
        let isCritical = level == .critical
        diagnosticLog.memoryPressure(critical: isCritical)
        ProcessMemoryDiagnostics.logFootprint(
            isCritical ? .memoryPressureCritical : .memoryPressureWarning,
            diagnosticLog: diagnosticLog
        )
        await localModelUnloader.unload(reason: "Modèle local déchargé : pression mémoire")
        if isCritical {
            await transcriptionModelUnloader.unload(reason: "Whisper déchargé : pression mémoire critique")
        }
        textCleanupSettings.setEngine(.fast)
        _ = alertPresenter.present(Self.alert(for: level))
    }

    private static func alert(for level: MemoryPressureLevel) -> UserAlert {
        switch level {
        case .warning:
            UserAlert(
                style: .warning,
                title: "Mémoire disponible faible",
                message: "DictaMac a déchargé le modèle local. Le nettoyage repasse en Rapide (règles).",
                primaryButton: "OK",
                secondaryButton: nil
            )
        case .critical:
            UserAlert(
                style: .critical,
                title: "Pression mémoire critique",
                message: "DictaMac a déchargé les modèles Whisper et local. Le nettoyage repasse en Rapide (règles).",
                primaryButton: "OK",
                secondaryButton: nil
            )
        }
    }
}

extension LocalCleanupModelManager: ModelUnloading {}
extension WhisperKitTranscriptionService: ModelUnloading {}
