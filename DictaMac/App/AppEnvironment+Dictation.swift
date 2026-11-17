import AppKit

extension AppEnvironment {
    static func makeCoordinator(
        settings: SettingsBundle,
        models: ModelBundle,
        emergency: EmergencyBundle,
        cleanupService: any TextCleanupService,
        activity: AppActivityModel,
        correctionLearningTracker: any DictationCorrectionTracking,
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
            permissionCache: shared.permissionCache,
            correctionLearningTracker: correctionLearningTracker
        )
        return DictationCoordinator(dependencies: DictationCoordinatorDependencies(
            hotkeyProvider: makeHotkey(settings: settings.emergency, emergency: emergency),
            audioRecorder: audioRecorder,
            overlayPresenter: DictationOverlayController(),
            feedbackSoundPlayer: SystemFeedbackSoundPlayer(settings: settings.feedback),
            contextProvider: AccessibilityDictationContextProvider(
                permissionReader: shared.permissionCache
            ),
            recordingSessionFactory: makeRecordingFactory(
                audioRecorder: audioRecorder,
                settings: settings,
                transcriptionService: models.transcriptionService,
                wordDiagnostics: models.diagnostics
            ),
            pipeline: pipeline,
            stageReporter: reporter,
            modelPreparer: makeModelPreparer(settings: settings.cleanup, models: models),
            modelReadiness: models.transcriptionState,
            cancellationRegistry: emergency.cancellationHub,
            diagnosticLog: emergency.log,
            activityModel: activity
        ))
    }

    static func makePipeline(
        cleanupService: any TextCleanupService,
        settings: StoredTextCleanupSettings,
        personalDictionary: any PersonalDictionary,
        models: ModelBundle,
        reporter: any DictationStageReporting,
        permissionCache: any AccessibilityPermissionReading,
        correctionLearningTracker: any DictationCorrectionTracking
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
            modelRecovery: recovery,
            wordDiagnostics: models.diagnostics,
            correctionTracker: correctionLearningTracker
        )
    }

    static func makeRecordingFactory(
        audioRecorder: AudioRecorder,
        settings: SettingsBundle,
        transcriptionService: WhisperKitTranscriptionService,
        wordDiagnostics: any TextWordDiagnosticsRecording
    ) -> DefaultRecordingSessionFactory {
        DefaultRecordingSessionFactory(
            audioRecorder: audioRecorder,
            transcriptionService: transcriptionService,
            transcriptionSettings: settings.transcription,
            recordingSettings: settings.recording,
            wordDiagnostics: wordDiagnostics
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
