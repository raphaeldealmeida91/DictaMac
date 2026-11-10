import XCTest
@testable import DictaMac

@MainActor
final class DictationCoordinatorTests: XCTestCase {
    func testNominalPressAndReleaseRunsPipeline() async {
        let fixture = Fixture()

        fixture.hotkey.press()
        XCTAssertEqual(fixture.coordinator.state, .recording)
        XCTAssertEqual(fixture.overlay.events, [.recording])

        fixture.hotkey.release()
        await fixture.waitUntilIdle()

        XCTAssertEqual(fixture.pipeline.runCount, 1)
        XCTAssertTrue(fixture.overlay.events.contains(.transcribing("Transcription…")))
        XCTAssertEqual(fixture.overlay.events.last, .hidden)
    }

    func testCancellationDuringRecordingStopsWithoutPipeline() {
        let fixture = Fixture()

        fixture.hotkey.press()
        fixture.hotkey.cancel()

        XCTAssertEqual(fixture.coordinator.state, .idle)
        XCTAssertEqual(fixture.audio.stopCount, 1)
        XCTAssertEqual(fixture.pipeline.runCount, 0)
        XCTAssertEqual(fixture.overlay.events.last, .message("Dictée annulée"))
    }

    func testMaximumDurationFinishesRecording() async {
        let fixture = Fixture()

        fixture.hotkey.press()
        fixture.sessionFactory.triggerMaximumDuration()
        await fixture.waitUntilIdle()

        XCTAssertEqual(fixture.pipeline.runCount, 1)
        XCTAssertTrue(
            fixture.overlay.events.contains(.transcribing("Durée maximale atteinte…"))
        )
    }

    func testLostAudioFinalizesAvailableCapture() async {
        let fixture = Fixture()

        fixture.hotkey.press()
        fixture.audio.fail(.inputUnavailable)
        await fixture.waitUntilIdle()

        XCTAssertEqual(fixture.pipeline.runCount, 1)
        XCTAssertEqual(fixture.stageReporter.inputLostCount, 1)
        XCTAssertTrue(
            fixture.overlay.events.contains(
                .transcribing("Entrée audio perdue — finalisation…")
            )
        )
    }

    func testShortPressFilteredByHotkeyProducesNoCoordinatorEvent() {
        let fixture = Fixture()

        fixture.hotkey.release()

        XCTAssertEqual(fixture.coordinator.state, .idle)
        XCTAssertEqual(fixture.audio.startCount, 0)
        XCTAssertTrue(fixture.overlay.events.isEmpty)
    }
}

@MainActor
private final class Fixture {
    let hotkey = FakeHotkeyProvider()
    let audio = FakeAudioRecorder()
    let overlay = FakeOverlayPresenter()
    let pipeline = FakePipeline()
    let stageReporter = FakeStageReporter()
    let sessionFactory: FakeRecordingSessionFactory
    let coordinator: DictationCoordinator

    init() {
        sessionFactory = FakeRecordingSessionFactory(audio: audio)
        coordinator = DictationCoordinator(dependencies: DictationCoordinatorDependencies(
            hotkeyProvider: hotkey,
            audioRecorder: audio,
            overlayPresenter: overlay,
            feedbackSoundPlayer: FakeFeedbackSoundPlayer(),
            recordingSessionFactory: sessionFactory,
            pipeline: pipeline,
            stageReporter: stageReporter,
            modelPreparer: FakeModelPreparer(),
            cancellationRegistry: FakeCancellationRegistry(),
            diagnosticLog: PersistentDiagnosticLog(),
            activityModel: AppActivityModel(),
            frontmostApplicationName: { "Tests" }
        ))
    }

    func waitUntilIdle() async {
        for _ in 0..<20 where coordinator.state != .idle {
            await Task.yield()
        }
    }
}

@MainActor
private final class FakeHotkeyProvider: HotkeyProviding {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var onCancel: (() -> Void)?

    func start() {}
    func stop() {}
    func press() { onPress?() }
    func release() { onRelease?() }
    func cancel() { onCancel?() }
}

// Test access is confined to the main-actor fixture despite the production protocol's Sendable bound.
private final class FakeAudioRecorder: AudioRecording, @unchecked Sendable {
    var onLevelUpdate: (@MainActor @Sendable (Float) -> Void)?
    var onError: (@MainActor @Sendable (AudioRecorderError) -> Void)?
    var lastRecordingDuration: TimeInterval = 1
    var samples = [Float](repeating: 0.1, count: 16)
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start() throws { startCount += 1 }

    func stop() -> [Float] {
        stopCount += 1
        return samples
    }

    func capturedSamples(since offset: Int) -> [Float] {
        guard offset < samples.count else { return [] }
        return Array(samples[offset...])
    }

    @MainActor
    func fail(_ error: AudioRecorderError) {
        onError?(error)
    }
}

private actor FakeSegmentedTranscriber: SegmentedTranscribing {
    func append(_ samples: [Float]) {}

    func finishWithBudget(
        completeAudio: [Float],
        budget: TimeInterval?
    ) async throws -> SegmentedTranscriber.FinishResult {
        SegmentedTranscriber.FinishResult(
            text: "texte",
            isPartial: false,
            segmentCount: 1
        )
    }

    func cancel() {}
}

@MainActor
private final class FakeRecordingSessionFactory: RecordingSessionBuilding {
    private let audio: FakeAudioRecorder
    private var maximumDurationHandler: (@MainActor () -> Void)?

    init(audio: FakeAudioRecorder) {
        self.audio = audio
    }

    func makeSession(
        onMaximumDuration: @escaping @MainActor () -> Void
    ) -> any RecordingSessionManaging {
        maximumDurationHandler = onMaximumDuration
        return RecordingSession(
            audioRecorder: audio,
            transcriber: FakeSegmentedTranscriber(),
            maximumDuration: 60,
            onMaximumDuration: onMaximumDuration
        )
    }

    func triggerMaximumDuration() {
        maximumDurationHandler?()
    }
}

@MainActor
private final class FakePipeline: DictationPipelineRunning {
    private(set) var runCount = 0
    var outcome = DictationOutcome.inserted

    func run(
        samples: [Float],
        session: DictationPipelineSession
    ) async -> DictationOutcome {
        runCount += 1
        _ = session.beginInjection()
        return outcome
    }
}

@MainActor
private final class FakeOverlayPresenter: OverlayPresenting {
    enum Event: Equatable {
        case recording
        case transcribing(String)
        case message(String)
        case error(String)
        case hidden
    }

    private(set) var events: [Event] = []

    func showRecording() { events.append(.recording) }
    func updateLevel(_ rms: Float) {}
    func showTranscribing(message: String) { events.append(.transcribing(message)) }
    func showMessage(_ message: String) { events.append(.message(message)) }
    func showError(_ message: String) { events.append(.error(message)) }
    func hide() { events.append(.hidden) }
}

@MainActor
private final class FakeFeedbackSoundPlayer: FeedbackSoundPlaying {
    func playStart() {}
    func playStop() {}
}

@MainActor
private final class FakeStageReporter: DictationStageReporting {
    private(set) var inputLostCount = 0

    func begin(_ stage: DiagnosticStage, context: StageContext) -> DictationStageHandle {
        DictationStageHandle(id: UUID(), stage: stage)
    }

    func end(
        _ handle: DictationStageHandle,
        context: StageContext,
        duration: TimeInterval
    ) {}

    func report(_ stage: DiagnosticStage, phase: String, context: StageContext) {}
    func reportInputLost() { inputLostCount += 1 }
    func setRuntimeIdle(_ isIdle: Bool) {}
}

@MainActor
private final class FakeModelPreparer: DictationModelPreparing {
    func prepare() async throws {}
}

private final class FakeCancellationRegistry: EmergencyCancellationRegistering {
    func replaceHandlers(_ handlers: [@Sendable () -> Void]) {}
}
