import XCTest
@testable import DictaMac

@MainActor
final class DictationPipelineTests: XCTestCase {
    func testCleanupFailureFallsBackToRawText() async {
        let injector = PipelineFakeInjector()
        let stageReporter = PipelineFakeStageReporter()
        let pipeline = makePipeline(
            cleanupService: FailingCleanupService(),
            injector: injector,
            stageReporter: stageReporter
        )

        let outcome = await pipeline.run(
            samples: [0.1],
            session: makeSession(transcriber: PipelineFakeTranscriber())
        )

        XCTAssertEqual(outcome, .inserted)
        XCTAssertEqual(injector.insertedText, "texte brut")
        XCTAssertEqual(stageReporter.beginStages, [.transcription, .cleanup, .injection])
        XCTAssertEqual(stageReporter.endStages, [.transcription, .cleanup, .injection])
    }

    func testStageIsClosedWhenTranscriptionFails() async {
        let stageReporter = PipelineFakeStageReporter()
        let pipeline = makePipeline(
            cleanupService: FailingCleanupService(),
            injector: PipelineFakeInjector(),
            stageReporter: stageReporter
        )

        let outcome = await pipeline.run(
            samples: [0.1],
            session: makeSession(transcriber: ThrowingPipelineTranscriber())
        )

        XCTAssertEqual(outcome, .failed(.transcription))
        XCTAssertEqual(stageReporter.beginStages, [.transcription])
        XCTAssertEqual(stageReporter.endStages, [.transcription])
    }

    func testHistoryKeepsRawAndCleanedTextForComparison() async {
        let history = PipelineFakeHistoryRecorder()
        let pipeline = makePipeline(
            cleanupService: SuccessfulCleanupService(output: "Texte nettoyé."),
            injector: PipelineFakeInjector(),
            stageReporter: PipelineFakeStageReporter(),
            historyRecorder: history
        )

        _ = await pipeline.run(
            samples: [0.1],
            session: makeSession(transcriber: PipelineFakeTranscriber())
        )

        XCTAssertEqual(history.rawText, "texte brut")
        XCTAssertEqual(history.text, "Texte nettoyé.")
    }

    private func makePipeline(
        cleanupService: any TextCleanupService,
        injector: PipelineFakeInjector,
        stageReporter: PipelineFakeStageReporter,
        historyRecorder: PipelineFakeHistoryRecorder = PipelineFakeHistoryRecorder()
    ) -> DictationPipeline {
        DictationPipeline(
            textCleanupService: cleanupService,
            textCleanupSettings: PipelineCleanupSettings(),
            textInjector: injector,
            historyRecorder: historyRecorder,
            metricsRecorder: PipelineFakeMetricsRecorder(),
            stageReporter: stageReporter,
            modelRecovery: PipelineFakeRecovery()
        )
    }

    private func makeSession(
        transcriber: any SegmentedTranscribing
    ) -> DictationPipelineSession {
        DictationPipelineSession(
            transcriber: transcriber,
            audioDuration: 1,
            estimatedSegmentCount: 1,
            stopAudioDuration: 0.01,
            releaseInstant: .now,
            targetApplication: "Tests",
            beginInjection: { true }
        )
    }
}

private actor PipelineFakeTranscriber: SegmentedTranscribing {
    func append(_ samples: [Float]) {}

    func finishWithBudget(
        completeAudio: [Float],
        budget: TimeInterval?
    ) async throws -> SegmentedTranscriber.FinishResult {
        SegmentedTranscriber.FinishResult(
            text: "texte brut",
            isPartial: false,
            segmentCount: 1
        )
    }

    func cancel() {}
}

private actor ThrowingPipelineTranscriber: SegmentedTranscribing {
    enum Failure: Error { case transcription }

    func append(_ samples: [Float]) {}

    func finishWithBudget(
        completeAudio: [Float],
        budget: TimeInterval?
    ) async throws -> SegmentedTranscriber.FinishResult {
        throw Failure.transcription
    }

    func cancel() {}
}

private actor FailingCleanupService: TextCleanupService {
    enum Failure: Error { case cleanup }

    func cleanup(_ text: String) async throws -> String {
        throw Failure.cleanup
    }
}

private actor SuccessfulCleanupService: TextCleanupService {
    let output: String

    init(output: String) {
        self.output = output
    }

    func cleanup(_ text: String) async throws -> String { output }
}

private struct PipelineCleanupSettings: TextCleanupSettings {
    let configuredEngine = TextCleanupEngine.fast
    let isEnabled = true
    let configuredModel = ""
    let configuredLocalModel = ""
    let removeIsolatedGenre = false
    let localTimeout: TimeInterval = 1
    let localDownloadApproved = false
}

@MainActor
private final class PipelineFakeInjector: TextInjector {
    private(set) var insertedText: String?

    func insert(_ text: String) -> TextInjectionOutcome {
        insertedText = text
        return .pasted
    }
}

@MainActor
private final class PipelineFakeHistoryRecorder: DictationHistoryRecording {
    private(set) var rawText: String?
    private(set) var text: String?

    func record(rawText: String, text: String, targetApplication: String) throws {
        self.rawText = rawText
        self.text = text
    }
}

@MainActor
private final class PipelineFakeMetricsRecorder: DictationMetricsRecording {
    func record(_ timings: DictationTimings) {}
}

@MainActor
private final class PipelineFakeStageReporter: DictationStageReporting {
    private(set) var beginStages: [DiagnosticStage] = []
    private(set) var endStages: [DiagnosticStage] = []

    func begin(_ stage: DiagnosticStage, context: StageContext) -> DictationStageHandle {
        beginStages.append(stage)
        return DictationStageHandle(id: UUID(), stage: stage)
    }

    func end(
        _ handle: DictationStageHandle,
        context: StageContext,
        duration: TimeInterval
    ) {
        endStages.append(handle.stage)
    }

    func report(_ stage: DiagnosticStage, phase: String, context: StageContext) {}
    func reportInputLost() {}
    func setRuntimeIdle(_ isIdle: Bool) {}
}

@MainActor
private final class PipelineFakeRecovery: PipelineModelRecovering {
    func recoverAfterWatchdog() async {}
}
