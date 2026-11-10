import Foundation
import OSLog

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
    private enum Constants {
        static let estimatedSegmentDuration: TimeInterval = 4
        static let minimumTranscribableDuration: TimeInterval = 0.050
        static let unknownApplication = "Application inconnue"
    }

    var state: DictationState { sessionPolicy.state }

    private let hotkeyProvider: any HotkeyProviding
    private let audioRecorder: any AudioRecording
    private let overlayPresenter: any OverlayPresenting
    private let feedbackSoundPlayer: any FeedbackSoundPlaying
    private let recordingSessionFactory: any RecordingSessionBuilding
    private let pipeline: any DictationPipelineRunning
    private let stageReporter: any DictationStageReporting
    private let modelPreparer: any DictationModelPreparing
    private let cancellationRegistry: any EmergencyCancellationRegistering
    private let frontmostApplicationName: () -> String?
    private var sessionPolicy = DictationSessionPolicy()
    private var activeGeneration: Int?
    private var recordingSession: (any RecordingSessionManaging)?
    private var pipelineTask: Task<Void, Never>?
    private var modelPreparationTask: Task<Void, Never>?
    private var emergencyObserver: NSObjectProtocol?
    private var targetApplication = Constants.unknownApplication
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "DictaMac",
        category: "Dictation"
    )

    init(
        hotkeyProvider: any HotkeyProviding,
        audioRecorder: any AudioRecording,
        overlayPresenter: any OverlayPresenting,
        feedbackSoundPlayer: any FeedbackSoundPlaying,
        recordingSessionFactory: any RecordingSessionBuilding,
        pipeline: any DictationPipelineRunning,
        stageReporter: any DictationStageReporting,
        modelPreparer: any DictationModelPreparing,
        cancellationRegistry: any EmergencyCancellationRegistering,
        frontmostApplicationName: @escaping () -> String?
    ) {
        self.hotkeyProvider = hotkeyProvider
        self.audioRecorder = audioRecorder
        self.overlayPresenter = overlayPresenter
        self.feedbackSoundPlayer = feedbackSoundPlayer
        self.recordingSessionFactory = recordingSessionFactory
        self.pipeline = pipeline
        self.stageReporter = stageReporter
        self.modelPreparer = modelPreparer
        self.cancellationRegistry = cancellationRegistry
        self.frontmostApplicationName = frontmostApplicationName
        bindEvents()
    }

    func start() {
        hotkeyProvider.start()
        modelPreparationTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.modelPreparer.prepare()
                self.logger.info("Modèle de transcription prêt")
            } catch is CancellationError {
                return
            } catch {
                self.logger.error(
                    "Préparation du modèle impossible: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
        refreshEmergencyCancellationHandlers()
    }

    func stop() {
        hotkeyProvider.stop()
        modelPreparationTask?.cancel()
        modelPreparationTask = nil
        pipelineTask?.cancel()
        recordingSession?.cancel()
        _ = sessionPolicy.cancel()
        clearActiveSession()
        overlayPresenter.hide()
    }

    private func bindEvents() {
        hotkeyProvider.onPress = { [weak self] in self?.beginRecording() }
        hotkeyProvider.onRelease = { [weak self] in self?.endRecording() }
        hotkeyProvider.onCancel = { [weak self] in self?.cancelDictation() }
        audioRecorder.onLevelUpdate = { [weak overlayPresenter] level in
            overlayPresenter?.updateLevel(level)
        }
        audioRecorder.onError = { [weak self] error in self?.handleAudioRecorderError(error) }
        emergencyObserver = NotificationCenter.default.addObserver(
            forName: .emergencyStopRequested,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.cancelDictation() }
        }
    }

    private func beginRecording() {
        guard state == .idle else { return }
        stageReporter.report(.recording, phase: "begin", context: StageContext())
        ProcessMemoryDiagnostics.logFootprint(.dictationStarted)
        let session = makeRecordingSession()
        do {
            try session.start()
            try activate(session)
        } catch {
            session.cancel()
            stageReporter.report(.recording, phase: "error", context: StageContext())
            logger.error("Démarrage de l’enregistrement impossible: \(error.localizedDescription, privacy: .public)")
            overlayPresenter.showError(error.localizedDescription)
        }
    }

    private func makeRecordingSession() -> any RecordingSessionManaging {
        recordingSessionFactory.makeSession { [weak self] in
            self?.finishForMaximumDuration()
        }
    }

    private func activate(_ session: any RecordingSessionManaging) throws {
        guard let generation = sessionPolicy.beginRecording() else {
            throw CancellationError()
        }
        recordingSession = session
        activeGeneration = generation
        stageReporter.setRuntimeIdle(false)
        targetApplication = frontmostApplicationName() ?? Constants.unknownApplication
        overlayPresenter.showRecording()
        feedbackSoundPlayer.playStart()
        refreshEmergencyCancellationHandlers()
    }

    private func endRecording(reason: DictationSessionPolicy.StopReason = .released) {
        guard state == .recording,
              let generation = activeGeneration,
              let recordingSession else { return }
        let releaseInstant = ContinuousClock.now
        let result = recordingSession.finish()
        self.recordingSession = nil
        feedbackSoundPlayer.playStop()
        reportRecordingFinished(result)
        guard shouldTranscribe(result) else {
            completeSession(generation: generation)
            overlayPresenter.hide()
            return
        }
        startPipeline(result: result, generation: generation, reason: reason, releaseInstant: releaseInstant)
    }

    private func reportRecordingFinished(_ result: RecordingSessionResult) {
        let context = StageContext(
            audioDuration: result.duration,
            segmentCount: estimatedSegmentCount(for: result.duration)
        )
        stageReporter.report(.recording, phase: "end", context: context)
        logger.info("Durée enregistrée: \(result.duration, format: .fixed(precision: 3)) s")
    }

    private func shouldTranscribe(_ result: RecordingSessionResult) -> Bool {
        let tooShort = result.samples.isEmpty
            && result.duration < Constants.minimumTranscribableDuration
        if tooShort { logger.debug("Enregistrement ignoré: capture audio trop courte") }
        return !tooShort
    }

    private func startPipeline(
        result: RecordingSessionResult,
        generation: Int,
        reason: DictationSessionPolicy.StopReason,
        releaseInstant: ContinuousClock.Instant
    ) {
        guard sessionPolicy.beginTranscription(for: generation, reason: reason) else { return }
        showTranscribing(reason: reason)
        let session = makePipelineSession(
            result: result,
            generation: generation,
            releaseInstant: releaseInstant
        )
        pipelineTask = Task { [weak self] in
            defer { ProcessMemoryDiagnostics.logFootprint(.dictationFinished) }
            guard let self else { return }
            let outcome = await self.pipeline.run(samples: result.samples, session: session)
            self.present(outcome)
            self.completeSession(generation: generation)
        }
        refreshEmergencyCancellationHandlers()
    }

    private func makePipelineSession(
        result: RecordingSessionResult,
        generation: Int,
        releaseInstant: ContinuousClock.Instant
    ) -> DictationPipelineSession {
        DictationPipelineSession(
            transcriber: result.transcriber,
            audioDuration: result.duration,
            estimatedSegmentCount: estimatedSegmentCount(for: result.duration),
            stopAudioDuration: Self.seconds(releaseInstant.duration(to: .now)),
            releaseInstant: releaseInstant,
            targetApplication: targetApplication,
            beginInjection: { [weak self] in
                self?.sessionPolicy.beginInjection(for: generation) == true
            }
        )
    }

    private func showTranscribing(reason: DictationSessionPolicy.StopReason) {
        if reason == .maximumDuration {
            overlayPresenter.showTranscribing(message: "Durée maximale atteinte…")
        } else {
            overlayPresenter.showTranscribing()
        }
    }

    private func present(_ outcome: DictationOutcome) {
        switch outcome {
        case .inserted, .empty, .cancelled:
            overlayPresenter.hide()
        case .copiedToClipboard:
            overlayPresenter.showMessage("Copié : ⌘V pour coller")
        case .partial:
            overlayPresenter.showMessage("Transcription partielle")
        case let .failed(.watchdog(message)):
            overlayPresenter.showError(message)
        case .failed(.transcription):
            overlayPresenter.showError("Transcription impossible")
        }
    }

    private func cancelDictation() {
        let wasRecording = state == .recording
        guard sessionPolicy.cancel() else { return }
        recordingSession?.cancel()
        if wasRecording {
            stageReporter.report(.recording, phase: "cancelled", context: StageContext())
        }
        pipelineTask?.cancel()
        clearActiveSession()
        overlayPresenter.showMessage("Dictée annulée")
    }

    private func finishForMaximumDuration() {
        guard state == .recording else { return }
        overlayPresenter.showTranscribing(message: "Durée maximale atteinte…")
        endRecording(reason: .maximumDuration)
    }

    private func handleAudioRecorderError(_ error: AudioRecorderError) {
        logger.error("Enregistrement interrompu: \(error.localizedDescription, privacy: .public)")
        if state == .recording, inputWasLost(error) {
            stageReporter.reportInputLost()
            overlayPresenter.showTranscribing(message: "Entrée audio perdue — finalisation…")
            endRecording(reason: .inputLost)
            return
        }
        failRecording(with: error)
    }

    private func inputWasLost(_ error: AudioRecorderError) -> Bool {
        switch error {
        case .inputUnavailable, .microphonePermissionRequired: true
        case .alreadyRecording, .converterCreationFailed: false
        }
    }

    private func failRecording(with error: AudioRecorderError) {
        stageReporter.report(.recording, phase: "error", context: StageContext())
        recordingSession?.cancel()
        pipelineTask?.cancel()
        _ = sessionPolicy.cancel()
        clearActiveSession()
        overlayPresenter.showError(error.localizedDescription)
    }

    private func completeSession(generation: Int) {
        sessionPolicy.complete(generation: generation)
        guard activeGeneration == generation else { return }
        clearActiveSession()
    }

    private func clearActiveSession() {
        recordingSession = nil
        pipelineTask = nil
        activeGeneration = nil
        stageReporter.setRuntimeIdle(true)
        refreshEmergencyCancellationHandlers()
    }

    private func refreshEmergencyCancellationHandlers() {
        var handlers = recordingSession?.cancellationHandlers ?? []
        handlers.append(contentsOf: [modelPreparationTask, pipelineTask].compactMap { task -> (@Sendable () -> Void)? in
            guard let task else { return nil }
            return { @Sendable in task.cancel() }
        })
        cancellationRegistry.replaceHandlers(handlers)
    }

    private func estimatedSegmentCount(for duration: TimeInterval) -> Int {
        max(1, Int(ceil(duration / Constants.estimatedSegmentDuration)))
    }

    private static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
}
