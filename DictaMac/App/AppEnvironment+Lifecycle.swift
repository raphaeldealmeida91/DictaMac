extension AppEnvironment {
    struct LifecycleBundle {
        let memoryMonitor: MemoryPressureMonitor
        let safeModeLauncher: SafeModeLauncher
        let heartbeat: MainThreadHeartbeat
    }

    static func makeLifecycle(
        settings: SettingsBundle,
        models: ModelBundle,
        emergency: EmergencyBundle
    ) -> LifecycleBundle {
        let memoryMonitor = MemoryPressureMonitor(
            localModelUnloader: models.localManager,
            transcriptionModelUnloader: models.transcriptionService,
            textCleanupSettings: settings.cleanup,
            alertPresenter: emergency.alerts,
            diagnosticLog: emergency.log
        )
        return LifecycleBundle(
            memoryMonitor: memoryMonitor,
            safeModeLauncher: SafeModeLauncher(
                manager: try? SafeModeManager.live(),
                alertPresenter: emergency.alerts
            ),
            heartbeat: MainThreadHeartbeat(runtime: emergency.runtime)
        )
    }
}
