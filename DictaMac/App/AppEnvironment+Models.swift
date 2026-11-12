extension AppEnvironment {
    struct ModelBundle {
        let transcriptionState: TranscriptionModelState
        let cleanupState: LocalCleanupModelState
        let history: TranscriptionHistoryStore
        let diagnostics: DictationDiagnostics
        let localManager: LocalCleanupModelManager
        let transcriptionService: WhisperKitTranscriptionService
    }

    static func makeModels(settings: SettingsBundle, shared: SharedServices) -> ModelBundle {
        let transcriptionState = TranscriptionModelState()
        let cleanupState = LocalCleanupModelState()
        let localManager = LocalCleanupModelManager(
            settings: settings.cleanup,
            modelState: cleanupState,
            modelLoadingGate: shared.modelLoadingGate,
            diagnosticLog: shared.diagnosticLog
        )
        let transcriptionService = WhisperKitTranscriptionService(
            settings: settings.transcription,
            modelPathStore: settings.transcription,
            personalDictionary: settings.dictionary,
            modelState: transcriptionState,
            modelLoadingGate: shared.modelLoadingGate,
            diagnosticLog: shared.diagnosticLog
        )
        return ModelBundle(
            transcriptionState: transcriptionState,
            cleanupState: cleanupState,
            history: TranscriptionHistoryStore(settings: settings.history),
            diagnostics: DictationDiagnostics(),
            localManager: localManager,
            transcriptionService: transcriptionService
        )
    }
}
