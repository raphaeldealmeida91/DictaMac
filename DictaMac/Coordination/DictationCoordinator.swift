import Foundation
import OSLog
import AppKit

enum DictationState: Sendable, Equatable {
    case idle
    case recording
    case transcribing
    case injecting
}

@MainActor
protocol DictationCoordinating: AnyObject {
    var state: DictationState { get }
}

@MainActor
final class DictationCoordinator: DictationCoordinating {
    var state: DictationState { sessionPolicy.state }

    private let hotkeyService: HotkeyService
    private let audioRecorder: AudioRecorder
    private let transcriptionService: any TranscriptionService
    private let textCleanupService: any TextCleanupService
    private let textInjector: any TextInjector
    private let overlayController: DictationOverlayController
    private let transcriptionSettings: any TranscriptionSettings
    private let textCleanupSettings: any TextCleanupSettings
    private let recordingSettings: any RecordingSettings
    private let feedbackSoundSettings: any FeedbackSoundSettings
    private var transcriptionTask: Task<Void, Never>?
    private var modelPreparationTask: Task<Void, Never>?
    private var audioFeedTask: Task<Void, Never>?
    private var maximumDurationTask: Task<Void, Never>?
    private var activeSegmentedTranscriber: SegmentedTranscriber?
    private var emergencyObserver: NSObjectProtocol?
    private var sessionPolicy = DictationSessionPolicy()
    private var activeGeneration: Int?
    private var targetApplication = "Application inconnue"
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "DictaMac",
        category: "Dictation"
    )

    init(
        hotkeyService: HotkeyService = HotkeyService(),
        audioRecorder: AudioRecorder = AudioRecorder(),
        transcriptionService: any TranscriptionService = WhisperKitTranscriptionService.shared,
        textCleanupService: any TextCleanupService,
        textInjector: any TextInjector = ClipboardTextInjector(),
        overlayController: DictationOverlayController = DictationOverlayController(),
        transcriptionSettings: any TranscriptionSettings = StoredTranscriptionSettings(),
        textCleanupSettings: any TextCleanupSettings = StoredTextCleanupSettings(),
        recordingSettings: any RecordingSettings = StoredRecordingSettings(),
        feedbackSoundSettings: any FeedbackSoundSettings = StoredFeedbackSoundSettings()
    ) {
        self.hotkeyService = hotkeyService
        self.audioRecorder = audioRecorder
        self.transcriptionService = transcriptionService
        self.textCleanupService = textCleanupService
        self.textInjector = textInjector
        self.overlayController = overlayController
        self.transcriptionSettings = transcriptionSettings
        self.textCleanupSettings = textCleanupSettings
        self.recordingSettings = recordingSettings
        self.feedbackSoundSettings = feedbackSoundSettings

        hotkeyService.onPress = { [weak self] in self?.beginRecording() }
        hotkeyService.onRelease = { [weak self] in self?.endRecording() }
        hotkeyService.onCancel = { [weak self] in self?.cancelDictation() }
        audioRecorder.onLevelUpdate = { [weak overlayController] rms in
            overlayController?.updateLevel(rms)
        }
        audioRecorder.onError = { [weak self] error in
            self?.handleAudioRecorderError(error)
        }
        emergencyObserver = NotificationCenter.default.addObserver(
            forName: .emergencyStopRequested,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.cancelDictation()
            }
        }
    }

    func start() {
        hotkeyService.start()
        modelPreparationTask = Task.detached(priority: .utility) {
            [transcriptionService, textCleanupSettings, logger] in
            do {
                try await transcriptionService.prepare()
                logger.info("Modèle de transcription prêt")
                guard textCleanupSettings.configuredEngine == .local,
                      textCleanupSettings.localDownloadApproved else {
                    return
                }
                // Let Core ML release temporary compilation/loading buffers before
                // MLX starts allocating its own GPU working set.
                try await ContinuousClock().sleep(for: .seconds(1))
                await LocalCleanupModelManager.shared.activateConfiguredModel()
            } catch {
                logger.error("Préparation du modèle impossible: \(error.localizedDescription, privacy: .public)")
            }
        }
        refreshEmergencyCancellationHandlers()
    }

    func stop() {
        hotkeyService.stop()
        modelPreparationTask?.cancel()
        modelPreparationTask = nil
        audioFeedTask?.cancel()
        audioFeedTask = nil
        maximumDurationTask?.cancel()
        maximumDurationTask = nil
        transcriptionTask?.cancel()
        if let activeSegmentedTranscriber {
            Task { await activeSegmentedTranscriber.cancel() }
            self.activeSegmentedTranscriber = nil
        }
        if state == .recording {
            _ = audioRecorder.stop()
        }
        _ = sessionPolicy.cancel()
        EmergencyRuntime.shared.setIdle(true)
        activeGeneration = nil
        overlayController.hide()
        refreshEmergencyCancellationHandlers()
    }

    private func beginRecording() {
        guard state == .idle else { return }
        PersistentDiagnosticLog.shared.stage(.recording, phase: "begin")
        ProcessMemoryDiagnostics.logFootprint(.dictationStarted)

        do {
            try audioRecorder.start()
            guard let generation = sessionPolicy.beginRecording() else {
                _ = audioRecorder.stop()
                return
            }
            activeGeneration = generation
            EmergencyRuntime.shared.setIdle(false)
            targetApplication = NSWorkspace.shared.frontmostApplication?.localizedName
                ?? "Application inconnue"
            overlayController.showRecording()
            let segmentedTranscriber = SegmentedTranscriber(
                transcriptionService: transcriptionService,
                language: transcriptionSettings.configuredLanguage
            )
            activeSegmentedTranscriber = segmentedTranscriber
            audioFeedTask = Task { [weak self, audioRecorder, logger] in
                var deliveredSampleCount = 0
                do {
                    while !Task.isCancelled {
                        try await ContinuousClock().sleep(for: .milliseconds(50))
                        guard let self, self.state == .recording else { return }
                        let samples = audioRecorder.capturedSamples(since: deliveredSampleCount)
                        deliveredSampleCount += samples.count
                        await segmentedTranscriber.append(samples)
                    }
                } catch is CancellationError {
                    // Normal when fn is released or dictation is stopped.
                } catch {
                    logger.warning(
                        "Alimentation de la transcription incrémentale interrompue: \(error.localizedDescription, privacy: .public)"
                    )
                }
            }
            maximumDurationTask = Task { [weak self, recordingSettings] in
                do {
                    try await Task.sleep(for: .seconds(recordingSettings.maximumDuration))
                    guard !Task.isCancelled else { return }
                    self?.cancelForMaximumDuration()
                } catch is CancellationError {
                    // Normal when Fn is released or the dictation is cancelled.
                } catch {
                    // Task.sleep has no other expected failure.
                }
            }
            refreshEmergencyCancellationHandlers()
            playFeedbackSound(named: "Tink")
        } catch {
            PersistentDiagnosticLog.shared.stage(.recording, phase: "error")
            logger.error("Démarrage de l’enregistrement impossible: \(error.localizedDescription, privacy: .public)")
            overlayController.showError(error.localizedDescription)
        }
    }

    private func endRecording(reason: DictationSessionPolicy.StopReason = .released) {
        guard state == .recording, let generation = activeGeneration else { return }

        let releaseInstant = ContinuousClock.now
        maximumDurationTask?.cancel()
        maximumDurationTask = nil
        audioFeedTask?.cancel()
        audioFeedTask = nil
        let samples = audioRecorder.stop()
        guard let segmentedTranscriber = activeSegmentedTranscriber else {
            logger.error("Session de transcription incrémentale absente")
            sessionPolicy.complete(generation: generation)
            activeGeneration = nil
            overlayController.hide()
            return
        }
        activeSegmentedTranscriber = nil
        let stopAudioSeconds = Self.seconds(releaseInstant.duration(to: .now))
        playFeedbackSound(named: "Pop")
        let duration = audioRecorder.lastRecordingDuration
        let estimatedSegments = max(1, Int(ceil(duration / 4)))
        PersistentDiagnosticLog.shared.stage(
            .recording,
            phase: "end",
            audioDuration: duration,
            segmentCount: estimatedSegments
        )
        logger.info("Durée enregistrée: \(duration, format: .fixed(precision: 3)) s")

        if samples.isEmpty, duration < AudioRecorder.minimumDuration {
            logger.debug("Enregistrement ignoré: capture audio trop courte")
            sessionPolicy.complete(generation: generation)
            activeGeneration = nil
            overlayController.hide()
            return
        }

        guard sessionPolicy.beginTranscription(for: generation, reason: reason) else { return }
        if reason == .maximumDuration {
            overlayController.showTranscribing(message: "Durée maximale atteinte…")
        } else {
            overlayController.showTranscribing()
        }
        let targetApplication = targetApplication
        transcriptionTask = Task {
            [weak self, textCleanupService, textCleanupSettings, textInjector, overlayController, logger] in
            defer { ProcessMemoryDiagnostics.logFootprint(.dictationFinished) }
            let transcriptionStart = ContinuousClock.now
            PersistentDiagnosticLog.shared.stage(
                .transcription,
                phase: "begin",
                audioDuration: duration,
                segmentCount: estimatedSegments
            )
            EmergencyRuntime.shared.begin(.finalTranscription)
            do {
                let transcriptionSignpost = PerformanceSignposts.signposter.beginInterval("Transcription")
                let finishResult: SegmentedTranscriber.FinishResult
                do {
                    finishResult = try await segmentedTranscriber.finishWithBudget(
                        completeAudio: samples,
                        budget: 8
                    )
                    PerformanceSignposts.signposter.endInterval("Transcription", transcriptionSignpost)
                } catch {
                    PerformanceSignposts.signposter.endInterval("Transcription", transcriptionSignpost)
                    throw error
                }
                EmergencyRuntime.shared.end(.finalTranscription)
                let rawText = finishResult.text
                try Task.checkCancellation()
                let transcriptionSeconds = Self.seconds(transcriptionStart.duration(to: .now))
                PersistentDiagnosticLog.shared.stage(
                    .transcription,
                    phase: "end",
                    duration: transcriptionSeconds,
                    audioDuration: duration,
                    segmentCount: finishResult.segmentCount
                )

                let text: String
                let cleanupStart = ContinuousClock.now
                let cleanupEngine = textCleanupSettings.configuredEngine
                if textCleanupSettings.isEnabled, !rawText.isEmpty {
                    PersistentDiagnosticLog.shared.stage(
                        .cleanup,
                        phase: "begin",
                        audioDuration: duration,
                        segmentCount: finishResult.segmentCount
                    )
                    EmergencyRuntime.shared.begin(.cleanup)
                    let cleanupSignpost = PerformanceSignposts.signposter.beginInterval(
                        "Cleanup", "engine=\(cleanupEngine.rawValue, privacy: .public)"
                    )
                    do {
                        text = try await PipelineWatchdog.run(stage: "nettoyage") {
                            try await textCleanupService.cleanup(rawText)
                        }
                        PerformanceSignposts.signposter.endInterval("Cleanup", cleanupSignpost)
                        logger.info("Nettoyage du texte terminé")
                    } catch is CancellationError {
                        PerformanceSignposts.signposter.endInterval("Cleanup", cleanupSignpost)
                        throw CancellationError()
                    } catch {
                        PerformanceSignposts.signposter.endInterval("Cleanup", cleanupSignpost)
                        if error is PipelineWatchdogError { throw error }
                        text = rawText
                        logger.warning("Nettoyage indisponible, texte brut conservé")
                    }
                    PersistentDiagnosticLog.shared.stage(
                        .cleanup,
                        phase: "end",
                        duration: Self.seconds(cleanupStart.duration(to: .now)),
                        audioDuration: duration,
                        segmentCount: finishResult.segmentCount
                    )
                    EmergencyRuntime.shared.end(.cleanup)
                } else {
                    text = rawText
                }
                let cleanupSeconds = Self.seconds(cleanupStart.duration(to: .now))
                try Task.checkCancellation()

                let injectionStart = ContinuousClock.now
                PersistentDiagnosticLog.shared.stage(
                    .injection,
                    phase: "begin",
                    audioDuration: duration,
                    segmentCount: finishResult.segmentCount
                )
                EmergencyRuntime.shared.begin(.injection)
                let injectionSignpost = PerformanceSignposts.signposter.beginInterval("Injection")
                var injectionOutcome = TextInjectionOutcome.pasted
                do {
                    if !text.isEmpty {
                        guard self?.sessionPolicy.beginInjection(for: generation) == true else {
                            throw CancellationError()
                        }
                        try Task.checkCancellation()
                        injectionOutcome = textInjector.insert(text)
                    }
                    PerformanceSignposts.signposter.endInterval("Injection", injectionSignpost)
                } catch {
                    PerformanceSignposts.signposter.endInterval("Injection", injectionSignpost)
                    throw error
                }
                let injectionSeconds = Self.seconds(injectionStart.duration(to: .now))
                PersistentDiagnosticLog.shared.stage(
                    .injection,
                    phase: "end",
                    duration: injectionSeconds,
                    audioDuration: duration,
                    segmentCount: finishResult.segmentCount
                )
                EmergencyRuntime.shared.end(.injection)
                if !text.isEmpty {
                    do {
                        try TranscriptionHistoryStore.shared.add(
                            text: text,
                            targetApplication: targetApplication
                        )
                    } catch {
                        logger.error("Enregistrement de l’historique impossible")
                    }
                }
                let totalSeconds = Self.seconds(releaseInstant.duration(to: .now))
                DictationDiagnostics.shared.record(DictationTimings(
                    date: Date(),
                    stopAudio: stopAudioSeconds,
                    transcription: transcriptionSeconds,
                    cleanup: cleanupSeconds,
                    injection: injectionSeconds,
                    total: totalSeconds,
                    cleanupEngine: cleanupEngine
                ))
                if finishResult.isPartial {
                    overlayController.showMessage("Transcription partielle")
                } else if injectionOutcome == .copiedToClipboard {
                    overlayController.showMessage("Copié : ⌘V pour coller")
                } else {
                    overlayController.hide()
                }
            } catch is CancellationError {
                logger.debug("Transcription annulée")
                overlayController.hide()
            } catch let error as PipelineWatchdogError {
                logger.fault("Watchdog pipeline: \(error.localizedDescription, privacy: .public)")
                await segmentedTranscriber.cancel()
                await LocalCleanupModelManager.shared.unload(reason: "Modèle déchargé après timeout")
                await WhisperKitTranscriptionService.shared.unload(reason: "Whisper déchargé après timeout")
                overlayController.showError(error.localizedDescription)
            } catch {
                logger.error("Transcription impossible: \(error.localizedDescription, privacy: .public)")
                overlayController.showError("Transcription impossible")
            }
            guard let self else { return }
            self.sessionPolicy.complete(generation: generation)
            if self.activeGeneration == generation {
                self.activeGeneration = nil
                self.transcriptionTask = nil
            }
            EmergencyRuntime.shared.setIdle(true)
            self.refreshEmergencyCancellationHandlers()
        }
        refreshEmergencyCancellationHandlers()
    }

    private func cancelDictation() {
        let wasRecording = state == .recording
        guard sessionPolicy.cancel() else { return }
        EmergencyRuntime.shared.setIdle(true)
        activeGeneration = nil
        maximumDurationTask?.cancel()
        maximumDurationTask = nil
        audioFeedTask?.cancel()
        audioFeedTask = nil
        if wasRecording {
            _ = audioRecorder.stop()
            PersistentDiagnosticLog.shared.stage(.recording, phase: "cancelled")
        }
        transcriptionTask?.cancel()
        transcriptionTask = nil
        if let activeSegmentedTranscriber {
            Task { await activeSegmentedTranscriber.cancel() }
            self.activeSegmentedTranscriber = nil
        }
        overlayController.showMessage("Dictée annulée")
        refreshEmergencyCancellationHandlers()
    }

    private func cancelForMaximumDuration() {
        guard state == .recording else { return }
        overlayController.showTranscribing(message: "Durée maximale atteinte…")
        endRecording(reason: .maximumDuration)
    }

    private static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }

    private func playFeedbackSound(named name: String) {
        guard feedbackSoundSettings.isEnabled else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }

    private func handleAudioRecorderError(_ error: AudioRecorderError) {
        logger.error("Enregistrement interrompu: \(error.localizedDescription, privacy: .public)")
        let inputWasLost = switch error {
        case .inputUnavailable, .microphonePermissionRequired: true
        case .alreadyRecording, .converterCreationFailed: false
        }
        if state == .recording, inputWasLost {
            PersistentDiagnosticLog.shared.inputLost()
            overlayController.showTranscribing(message: "Entrée audio perdue — finalisation…")
            endRecording(reason: .inputLost)
            return
        }
        PersistentDiagnosticLog.shared.stage(.recording, phase: "error")
        audioFeedTask?.cancel()
        audioFeedTask = nil
        transcriptionTask?.cancel()
        transcriptionTask = nil
        maximumDurationTask?.cancel()
        maximumDurationTask = nil
        if let activeSegmentedTranscriber {
            Task { await activeSegmentedTranscriber.cancel() }
            self.activeSegmentedTranscriber = nil
        }
        _ = sessionPolicy.cancel()
        EmergencyRuntime.shared.setIdle(true)
        activeGeneration = nil
        overlayController.showError(error.localizedDescription)
        refreshEmergencyCancellationHandlers()
    }

    private func refreshEmergencyCancellationHandlers() {
        let tasks = [modelPreparationTask, audioFeedTask, maximumDurationTask, transcriptionTask]
            .compactMap { $0 }
        EmergencyCancellationHub.shared.replaceHandlers(
            tasks.map { task in { task.cancel() } }
        )
    }
}
