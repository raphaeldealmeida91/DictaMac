import XCTest
@testable import DictaMac

private actor FakeTranscriptionService: TranscriptionService {
    enum FakeError: Error { case segment }

    private var results: [Result<String, Error>]
    private var receivedSamples: [[Float]] = []
    private let delay: Duration?

    init(results: [Result<String, Error>], delay: Duration? = nil) {
        self.results = results
        self.delay = delay
    }

    func prepare() async throws {}

    func transcribe(_ samples: [Float], language: String?) async throws -> String {
        receivedSamples.append(samples)
        if let delay { try await ContinuousClock().sleep(for: delay) }
        guard !results.isEmpty else { return "" }
        return try results.removeFirst().get()
    }

    func sampleCounts() -> [Int] { receivedSamples.map(\.count) }
}

@MainActor
final class SegmentedTranscriberTests: XCTestCase {
    private let configuration = SegmentedTranscriber.Configuration(
        sampleRate: 10,
        segmentDuration: 4,
        overlapDuration: 0.5
    )

    func testAssemblesIncrementalAndFinalSegments() async throws {
        let diagnostics = WordDiagnosticsSpy()
        let service = FakeTranscriptionService(results: [
            .success("Bonjour tout le monde"),
            .success("monde comment allez-vous")
        ])
        let transcriber = SegmentedTranscriber(
            transcriptionService: service,
            language: "fr",
            configuration: configuration,
            wordDiagnostics: diagnostics
        )

        await transcriber.append(Array(repeating: 0, count: 40))
        let result = try await transcriber.finish(completeAudio: Array(repeating: 0, count: 50))

        XCTAssertEqual(result, "Bonjour tout le monde comment allez-vous")
        let sampleCounts = await service.sampleCounts()
        XCTAssertEqual(sampleCounts, [40, 15])
        XCTAssertEqual(diagnostics.count(for: .whisperSegment), 2)
        XCTAssertEqual(diagnostics.lastCount(for: .whisperTotal), 7)
        XCTAssertEqual(diagnostics.lastCount(for: .segmentedMerge), 6)
    }

    func testDeduplicatesLongestCaseAndPunctuationInsensitiveOverlap() {
        XCTAssertEqual(
            SegmentedTranscriber.assemble([
                "Un rendez-vous demain matin.",
                "DEMAIN matin à neuf heures",
                "neuf heures précises."
            ]),
            "Un rendez-vous demain matin à neuf heures précises."
        )
    }

    func testDeduplicatesFuzzyAccentInsensitiveOverlap() {
        XCTAssertEqual(
            SegmentedTranscriber.assemble([
                "Le dossier validé part demain matin",
                "dossier valide part demin matin à neuf heures"
            ]),
            "Le dossier validé part demain matin à neuf heures"
        )
    }

    func testFuzzyOverlapRejectsTooManySubstitutions() {
        XCTAssertEqual(
            SegmentedTranscriber.assemble([
                "Le dossier validé part demain matin",
                "dossier refusé revient vendredi matin"
            ]),
            "Le dossier validé part demain matin dossier refusé revient vendredi matin"
        )
    }

    func testKeepsRepeatedCompletePassageToAvoidContentLoss() {
        XCTAssertEqual(
            SegmentedTranscriber.assemble([
                "on part à huit heures on part à huit heures"
            ]),
            "on part à huit heures on part à huit heures"
        )
    }

    func testShortFinalSegmentIsTranscribedFromNextOverlappingStart() async throws {
        let service = FakeTranscriptionService(results: [.success("premier"), .success("fin")])
        let transcriber = SegmentedTranscriber(
            transcriptionService: service,
            language: nil,
            configuration: configuration
        )

        await transcriber.append(Array(repeating: 0, count: 40))
        _ = try await transcriber.finish(completeAudio: Array(repeating: 0, count: 42))

        let sampleCounts = await service.sampleCounts()
        XCTAssertEqual(sampleCounts, [40, 7])
    }

    func testDictationUnderFourSecondsKeepsSinglePassBehavior() async throws {
        let service = FakeTranscriptionService(results: [.success("dictée courte")])
        let transcriber = SegmentedTranscriber(
            transcriptionService: service,
            language: "fr",
            configuration: configuration
        )

        await transcriber.append(Array(repeating: 0, count: 30))
        let result = try await transcriber.finish(completeAudio: Array(repeating: 0, count: 30))

        XCTAssertEqual(result, "dictée courte")
        let sampleCounts = await service.sampleCounts()
        XCTAssertEqual(sampleCounts, [30])
    }

    func testDictationFittingExactlyOneWindowUsesOneCompletePass() async throws {
        let service = FakeTranscriptionService(results: [.success("une seule passe")])
        let transcriber = SegmentedTranscriber(
            transcriptionService: service,
            language: "fr",
            configuration: configuration
        )

        await transcriber.append(Array(repeating: 0, count: 40))
        let result = try await transcriber.finish(completeAudio: Array(repeating: 0, count: 40))

        XCTAssertEqual(result, "une seule passe")
        let sampleCounts = await service.sampleCounts()
        XCTAssertEqual(sampleCounts, [40])
    }

    func testSegmentErrorFallsBackToCompleteTranscription() async throws {
        let service = FakeTranscriptionService(results: [
            .failure(FakeTranscriptionService.FakeError.segment),
            .success("transcription complète")
        ])
        let transcriber = SegmentedTranscriber(
            transcriptionService: service,
            language: "fr",
            configuration: configuration
        )

        await transcriber.append(Array(repeating: 0, count: 40))
        let result = try await transcriber.finish(completeAudio: Array(repeating: 0, count: 50))

        XCTAssertEqual(result, "transcription complète")
        let sampleCounts = await service.sampleCounts()
        XCTAssertEqual(sampleCounts, [40, 50])
    }

    func testCancellationStopsInFlightSegmentAndDoesNotFallback() async throws {
        let service = FakeTranscriptionService(
            results: [.success("ne doit pas aboutir")],
            delay: .seconds(5)
        )
        let transcriber = SegmentedTranscriber(
            transcriptionService: service,
            language: "fr",
            configuration: configuration
        )
        await transcriber.append(Array(repeating: 0, count: 40))

        let task = Task {
            try await transcriber.finish(completeAudio: Array(repeating: 0, count: 50))
        }
        try await ContinuousClock().sleep(for: .milliseconds(20))
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        }
        let sampleCounts = await service.sampleCounts()
        XCTAssertEqual(sampleCounts, [40])
    }

    func testBacklogDropsIntermediateSegmentsAndTranscribesFinalAudio() async throws {
        let service = FakeTranscriptionService(
            results: [.success("segment ancien"), .success("transcription finale")],
            delay: .milliseconds(30)
        )
        let overloadedConfiguration = SegmentedTranscriber.Configuration(
            sampleRate: 10,
            segmentDuration: 4,
            overlapDuration: 0.5,
            maximumBacklog: 1
        )
        let transcriber = SegmentedTranscriber(
            transcriptionService: service,
            language: "fr",
            configuration: overloadedConfiguration
        )

        await transcriber.append(Array(repeating: 0, count: 40))
        try await ContinuousClock().sleep(for: .milliseconds(5))
        await transcriber.append(Array(repeating: 0, count: 150))
        let result = try await transcriber.finish(completeAudio: Array(repeating: 0, count: 190))

        XCTAssertEqual(result, "transcription finale")
        let sampleCounts = await service.sampleCounts()
        XCTAssertEqual(sampleCounts, [40, 190])
    }

    func testFinalBudgetDoesNotTruncateTranscribedText() async throws {
        let service = FakeTranscriptionService(
            results: [.success("segment disponible"), .success("segment trop lent")],
            delay: .milliseconds(30)
        )
        let transcriber = SegmentedTranscriber(
            transcriptionService: service,
            language: "fr",
            configuration: configuration
        )
        await transcriber.append(Array(repeating: 0, count: 40))
        try await ContinuousClock().sleep(for: .milliseconds(40))

        let result = try await transcriber.finishWithBudget(
            completeAudio: Array(repeating: 0, count: 50),
            budget: 0.005
        )

        XCTAssertFalse(result.isPartial)
        XCTAssertEqual(result.text, "segment disponible segment trop lent")
    }

    func testFortySecondBacklogKeepsEveryTranscribedSegment() async throws {
        let scenario = longScenario(duration: 40)
        let service = FakeTranscriptionService(results: scenario.results, delay: .milliseconds(1))
        let transcriber = SegmentedTranscriber(
            transcriptionService: service,
            language: "fr",
            configuration: overloadedConfiguration
        )

        await transcriber.append(scenario.samples)
        let result = try await transcriber.finishWithBudget(
            completeAudio: scenario.samples,
            budget: 8
        )

        assertComplete(result, scenario: scenario)
    }

    func testOneHundredTwentySecondBudgetOverrunKeepsEveryTranscribedSegment() async throws {
        let scenario = longScenario(duration: 120)
        let service = FakeTranscriptionService(results: scenario.results, delay: .milliseconds(1))
        let transcriber = SegmentedTranscriber(
            transcriptionService: service,
            language: "fr",
            configuration: configuration
        )

        await transcriber.append(Array(scenario.samples.prefix(40)))
        let result = try await transcriber.finishWithBudget(
            completeAudio: scenario.samples,
            budget: 0.001
        )

        assertComplete(result, scenario: scenario)
    }

    func testLongDictationContinuesAfterOneSegmentFailure() async throws {
        let scenario = longScenario(duration: 40)
        let failedIndex = 4
        var results = scenario.results
        results[failedIndex] = .failure(FakeTranscriptionService.FakeError.segment)
        let service = FakeTranscriptionService(results: results)
        let transcriber = SegmentedTranscriber(
            transcriptionService: service,
            language: "fr",
            configuration: configuration
        )

        let result = try await transcriber.finishWithBudget(
            completeAudio: scenario.samples,
            budget: 8
        )

        for index in scenario.texts.indices where index != failedIndex {
            XCTAssertTrue(result.text.contains("unique\(index)"), "Missing successful segment \(index)")
        }
        let successfulRawWords = scenario.texts.indices
            .filter { $0 != failedIndex }
            .reduce(0) { count, index in
                count + scenario.texts[index].split(whereSeparator: \.isWhitespace).count
            }
        let retainedOverlaps = (failedIndex - 1) + (scenario.texts.count - failedIndex - 2)
        XCTAssertEqual(
            result.text.split(whereSeparator: \.isWhitespace).count,
            successfulRawWords - retainedOverlaps
        )
    }

    func testLongDictationCancellationDoesNotReturnTruncatedSuccess() async throws {
        let scenario = longScenario(duration: 120)
        let service = FakeTranscriptionService(results: scenario.results, delay: .milliseconds(20))
        let transcriber = SegmentedTranscriber(
            transcriptionService: service,
            language: "fr",
            configuration: configuration
        )
        let task = Task {
            try await transcriber.finishWithBudget(completeAudio: scenario.samples, budget: 8)
        }
        try await ContinuousClock().sleep(for: .milliseconds(30))
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation instead of a truncated successful result")
        } catch is CancellationError {
            // Expected.
        }
    }

    func testLongDictationNeverFallsBackToOneCompleteAudioCall() async throws {
        let service = FakeTranscriptionService(results: [
            .failure(FakeTranscriptionService.FakeError.segment)
        ])
        let transcriber = SegmentedTranscriber(
            transcriptionService: service,
            language: "fr",
            configuration: configuration
        )
        await transcriber.append(Array(repeating: 0, count: 40))
        try await ContinuousClock().sleep(for: .milliseconds(10))

        let result = try await transcriber.finishWithBudget(
            completeAudio: Array(repeating: 0, count: 310),
            budget: 8
        )

        XCTAssertTrue(result.isPartial)
        let sampleCounts = await service.sampleCounts()
        XCTAssertFalse(sampleCounts.contains(310))
    }

    private var overloadedConfiguration: SegmentedTranscriber.Configuration {
        SegmentedTranscriber.Configuration(
            sampleRate: 10,
            segmentDuration: 4,
            overlapDuration: 0.5,
            maximumBacklog: 1
        )
    }

    private func longScenario(duration: Int) -> LongScenario {
        let sampleCount = duration * configuration.sampleRate
        let completeSegments = 1 + (sampleCount - configuration.segmentSampleCount)
            / configuration.strideSampleCount
        let hasTail = completeSegments * configuration.strideSampleCount < sampleCount
        let segmentCount = completeSegments + (hasTail ? 1 : 0)
        let texts = (0..<segmentCount).map { index in
            index == 0
                ? "unique0 contenu0 overlap0"
                : "overlap\(index - 1) unique\(index) contenu\(index) overlap\(index)"
        }
        return LongScenario(
            samples: Array(repeating: 0, count: sampleCount),
            texts: texts,
            results: texts.map { .success($0) }
        )
    }

    private func assertComplete(
        _ result: SegmentedTranscriber.FinishResult,
        scenario: LongScenario
    ) {
        let rawWords = scenario.texts.reduce(0) { $0 + $1.split(whereSeparator: \.isWhitespace).count }
        let expectedWords = rawWords - (scenario.texts.count - 1)
        XCTAssertFalse(result.isPartial)
        XCTAssertEqual(result.text.split(whereSeparator: \.isWhitespace).count, expectedWords)
        for index in scenario.texts.indices {
            XCTAssertTrue(result.text.contains("unique\(index)"), "Missing segment \(index)")
        }
    }
}

private struct LongScenario {
    let samples: [Float]
    let texts: [String]
    let results: [Result<String, Error>]
}

@MainActor
private final class WordDiagnosticsSpy: TextWordDiagnosticsRecording {
    private var entries: [TextWordDiagnosticEntry] = []

    func beginWordDiagnostics() { entries = [] }

    func recordWordCount(_ count: Int, stage: TextWordDiagnosticStage, segmentIndex: Int?) {
        entries.append(TextWordDiagnosticEntry(stage: stage, segmentIndex: segmentIndex, wordCount: count))
    }

    func count(for stage: TextWordDiagnosticStage) -> Int {
        entries.filter { $0.stage == stage }.count
    }

    func lastCount(for stage: TextWordDiagnosticStage) -> Int? {
        entries.last { $0.stage == stage }?.wordCount
    }
}
