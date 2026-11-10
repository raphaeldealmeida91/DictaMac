extension AppEnvironment {
    struct EmergencyBundle {
        let log: PersistentDiagnosticLog
        let runtime: EmergencyRuntime
        let alerts: NSAlertPresenter
        let cancellationHub: EmergencyCancellationHub
        let audioRegistry: EmergencyAudioRegistry
        let recovery: EmergencyRecovery
        let watchdog: EmergencyWatchdog
    }

    static func makeEmergency(models: ModelBundle) -> EmergencyBundle {
        let log = PersistentDiagnosticLog.shared
        let runtime = EmergencyRuntime()
        let alerts = NSAlertPresenter()
        let cancellationHub = EmergencyCancellationHub()
        let audioRegistry = EmergencyAudioRegistry()
        let recovery = EmergencyRecovery(
            diagnosticLog: log,
            runtime: runtime,
            cancellationHub: cancellationHub,
            audioRegistry: audioRegistry,
            transcriptionModel: models.transcriptionService,
            localModel: models.localManager,
            alertPresenter: alerts
        )
        return EmergencyBundle(
            log: log,
            runtime: runtime,
            alerts: alerts,
            cancellationHub: cancellationHub,
            audioRegistry: audioRegistry,
            recovery: recovery,
            watchdog: EmergencyWatchdog(runtime: runtime, recovery: recovery)
        )
    }
}
