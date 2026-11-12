import AppKit

extension AppEnvironment {
    static func makeCoordinator(
        settings: SettingsBundle,
        models: ModelBundle,
        emergency: EmergencyBundle,
        cleanupService: any TextCleanupService,
        activity: AppActivityModel,
        shared: SharedServices
    ) -> DictationCoordinator {
        let audioRecorder = AudioRecorder(
            emergencyAudioRegistry: emergency.audioRegistry,
            diagnosticLog: emergency.log
        )
        let reporter = DefaultDictationStageReporter(
            persistentLog: emergency.log,
            emergencyRuntime: emergency.runtime
        )
        let pipeline = makePipeline(
            cleanupService: cleanupService,
            settings: settings.cleanup,
            personalDictionary: settings.dictionary,
            models: models,
            reporter: reporter,
            permissionCache: shared.permissionCache
        )
        return DictationCoordinator(dependencies: DictationCoordinatorDependencies(
            hotkeyProvider: makeHotkey(settings: settings.emergency, emergency: emergency),
            audioRecorder: audioRecorder,
            overlayPresenter: DictationOverlayController(),
            feedbackSoundPlayer: SystemFeedbackSoundPlayer(settings: settings.feedback),
            recordingSessionFactory: makeRecordingFactory(
                audioRecorder: audioRecorder,
                settings: settings,
                transcriptionService: models.transcriptionService
            ),
            pipeline: pipeline,
            stageReporter: reporter,
            modelPreparer: makeModelPreparer(settings: settings.cleanup, models: models),
            modelReadiness: models.transcriptionState,
            cancellationRegistry: emergency.cancellationHub,
            diagnosticLog: emergency.log,
            activityModel: activity,
            frontmostApplicationName: { NSWorkspace.shared.frontmostApplication?.localizedName }
        ))
    }

    static func makePipeline(
        cleanupService: any TextCleanupService,
        settings: StoredTextCleanupSettings,
        personalDictionary: any PersonalDictionary,
        models: ModelBundle,
        reporter: any DictationStageReporting,
        permissionCache: any AccessibilityPermissionReading
    ) -> DictationPipeline {
        let recovery = DefaultPipelineModelRecovery {
            await models.localManager.unload(reason: "Modèle déchargé après timeout")
            await models.transcriptionService.unload(reason: "Whisper déchargé après timeout")
        }
        return DictationPipeline(
            textCleanupService: cleanupService,
            textCleanupSettings: settings,
            personalDictionary: personalDictionary,
            textInjector: ClipboardTextInjector(permissionCache: permissionCache),
            historyRecorder: models.history,
            metricsRecorder: models.diagnostics,
            stageReporter: reporter,
            modelRecovery: recovery
        )
    }

    static func makeRecordingFactory(
        audioRecorder: AudioRecorder,
        settings: SettingsBundle,
        transcriptionService: WhisperKitTranscriptionService
    ) -> DefaultRecordingSessionFactory {
        DefaultRecordingSessionFactory(
            audioRecorder: audioRecorder,
            transcriptionService: transcriptionService,
            transcriptionSettings: settings.transcription,
            recordingSettings: settings.recording
        )
    }

    static func makeModelPreparer(
        settings: StoredTextCleanupSettings,
        models: ModelBundle
    ) -> DictationModelPreparer {
        DictationModelPreparer(
            transcriptionService: models.transcriptionService,
            textCleanupSettings: settings,
            localModelManager: models.localManager
        )
    }

    static func makeHotkey(
        settings: StoredEmergencyHotkeySettings,
        emergency: EmergencyBundle
    ) -> HotkeyService {
        HotkeyService(
            emergencySettings: settings,
            emergencyRuntime: emergency.runtime,
            emergencyRecovery: emergency.recovery,
            diagnosticLog: emergency.log
        )
    }
}
