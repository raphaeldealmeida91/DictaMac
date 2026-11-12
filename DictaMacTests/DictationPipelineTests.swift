import XCTest
@testable import DictaMac

@MainActor
final class DictationPipelineTests: XCTestCase {
    func testCleanupFailureFallsBackToDeterministicRulesAndSignalsAvailability() async {
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

        XCTAssertEqual(outcome, .cleanupUnavailable)
        XCTAssertEqual(injector.insertedText, "Texte brut.")
        XCTAssertEqual(stageReporter.beginStages, [.transcription, .cleanup, .injection])
        XCTAssertEqual(stageReporter.endStages, [.transcription, .cleanup, .injection])
    }

    func testStageIsClosedWhenTranscriptionFails() async {
        let stageReporter = PipelineFakeStageReporter()
        let injector = PipelineFakeInjector()
        let pipeline = makePipeline(
            cleanupService: FailingCleanupService(),
            injector: injector,
            stageReporter: stageReporter
        )

        let outcome = await pipeline.run(
            samples: [0.1],
            session: makeSession(transcriber: ThrowingPipelineTranscriber())
        )

        XCTAssertEqual(outcome, .failed(.transcription))
        XCTAssertEqual(stageReporter.beginStages, [.transcription])
        XCTAssertEqual(stageReporter.endStages, [.transcription])
        XCTAssertNil(injector.insertedText)
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

    func testDictionaryCorrectionRunsBeforeCleanupAndProvidesCanonicalTerms() async {
        let cleanup = PipelineCleanupSpy()
        let injector = PipelineFakeInjector()
        let dictionary = PipelinePersonalDictionary(entries: [
            DictionaryEntry(canonical: "devis", variants: ["de vie"])
        ])
        let pipeline = makePipeline(
            cleanupService: cleanup,
            injector: injector,
            stageReporter: PipelineFakeStageReporter(),
            personalDictionary: dictionary
        )

        _ = await pipeline.run(
            samples: [0.1],
            session: makeSession(transcriber: PipelineFakeTranscriber(text: "le de vie est prêt"))
        )

        let received = await cleanup.received()
        XCTAssertEqual(received.text, "Le devis est prêt.")
        XCTAssertEqual(received.dictionary, ["devis"])
        XCTAssertEqual(injector.insertedText, "Le devis est prêt.")
    }

    func testModelPreparationFailureDoesNotStartTranscriptionStage() async {
        let stageReporter = PipelineFakeStageReporter()
        let injector = PipelineFakeInjector()
        let pipeline = makePipeline(
            cleanupService: FailingCleanupService(),
            injector: injector,
            stageReporter: stageReporter
        )

        let outcome = await pipeline.run(
            samples: [0.1],
            session: makeSession(transcriber: PreparationFailingTranscriber())
        )

        XCTAssertEqual(outcome, .failed(.transcription))
        XCTAssertTrue(stageReporter.beginStages.isEmpty)
        XCTAssertNil(injector.insertedText)
    }

    func testRecordsPipelineWordCountsThroughInjection() async {
        let diagnostics = PipelineWordDiagnosticsSpy()
        let pipeline = makePipeline(
            cleanupService: SuccessfulCleanupService(output: "Texte final conservé."),
            injector: PipelineFakeInjector(),
            stageReporter: PipelineFakeStageReporter(),
            wordDiagnostics: diagnostics
        )

        _ = await pipeline.run(
            samples: [0.1],
            session: makeSession(transcriber: PipelineFakeTranscriber(text: "texte brut conservé"))
        )

        XCTAssertEqual(diagnostics.stages, [
            .dictionary, .deterministicRules, .postProcessor, .injected
        ])
    }

    private func makePipeline(
        cleanupService: any TextCleanupService,
        injector: PipelineFakeInjector,
        stageReporter: PipelineFakeStageReporter,
        historyRecorder: PipelineFakeHistoryRecorder = PipelineFakeHistoryRecorder(),
        personalDictionary: any PersonalDictionary = PipelinePersonalDictionary(entries: []),
        wordDiagnostics: (any TextWordDiagnosticsRecording)? = nil
    ) -> DictationPipeline {
        DictationPipeline(
            textCleanupService: cleanupService,
            textCleanupSettings: PipelineCleanupSettings(),
            personalDictionary: personalDictionary,
            textInjector: injector,
            historyRecorder: historyRecorder,
            metricsRecorder: PipelineFakeMetricsRecorder(),
            stageReporter: stageReporter,
            modelRecovery: PipelineFakeRecovery(),
            wordDiagnostics: wordDiagnostics
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
    private let text: String

    init(text: String = "texte brut") {
        self.text = text
    }

    func append(_ samples: [Float]) {}

    func finishWithBudget(
        completeAudio: [Float],
        budget: TimeInterval?
    ) async throws -> SegmentedTranscriber.FinishResult {
        SegmentedTranscriber.FinishResult(
            text: text,
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

private actor PreparationFailingTranscriber: SegmentedTranscribing {
    enum Failure: Error { case modelUnavailable }

    func append(_ samples: [Float]) {}
    func prepareForFinalTranscription() async throws { throw Failure.modelUnavailable }

    func finishWithBudget(
        completeAudio: [Float],
        budget: TimeInterval?
    ) async throws -> SegmentedTranscriber.FinishResult {
        XCTFail("Final transcription must not start before model preparation succeeds")
        throw Failure.modelUnavailable
    }

    func cancel() {}
}

private actor FailingCleanupService: TextCleanupService {
    enum Failure: Error { case cleanup }

    func cleanup(_ text: String, dictionary: [String]) async throws -> String {
        throw Failure.cleanup
    }
}

private actor SuccessfulCleanupService: TextCleanupService {
    let output: String

    init(output: String) {
        self.output = output
    }

    func cleanup(_ text: String, dictionary: [String]) async throws -> String { output }
}

private actor PipelineCleanupSpy: TextCleanupService {
    private var text = ""
    private var dictionary: [String] = []

    func cleanup(_ text: String, dictionary: [String]) async throws -> String {
        self.text = text
        self.dictionary = dictionary
        return text
    }

    func received() -> (text: String, dictionary: [String]) {
        (text, dictionary)
    }
}

private struct PipelinePersonalDictionary: PersonalDictionary {
    let storedEntries: [DictionaryEntry]

    init(entries: [DictionaryEntry]) {
        storedEntries = entries
    }

    func entries() -> [DictionaryEntry] { storedEntries }
    func replaceEntries(_ entries: [DictionaryEntry]) throws {}
    func addCanonicalTerm(_ canonical: String) throws -> Bool { false }
}

private struct PipelineCleanupSettings: TextCleanupSettings {
    let configuredEngine = TextCleanupEngine.cloud
    let isEnabled = true
    let configuredModel = ""
    let configuredLocalModel = ""
    let cleanupStyle = CleanupStyle.polished
    let removeIsolatedGenre = false
    let localTimeout: TimeInterval = 1
    let cloudTimeout: TimeInterval = 1
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

@MainActor
private final class PipelineWordDiagnosticsSpy: TextWordDiagnosticsRecording {
    private(set) var stages: [TextWordDiagnosticStage] = []

    func beginWordDiagnostics() { stages = [] }

    func recordWordCount(_ count: Int, stage: TextWordDiagnosticStage, segmentIndex: Int?) {
        stages.append(stage)
    }
}
