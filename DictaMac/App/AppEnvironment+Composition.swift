import Foundation

extension AppEnvironment {
    struct SettingsBundle {
        let transcription: StoredTranscriptionSettings
        let cleanup: StoredTextCleanupSettings
        let recording: StoredRecordingSettings
        let feedback: StoredFeedbackSoundSettings
        let emergency: StoredEmergencyHotkeySettings
        let history: StoredHistorySettings

        init(store: any SettingsStoring) {
            transcription = StoredTranscriptionSettings(store: store)
            cleanup = StoredTextCleanupSettings(store: store)
            recording = StoredRecordingSettings(store: store)
            feedback = StoredFeedbackSoundSettings(store: store)
            emergency = StoredEmergencyHotkeySettings(store: store)
            history = StoredHistorySettings(store: store)
        }
    }

    struct Composition {
        let settingsStore: any SettingsStoring
        let apiKeyStore: any APIKeyStoring
        let diagnosticLogOpener: any DiagnosticLogOpening
        let settings: SettingsBundle
        let models: ModelBundle
        let emergency: EmergencyBundle
        let lifecycle: LifecycleBundle
        let coordinator: DictationCoordinator
        let activity: AppActivityModel
        let permissions: PermissionsManager
        let launchAtLogin: LaunchAtLoginService
        #if DEBUG
        let benchmarkState: WhisperBenchmarkState
        #endif

        @MainActor
        init(
            settingsStore: any SettingsStoring,
            apiKeyStore: any APIKeyStoring,
            diagnosticLogOpener: any DiagnosticLogOpening,
            settings: SettingsBundle,
            models: ModelBundle,
            emergency: EmergencyBundle,
            lifecycle: LifecycleBundle,
            coordinator: DictationCoordinator,
            activity: AppActivityModel
        ) {
            self.settingsStore = settingsStore
            self.apiKeyStore = apiKeyStore
            self.diagnosticLogOpener = diagnosticLogOpener
            self.settings = settings
            self.models = models
            self.emergency = emergency
            self.lifecycle = lifecycle
            self.coordinator = coordinator
            self.activity = activity
            permissions = PermissionsManager()
            launchAtLogin = LaunchAtLoginService()
            #if DEBUG
            benchmarkState = WhisperBenchmarkState(
                runner: WhisperBenchmarkRunner(settings: settings.transcription)
            )
            #endif
        }
    }

    static func compose() -> Composition {
        let settingsStore = UserDefaultsSettingsStore()
        let settings = SettingsBundle(store: settingsStore)
        let models = makeModels(settings: settings)
        let emergency = makeEmergency(models: models)
        let lifecycle = makeLifecycle(settings: settings, models: models, emergency: emergency)
        let cleanup = makeCleanupService(settings: settings.cleanup, manager: models.localManager)
        let activity = AppActivityModel()
        let coordinator = makeCoordinator(
            settings: settings,
            models: models,
            emergency: emergency,
            cleanupService: cleanup,
            activity: activity
        )
        return Composition(
            settingsStore: settingsStore,
            apiKeyStore: KeychainAPIKeyStore(),
            diagnosticLogOpener: SystemDiagnosticLogOpener(),
            settings: settings,
            models: models,
            emergency: emergency,
            lifecycle: lifecycle,
            coordinator: coordinator,
            activity: activity
        )
    }
}
