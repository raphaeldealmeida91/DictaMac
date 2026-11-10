import AppKit

@MainActor
final class SafeModeLauncher {
    private let manager: SafeModeManager?
    private let alertPresenter: any UserAlertPresenting

    init(manager: SafeModeManager?, alertPresenter: any UserAlertPresenting) {
        self.manager = manager
        self.alertPresenter = alertPresenter
    }

    func launch() {
        guard let manager else { return }
        let abnormalExit = (try? manager.detectAbnormalExitAndMarkRunning()) ?? false
        SafeModeState.setEnabled(abnormalExit)
        guard abnormalExit else { return }

        let response = alertPresenter.present(UserAlert(
            style: .warning,
            title: "DictaMac a démarré en mode sûr",
            message: "La sortie précédente était anormale. Le nettoyage Rapide (règles), les modèles légers et l’absence de préchauffage LLM sont activés pour cette session.",
            primaryButton: "Continuer",
            secondaryButton: "Ouvrir le journal"
        ))
        if response == .secondary,
           let directory = try? PersistentDiagnosticLog.logsDirectoryURL() {
            NSWorkspace.shared.open(directory)
        }
    }

    func terminate() {
        try? manager?.markCleanExit()
    }
}
