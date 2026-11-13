import AppKit
import Darwin
import Foundation
import OSLog

protocol EmergencyModelUnloading: Sendable {
    func requestEmergencyUnload()
}

protocol EmergencyRecovering: Sendable {
    func begin(reason: String, hotkey: Bool)
    func exit(reason: String)
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
    private let alertLock = NSLock()
    private var lastAlertAt: TimeInterval?
    private var alertIsPending = false
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
        guard reserveAlert(at: runtime.currentTime()) else { return }
        DispatchQueue.main.async { [weak self, alertPresenter] in
            guard let self else { return }
            NotificationCenter.default.post(name: .emergencyStopRequested, object: nil)
            let didPresent = alertPresenter.presentNonBlocking(UserAlert(
                style: .critical,
                title: "Arrêt d’urgence DictaMac",
                message: "La dictée a été annulée et les modèles ont été déchargés (\(reason)). Vous pouvez toujours quitter DictaMac.",
                primaryButton: "Quitter DictaMac",
                secondaryButton: "Ouvrir le journal"
            )) { [weak self] response in
                self?.releaseAlert()
                if response == .primary {
                    self?.exit(reason: "user_requested_exit")
                } else if let directory = try? PersistentDiagnosticLog.logsDirectoryURL() {
                    NSWorkspace.shared.open(directory)
                }
            }
            if !didPresent { self.releaseAlert() }
        }
    }

    func exit(reason: String) {
        diagnosticLog.emergencyExitAndFlush(reason: reason)
        DispatchQueue.main.async { NSApp.terminate(nil) }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) { _exit(0) }
    }

    private func reserveAlert(at now: TimeInterval) -> Bool {
        alertLock.withLock {
            guard !alertIsPending else { return false }
            if let lastAlertAt, now - lastAlertAt < 60 { return false }
            lastAlertAt = now
            alertIsPending = true
            return true
        }
    }

    private func releaseAlert() {
        alertLock.withLock { alertIsPending = false }
    }
}

extension LocalCleanupModelManager: EmergencyModelUnloading {}
extension WhisperKitTranscriptionService: EmergencyModelUnloading {}
