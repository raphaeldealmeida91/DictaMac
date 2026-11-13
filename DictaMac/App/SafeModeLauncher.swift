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
            message: "La sortie précédente était anormale. Vous pouvez continuer normalement ou conserver le mode sûr, qui désactive la correction complète.",
            primaryButton: "Continuer normalement",
            secondaryButton: "Rester en mode sûr"
        ))
        if response == .primary {
            SafeModeState.setEnabled(false)
        }
    }

    func terminate() {
        try? manager?.markCleanExit()
    }
}
