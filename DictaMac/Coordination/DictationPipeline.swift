import Foundation
import OSLog

enum PipelineFailure: Equatable, Sendable {
    case watchdog(String)
    case transcription
}

enum DictationOutcome: Equatable, Sendable {
    case inserted
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

    private struct ProcessedText {
        let rawValue: String
        let value: String
        let finishResult: SegmentedTranscriber.FinishResult
        let transcriptionDuration: TimeInterval
        let cleanupDuration: TimeInterval
        let cleanupEngine: TextCleanupEngine
    }

    private let textCleanupService: any TextCleanupService
    private let textCleanupSettings: any TextCleanupSettings
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
        textInjector: any TextInjector,
        historyRecorder: any DictationHistoryRecording,
        metricsRecorder: any DictationMetricsRecording,
        stageReporter: any DictationStageReporting,
        modelRecovery: any PipelineModelRecovering
    ) {
        self.textCleanupService = textCleanupService
        self.textCleanupSettings = textCleanupSettings
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
        let cleanupStartedAt = ContinuousClock.now
        let text = try await cleanup(result.text, result: result, session: session)
        try Task.checkCancellation()
        return ProcessedText(
            rawValue: result.text,
            value: text,
            finishResult: result,
            transcriptionDuration: transcriptionDuration,
            cleanupDuration: Self.seconds(cleanupStartedAt.duration(to: .now)),
            cleanupEngine: textCleanupSettings.configuredEngine
        )
    }

    private func transcribe(
        samples: [Float],
        session: DictationPipelineSession
    ) async throws -> SegmentedTranscriber.FinishResult {
        let context = StageContext(
            audioDuration: session.audioDuration,
            segmentCount: session.estimatedSegmentCount
        )
        return try await instrumentedStage.run(.transcription, context: context) {
            try await session.transcriber.finishWithBudget(
                completeAudio: samples,
                budget: Constants.finalTranscriptionBudget
            )
        }
    }

    private func cleanup(
        _ rawText: String,
        result: SegmentedTranscriber.FinishResult,
        session: DictationPipelineSession
    ) async throws -> String {
        guard textCleanupSettings.isEnabled, !rawText.isEmpty else { return rawText }
        let context = StageContext(
            audioDuration: session.audioDuration,
            segmentCount: result.segmentCount,
            detail: textCleanupSettings.configuredEngine.rawValue
        )
        let cleanupService = textCleanupService
        return try await instrumentedStage.run(.cleanup, context: context) {
            do {
                let text = try await PipelineWatchdog.run(stage: "nettoyage") {
                    try await cleanupService.cleanup(rawText)
                }
                self.logger.info("Nettoyage du texte terminé")
                return text
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if error is PipelineWatchdogError { throw error }
                self.logger.warning("Nettoyage indisponible, texte brut conservé")
                return rawText
            }
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
        if processed.finishResult.isPartial { return .partial }
        if injectionOutcome == .copiedToClipboard { return .copiedToClipboard }
        return .inserted
    }

    private static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
}
