import AppKit

@MainActor
enum DictationCompositionRoot {
    static func makeCoordinator(
        textCleanupService: any TextCleanupService,
        transcriptionSettings: any TranscriptionSettings,
        textCleanupSettings: any TextCleanupSettings,
        recordingSettings: any RecordingSettings,
        feedbackSoundSettings: any FeedbackSoundSettings
    ) -> DictationCoordinator {
        let audioRecorder = AudioRecorder()
        let transcriptionService = WhisperKitTranscriptionService.shared
        let stageReporter = makeStageReporter()
        let recordingFactory = makeRecordingFactory(audioRecorder, transcriptionService, transcriptionSettings, recordingSettings)
        let pipeline = makePipeline(textCleanupService, textCleanupSettings, stageReporter)
        let modelPreparer = makeModelPreparer(transcriptionService, textCleanupSettings)
        return DictationCoordinator(
            hotkeyProvider: HotkeyService(),
            audioRecorder: audioRecorder,
            overlayPresenter: DictationOverlayController(),
            feedbackSoundPlayer: SystemFeedbackSoundPlayer(settings: feedbackSoundSettings),
            recordingSessionFactory: recordingFactory,
            pipeline: pipeline,
            stageReporter: stageReporter,
            modelPreparer: modelPreparer,
            cancellationRegistry: EmergencyCancellationHub.shared,
            frontmostApplicationName: frontmostApplicationName
        )
    }

    private static func frontmostApplicationName() -> String? {
        NSWorkspace.shared.frontmostApplication?.localizedName
    }

    private static func makeStageReporter() -> DefaultDictationStageReporter {
        DefaultDictationStageReporter(
            persistentLog: .shared,
            emergencyRuntime: .shared
        )
    }

    private static func makeRecordingFactory(
        _ audioRecorder: AudioRecorder,
        _ transcriptionService: any TranscriptionService,
        _ transcriptionSettings: any TranscriptionSettings,
        _ recordingSettings: any RecordingSettings
    ) -> DefaultRecordingSessionFactory {
        DefaultRecordingSessionFactory(
            audioRecorder: audioRecorder,
            transcriptionService: transcriptionService,
            transcriptionSettings: transcriptionSettings,
            recordingSettings: recordingSettings
        )
    }

    private static func makePipeline(
        _ cleanupService: any TextCleanupService,
        _ cleanupSettings: any TextCleanupSettings,
        _ stageReporter: any DictationStageReporting
    ) -> DictationPipeline {
        DictationPipeline(
            textCleanupService: cleanupService,
            textCleanupSettings: cleanupSettings,
            textInjector: ClipboardTextInjector(),
            historyRecorder: TranscriptionHistoryStore.shared,
            metricsRecorder: DictationDiagnostics.shared,
            stageReporter: stageReporter,
            modelRecovery: makeModelRecovery()
        )
    }

    private static func makeModelPreparer(
        _ transcriptionService: any TranscriptionService,
        _ cleanupSettings: any TextCleanupSettings
    ) -> DictationModelPreparer {
        DictationModelPreparer(
            transcriptionService: transcriptionService,
            textCleanupSettings: cleanupSettings,
            localModelManager: LocalCleanupModelManager.shared
        )
    }

    private static func makeModelRecovery() -> DefaultPipelineModelRecovery {
        DefaultPipelineModelRecovery {
            await LocalCleanupModelManager.shared.unload(reason: "Modèle déchargé après timeout")
            await WhisperKitTranscriptionService.shared.unload(reason: "Whisper déchargé après timeout")
        }
    }
}
