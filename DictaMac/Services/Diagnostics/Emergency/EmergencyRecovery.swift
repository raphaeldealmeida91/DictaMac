import AppKit
import Darwin
import Foundation
import OSLog

enum EmergencyRecovery {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "DictaMac",
        category: "Emergency"
    )

    static func begin(reason: String, hotkey: Bool = false) {
        logger.fault("emergency recovery reason=\(reason, privacy: .public)")
        PersistentDiagnosticLog.shared.emergencyRecovery(reason: reason)
        if hotkey {
            EmergencyRuntime.shared.armHotkeyExit(reason: reason)
        }
        EmergencyCancellationHub.shared.cancelAll()
        let audioStopped = EmergencyAudioRegistry.shared.stop(timeout: 2)
        WhisperKitTranscriptionService.shared.requestEmergencyUnload()
        LocalCleanupModelManager.shared.requestEmergencyUnload()
        if audioStopped { EmergencyRuntime.shared.setIdle(true) }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .emergencyStopRequested, object: nil)
            EmergencyAlertPresenter.show(reason: reason)
        }
    }

    static func exit(reason: String) -> Never {
        PersistentDiagnosticLog.shared.emergencyExitAndFlush(reason: reason)
        _exit(0)
    }
}

@MainActor
private enum EmergencyAlertPresenter {
    private static var isShowing = false

    static func show(reason: String) {
        guard !isShowing else { return }
        isShowing = true
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Arrêt d’urgence DictaMac"
        alert.informativeText = "La dictée a été annulée et les modèles ont été déchargés (\(reason))."
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Ouvrir le journal")
        let response = alert.runModal()
        isShowing = false
        if response == .alertSecondButtonReturn,
           let directory = try? PersistentDiagnosticLog.logsDirectoryURL() {
            NSWorkspace.shared.open(directory)
        }
    }
}
