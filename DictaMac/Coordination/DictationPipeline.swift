import Foundation
import OSLog

enum PipelineFailure: Equatable, Sendable {
    case watchdog(String)
    case transcription
}

enum DictationOutcome: Equatable, Sendable {
    case inserted
    case cleanupUnavailable
    case copiedToClipboard
    case partial
    case empty
    case cancelled
    case failed(PipelineFailure)
}

@MainActor
struct DictationPipelineSession {
    let transcriber: any SegmentedTranscribing
    let audioDuration: TimeInterval
    let estimatedSegmentCount: Int
    let stopAudioDuration: TimeInterval
    let releaseInstant: ContinuousClock.Instant
    let targetApplication: String
    let beginInjection: () -> Bool
}

@MainActor
protocol DictationPipelineRunning: AnyObject {
    func run(samples: [Float], session: DictationPipelineSession) async -> DictationOutcome
}

@MainActor
protocol PipelineModelRecovering: AnyObject {
    func recoverAfterWatchdog() async
}

@MainActor
final class DefaultPipelineModelRecovery: PipelineModelRecovering {
    private let recover: @MainActor () async -> Void

    init(recover: @escaping @MainActor () async -> Void) {
        self.recover = recover
    }

    func recoverAfterWatchdog() async {
        await recover()
    }
}

@MainActor
final class DictationPipeline: DictationPipelineRunning {
    private enum Constants {
        static let finalTranscriptionBudget: TimeInterval = 8
    }

    private enum ModelPreparationError: Error {
        case interrupted
    }

    private enum TranscriptionFailureError: Error {
        case failed
    }

    private struct ProcessedText {
        let rawValue: String
        let value: String
        let finishResult: SegmentedTranscriber.FinishResult
        let transcriptionDuration: TimeInterval
        let cleanupDuration: TimeInterval
        let cleanupEngine: TextCleanupEngine
        let cleanupUnavailable: Bool
    }

    private let textCleanupService: any TextCleanupService
    private let textCleanupSettings: any TextCleanupSettings
    private let personalDictionary: any PersonalDictionary
    private let textInjector: any TextInjector
    private let historyRecorder: any DictationHistoryRecording
    private let metricsRecorder: any DictationMetricsRecording
    private let instrumentedStage: InstrumentedStage
    private let modelRecovery: any PipelineModelRecovering
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "DictaMac",
        category: "DictationPipeline"
    )

    init(
        textCleanupService: any TextCleanupService,
        textCleanupSettings: any TextCleanupSettings,
        personalDictionary: any PersonalDictionary,
        textInjector: any TextInjector,
        historyRecorder: any DictationHistoryRecording,
        metricsRecorder: any DictationMetricsRecording,
        stageReporter: any DictationStageReporting,
        modelRecovery: any PipelineModelRecovering
    ) {
        self.textCleanupService = textCleanupService
        self.textCleanupSettings = textCleanupSettings
        self.personalDictionary = personalDictionary
        self.textInjector = textInjector
        self.historyRecorder = historyRecorder
        self.metricsRecorder = metricsRecorder
        self.instrumentedStage = InstrumentedStage(reporter: stageReporter)
        self.modelRecovery = modelRecovery
    }

    func run(samples: [Float], session: DictationPipelineSession) async -> DictationOutcome {
        do {
            let processed = try await processText(samples: samples, session: session)
            let injection = try await inject(processed.value, processed: processed, session: session)
            recordHistory(processed, targetApplication: session.targetApplication)
            recordMetrics(processed: processed, injectionDuration: injection.duration, session: session)
            return outcome(for: processed, injectionOutcome: injection.outcome)
        } catch is CancellationError {
            logger.debug("Pipeline de dictée annulé")
            return .cancelled
        } catch is ModelPreparationError {
            logger.error("Chargement du modèle interrompu pendant une dictée")
            return .failed(.transcription)
        } catch is TranscriptionFailureError {
            logger.error("Transcription impossible")
            return .failed(.transcription)
        } catch let error as PipelineWatchdogError {
            logger.fault("Watchdog pipeline: \(error.localizedDescription, privacy: .public)")
            await session.transcriber.cancel()
            await modelRecovery.recoverAfterWatchdog()
            return .failed(.watchdog(error.localizedDescription))
        } catch {
            logger.error("Transcription impossible: \(error.localizedDescription, privacy: .public)")
            return .failed(.transcription)
        }
    }

    private func processText(
        samples: [Float],
        session: DictationPipelineSession
    ) async throws -> ProcessedText {
        let transcriptionStartedAt = ContinuousClock.now
        let result = try await transcribe(samples: samples, session: session)
        try Task.checkCancellation()
        let transcriptionDuration = Self.seconds(transcriptionStartedAt.duration(to: .now))
        let dictionaryEntries = personalDictionary.entries()
        let correctedText = DictionaryCorrector.correct(result.text, entries: dictionaryEntries)
        let cleanupStartedAt = ContinuousClock.now
        let cleanupResult = try await cleanup(
            correctedText,
            dictionary: dictionaryEntries.map(\.canonical),
            result: result,
            session: session
        )
        try Task.checkCancellation()
        return ProcessedText(
            rawValue: result.text,
            value: cleanupResult.text,
            finishResult: result,
            transcriptionDuration: transcriptionDuration,
            cleanupDuration: Self.seconds(cleanupStartedAt.duration(to: .now)),
            cleanupEngine: textCleanupSettings.configuredEngine,
            cleanupUnavailable: cleanupResult.isUnavailable
        )
    }

    private func transcribe(
        samples: [Float],
        session: DictationPipelineSession
    ) async throws -> SegmentedTranscriber.FinishResult {
        try await prepareForFinalTranscription(session.transcriber)
        try Task.checkCancellation()
        let context = StageContext(
            audioDuration: session.audioDuration,
            segmentCount: session.estimatedSegmentCount
        )
        return try await runFinalTranscription(
            samples: samples,
            transcriber: session.transcriber,
            context: context
        )
    }

    private func prepareForFinalTranscription(
        _ transcriber: any SegmentedTranscribing
    ) async throws {
        do {
            try await transcriber.prepareForFinalTranscription()
        } catch is CancellationError {
            throw ModelPreparationError.interrupted
        } catch {
            throw TranscriptionFailureError.failed
        }
    }

    private func runFinalTranscription(
        samples: [Float],
        transcriber: any SegmentedTranscribing,
        context: StageContext
    ) async throws -> SegmentedTranscriber.FinishResult {
        do {
            return try await instrumentedStage.run(.transcription, context: context) {
                try await transcriber.finishWithBudget(
                    completeAudio: samples,
                    budget: Constants.finalTranscriptionBudget
                )
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as PipelineWatchdogError {
            throw error
        } catch {
            throw TranscriptionFailureError.failed
        }
    }

    private func cleanup(
        _ rawText: String,
        dictionary: [String],
        result: SegmentedTranscriber.FinishResult,
        session: DictationPipelineSession
    ) async throws -> (text: String, isUnavailable: Bool) {
        guard textCleanupSettings.isEnabled, !rawText.isEmpty else { return (rawText, false) }
        let context = StageContext(
            audioDuration: session.audioDuration,
            segmentCount: result.segmentCount,
            detail: textCleanupSettings.configuredEngine.rawValue
        )
        let cleanupService = textCleanupService
        return try await instrumentedStage.run(.cleanup, context: context) {
            try await self.performCleanup(rawText, dictionary: dictionary, service: cleanupService)
        }
    }

    private func performCleanup(
        _ text: String,
        dictionary: [String],
        service: any TextCleanupService
    ) async throws -> (text: String, isUnavailable: Bool) {
        do {
            let cleaned = try await PipelineWatchdog.run(stage: "nettoyage") {
                try await service.cleanup(text, dictionary: dictionary)
            }
            logger.info("Nettoyage du texte terminé")
            return (cleaned, false)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            logger.warning("Nettoyage IA indisponible, règles déterministes appliquées")
            let fallback = FastRulesTextCleanupService.cleanup(
                text,
                removeIsolatedGenre: textCleanupSettings.removeIsolatedGenre
            )
            return (fallback, textCleanupSettings.configuredEngine.isAI)
        }
    }

    private func inject(
        _ text: String,
        processed: ProcessedText,
        session: DictationPipelineSession
    ) async throws -> (outcome: TextInjectionOutcome, duration: TimeInterval) {
        let startedAt = ContinuousClock.now
        let context = StageContext(
            audioDuration: session.audioDuration,
            segmentCount: processed.finishResult.segmentCount
        )
        let outcome = try await instrumentedStage.run(.injection, context: context) {
            guard !text.isEmpty else { return TextInjectionOutcome.pasted }
            guard session.beginInjection() else { throw CancellationError() }
            try Task.checkCancellation()
            return self.textInjector.insert(text)
        }
        return (outcome, Self.seconds(startedAt.duration(to: .now)))
    }

    private func recordHistory(_ processed: ProcessedText, targetApplication: String) {
        guard !processed.value.isEmpty else { return }
        do {
            try historyRecorder.record(
                rawText: processed.rawValue,
                text: processed.value,
                targetApplication: targetApplication
            )
        } catch {
            logger.error("Enregistrement de l’historique impossible")
        }
    }

    private func recordMetrics(
        processed: ProcessedText,
        injectionDuration: TimeInterval,
        session: DictationPipelineSession
    ) {
        metricsRecorder.record(DictationTimings(
            date: Date(),
            stopAudio: session.stopAudioDuration,
            transcription: processed.transcriptionDuration,
            cleanup: processed.cleanupDuration,
            injection: injectionDuration,
            total: Self.seconds(session.releaseInstant.duration(to: .now)),
            cleanupEngine: processed.cleanupEngine
        ))
    }

    private func outcome(
        for processed: ProcessedText,
        injectionOutcome: TextInjectionOutcome
    ) -> DictationOutcome {
        if processed.value.isEmpty { return .empty }
        if processed.cleanupUnavailable { return .cleanupUnavailable }
        if processed.finishResult.isPartial { return .partial }
        if injectionOutcome == .copiedToClipboard { return .copiedToClipboard }
        return .inserted
    }

    private static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
}

private extension TextCleanupEngine {
    var isAI: Bool { self == .local || self == .cloud }
}
