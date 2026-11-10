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

final class SegmentedTranscriberTests: XCTestCase {
    private let configuration = SegmentedTranscriber.Configuration(
        sampleRate: 10,
        segmentDuration: 4,
        overlapDuration: 0.5
    )

    func testAssemblesIncrementalAndFinalSegments() async throws {
        let service = FakeTranscriptionService(results: [
            .success("Bonjour tout le monde"),
            .success("monde comment allez-vous")
        ])
        let transcriber = SegmentedTranscriber(
            transcriptionService: service,
            language: "fr",
            configuration: configuration
        )

        await transcriber.append(Array(repeating: 0, count: 40))
        let result = try await transcriber.finish(completeAudio: Array(repeating: 0, count: 50))

        XCTAssertEqual(result, "Bonjour tout le monde comment allez-vous")
        let sampleCounts = await service.sampleCounts()
        XCTAssertEqual(sampleCounts, [40, 15])
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

    func testFinalBudgetReturnsAlreadyTranscribedPartialText() async throws {
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

        XCTAssertTrue(result.isPartial)
        XCTAssertEqual(result.text, "segment disponible")
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
}
