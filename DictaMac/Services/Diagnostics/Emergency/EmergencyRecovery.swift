import AppKit
import Darwin
import Foundation
import OSLog

protocol EmergencyModelUnloading: Sendable {
    func requestEmergencyUnload()
}

protocol EmergencyRecovering: Sendable {
    func begin(reason: String, hotkey: Bool)
    func exit(reason: String) -> Never
}

// The instance is immutable after initialization; injected collaborators own their synchronization.
final class EmergencyRecovery: EmergencyRecovering, @unchecked Sendable {
    private let diagnosticLog: any DiagnosticLogging
    private let runtime: EmergencyRuntime
    private let cancellationHub: EmergencyCancellationHub
    private let audioRegistry: EmergencyAudioRegistry
    private let transcriptionModel: any EmergencyModelUnloading
    private let localModel: any EmergencyModelUnloading
    private let alertPresenter: any UserAlertPresenting
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "DictaMac",
        category: "Emergency"
    )

    init(
        diagnosticLog: any DiagnosticLogging,
        runtime: EmergencyRuntime,
        cancellationHub: EmergencyCancellationHub,
        audioRegistry: EmergencyAudioRegistry,
        transcriptionModel: any EmergencyModelUnloading,
        localModel: any EmergencyModelUnloading,
        alertPresenter: any UserAlertPresenting
    ) {
        self.diagnosticLog = diagnosticLog
        self.runtime = runtime
        self.cancellationHub = cancellationHub
        self.audioRegistry = audioRegistry
        self.transcriptionModel = transcriptionModel
        self.localModel = localModel
        self.alertPresenter = alertPresenter
    }

    func begin(reason: String, hotkey: Bool = false) {
        logger.fault("emergency recovery reason=\(reason, privacy: .public)")
        diagnosticLog.emergencyRecovery(reason: reason)
        if hotkey { runtime.armHotkeyExit(reason: reason) }
        cancellationHub.cancelAll()
        let audioStopped = audioRegistry.stop(timeout: 2)
        transcriptionModel.requestEmergencyUnload()
        localModel.requestEmergencyUnload()
        if audioStopped { runtime.setIdle(true) }
        DispatchQueue.main.async { [alertPresenter] in
            NotificationCenter.default.post(name: .emergencyStopRequested, object: nil)
            let response = alertPresenter.present(UserAlert(
                style: .critical,
                title: "Arrêt d’urgence DictaMac",
                message: "La dictée a été annulée et les modèles ont été déchargés (\(reason)).",
                primaryButton: "OK",
                secondaryButton: "Ouvrir le journal"
            ))
            if response == .secondary,
               let directory = try? PersistentDiagnosticLog.logsDirectoryURL() {
                NSWorkspace.shared.open(directory)
            }
        }
    }

    func exit(reason: String) -> Never {
        diagnosticLog.emergencyExitAndFlush(reason: reason)
        _exit(0)
    }
}

extension LocalCleanupModelManager: EmergencyModelUnloading {}
extension WhisperKitTranscriptionService: EmergencyModelUnloading {}
