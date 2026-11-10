@preconcurrency import AVFoundation
import XCTest
@testable import DictaMac

@MainActor
final class AudioRecorderTests: XCTestCase {
    func testNominalStartAndStop() throws {
        let fixture = AudioRecorderFixture()
        try fixture.recorder.start()
        fixture.append(samples: Array(repeating: 0.25, count: 800))

        let samples = fixture.recorder.stop()

        XCTAssertEqual(samples.count, 800)
        XCTAssertEqual(fixture.engine.startCount, 1)
        XCTAssertEqual(fixture.engine.stopCount, 1)
    }

    func testPermissionRefusalPreventsStart() {
        let fixture = AudioRecorderFixture(isAuthorized: false)

        XCTAssertThrowsError(try fixture.recorder.start()) { error in
            XCTAssertEqual(error as? AudioRecorderError, .microphonePermissionRequired)
        }
        XCTAssertEqual(fixture.engine.startCount, 0)
    }

    func testDoubleStartIsRejectedWithoutDiscardingCapture() throws {
        let fixture = AudioRecorderFixture()
        try fixture.recorder.start()
        fixture.append(samples: [0.1, 0.2])

        XCTAssertThrowsError(try fixture.recorder.start()) { error in
            XCTAssertEqual(error as? AudioRecorderError, .alreadyRecording)
        }
        XCTAssertEqual(fixture.recorder.capturedSamples(since: 0), [0.1, 0.2])
    }

    func testCaptureBelowMinimumDurationReturnsNoSamples() throws {
        let fixture = AudioRecorderFixture()
        try fixture.recorder.start()
        fixture.append(samples: Array(repeating: 0.1, count: 799))

        XCTAssertTrue(fixture.recorder.stop().isEmpty)
        XCTAssertEqual(fixture.recorder.lastRecordingDuration, 799.0 / 16_000.0)
    }

    func testAccumulationAndIncrementalReadUseOffset() throws {
        let fixture = AudioRecorderFixture()
        try fixture.recorder.start()
        fixture.append(samples: [0.1, 0.2, 0.3, 0.4])

        XCTAssertEqual(fixture.recorder.capturedSamples(since: 2), [0.3, 0.4])
        XCTAssertEqual(fixture.recorder.capturedSamples(since: 10), [])
    }

    func testInputLossDuringRecordingReportsError() async throws {
        let fixture = AudioRecorderFixture()
        try fixture.recorder.start()
        let errorReported = expectation(description: "input loss")
        fixture.recorder.onError = { error in
            XCTAssertEqual(error, .inputUnavailable)
            errorReported.fulfill()
        }

        fixture.observer.sendConfigurationChange()

        await fulfillment(of: [errorReported], timeout: 1)
        XCTAssertEqual(fixture.diagnosticLog.inputLostCount, 1)
    }

    func testConfigurationChangeOutsideRecordingPreparesWithoutCallback() {
        let fixture = AudioRecorderFixture()

        fixture.observer.sendConfigurationChange()

        XCTAssertEqual(fixture.engine.configurationChangeCount, 1)
        XCTAssertEqual(fixture.engine.configurationPreparationRequests, [true])
        XCTAssertEqual(fixture.diagnosticLog.inputLostCount, 0)
    }

    func testSleepResetsEngineAndWakePreparesNextCapture() {
        let fixture = AudioRecorderFixture()
        let initialPrepareCount = fixture.engine.prepareCount

        fixture.observer.sendSystemWillSleep()
        fixture.observer.sendSystemDidWake()

        XCTAssertEqual(fixture.engine.configurationPreparationRequests, [false])
        XCTAssertEqual(fixture.engine.prepareCount, initialPrepareCount + 1)
    }

    func testSleepDuringRecordingReportsInputLoss() async throws {
        let fixture = AudioRecorderFixture()
        try fixture.recorder.start()
        let errorReported = expectation(description: "input loss during sleep")
        fixture.recorder.onError = { error in
            XCTAssertEqual(error, .inputUnavailable)
            errorReported.fulfill()
        }

        fixture.observer.sendSystemWillSleep()

        await fulfillment(of: [errorReported], timeout: 1)
        XCTAssertEqual(fixture.diagnosticLog.inputLostCount, 1)
    }

    func testEnvironmentObserverForwardsPowerNotifications() async {
        let applicationCenter = NotificationCenter()
        let workspaceCenter = NotificationCenter()
        let observer = AudioEnvironmentObserver(
            applicationNotificationCenter: applicationCenter,
            workspaceNotificationCenter: workspaceCenter
        )
        let sleepReported = expectation(description: "system will sleep")
        let wakeReported = expectation(description: "system did wake")
        observer.start(
            permissionChanged: {},
            configurationChanged: {},
            systemWillSleep: { sleepReported.fulfill() },
            systemDidWake: { wakeReported.fulfill() }
        )

        workspaceCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        workspaceCenter.post(name: NSWorkspace.didWakeNotification, object: nil)

        await fulfillment(of: [sleepReported, wakeReported], timeout: 1)
        observer.stop()
    }

    func testEmergencyStopPropagatesTimeoutResult() throws {
        let fixture = AudioRecorderFixture()
        fixture.engine.emergencyStopResult = false
        try fixture.recorder.start()
        fixture.append(samples: [0.5])

        XCTAssertFalse(fixture.emergencyRegistrar.stop(timeout: 0.001))
        XCTAssertEqual(fixture.engine.emergencyStopCount, 1)
        XCTAssertTrue(fixture.recorder.capturedSamples(since: 0).isEmpty)
    }

    func testNoLevelCallbackAfterStop() async throws {
        let fixture = AudioRecorderFixture()
        let callback = expectation(description: "no callback")
        callback.isInverted = true
        fixture.recorder.onLevelUpdate = { _ in callback.fulfill() }
        try fixture.recorder.start()
        _ = fixture.recorder.stop()

        fixture.append(samples: [0.8])

        await fulfillment(of: [callback], timeout: 0.05)
    }

    func testSyntheticConversionProducesMonoSamples() throws {
        let inputFormat = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 2,
            interleaved: false
        ))
        let input = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: 480))
        input.frameLength = 480
        for channelIndex in 0..<2 {
            guard let channel = input.floatChannelData?[channelIndex] else {
                return XCTFail("Canal synthétique indisponible")
            }
            for frame in 0..<480 { channel[frame] = channelIndex == 0 ? 0.5 : -0.25 }
        }
        let accumulator = AudioSampleAccumulator()
        accumulator.beginCapture()
        let converter = try XCTUnwrap(AVAudioSampleConverter(
            inputFormat: inputFormat,
            sampleRate: AudioRecorder.sampleRate
        ))

        converter.convert(input, sink: accumulator)

        let samples = accumulator.finishCapture()
        XCTAssertFalse(samples.isEmpty)
        XCTAssertLessThanOrEqual(samples.count, 200)
    }
}

@MainActor
private final class AudioRecorderFixture {
    let accumulator = AudioSampleAccumulator()
    let engine: FakeAudioCaptureEngine
    let permission: FakeMicrophonePermission
    let observer = FakeAudioEnvironmentObserver()
    let emergencyRegistrar = FakeAudioEmergencyStopRegistrar()
    let diagnosticLog = AudioDiagnosticLogSpy()
    let recorder: AudioRecorder

    init(isAuthorized: Bool = true) {
        permission = FakeMicrophonePermission(isAuthorized: isAuthorized)
        engine = FakeAudioCaptureEngine(accumulator: accumulator)
        recorder = AudioRecorder(
            engine: engine,
            sampleAccumulator: accumulator,
            permissionProvider: permission,
            environmentObserver: observer,
            emergencyStopRegistrar: emergencyRegistrar,
            diagnosticLog: diagnosticLog
        )
    }

    func append(samples: [Float]) {
        samples.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            accumulator.append(baseAddress, count: buffer.count)
        }
    }
}

private final class FakeAudioCaptureEngine: AudioCaptureEngineManaging, @unchecked Sendable {
    private let accumulator: any AudioSampleAccumulating
    private var isRecording = false
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var prepareCount = 0
    private(set) var configurationChangeCount = 0
    private(set) var configurationPreparationRequests: [Bool] = []
    private(set) var emergencyStopCount = 0
    var emergencyStopResult = true

    init(accumulator: any AudioSampleAccumulating) {
        self.accumulator = accumulator
    }

    func start() throws {
        guard !isRecording else { throw AudioRecorderError.alreadyRecording }
        isRecording = true
        startCount += 1
        accumulator.beginCapture()
    }

    func stop() {
        isRecording = false
        stopCount += 1
    }

    func prepareWhenIdle() { prepareCount += 1 }

    func handleConfigurationChange(
        shouldPrepare: Bool,
        completion: @escaping @Sendable (Bool) -> Void
    ) {
        configurationChangeCount += 1
        configurationPreparationRequests.append(shouldPrepare)
        let wasRecording = isRecording
        isRecording = false
        completion(wasRecording)
    }

    func handlePermissionRevocation(
        completion: @escaping @Sendable (Bool) -> Void
    ) {
        let wasRecording = isRecording
        isRecording = false
        completion(wasRecording)
    }

    func emergencyStop(timeout _: TimeInterval) -> Bool {
        emergencyStopCount += 1
        isRecording = false
        return emergencyStopResult
    }
}

private final class FakeMicrophonePermission: MicrophonePermissionProviding, @unchecked Sendable {
    var isAuthorized: Bool
    var statusDescription: String { isAuthorized ? "autorisée" : "refusée" }

    init(isAuthorized: Bool) {
        self.isAuthorized = isAuthorized
    }
}

private final class FakeAudioEnvironmentObserver: AudioEnvironmentObserving, @unchecked Sendable {
    private var permissionChanged: (@Sendable () -> Void)?
    private var configurationChanged: (@Sendable () -> Void)?
    private var systemWillSleep: (@Sendable () -> Void)?
    private var systemDidWake: (@Sendable () -> Void)?

    func start(
        permissionChanged: @escaping @Sendable () -> Void,
        configurationChanged: @escaping @Sendable () -> Void,
        systemWillSleep: @escaping @Sendable () -> Void,
        systemDidWake: @escaping @Sendable () -> Void
    ) {
        self.permissionChanged = permissionChanged
        self.configurationChanged = configurationChanged
        self.systemWillSleep = systemWillSleep
        self.systemDidWake = systemDidWake
    }

    func stop() {
        permissionChanged = nil
        configurationChanged = nil
        systemWillSleep = nil
        systemDidWake = nil
    }

    func sendConfigurationChange() { configurationChanged?() }
    func sendSystemWillSleep() { systemWillSleep?() }
    func sendSystemDidWake() { systemDidWake?() }
}

private final class FakeAudioEmergencyStopRegistrar: AudioEmergencyStopRegistering, @unchecked Sendable {
    private var handler: (@Sendable (TimeInterval) -> Bool)?

    func install(_ handler: @escaping @Sendable (TimeInterval) -> Bool) {
        self.handler = handler
    }

    func stop(timeout: TimeInterval) -> Bool {
        handler?(timeout) ?? true
    }
}

private final class AudioDiagnosticLogSpy: DiagnosticLogging, @unchecked Sendable {
    private(set) var inputLostCount = 0

    func stage(
        _: DiagnosticStage,
        phase _: String,
        duration _: TimeInterval?,
        audioDuration _: TimeInterval?,
        segmentCount _: Int?
    ) {}

    func inputLost() { inputLostCount += 1 }
    func emergencyRecovery(reason _: String) {}
    func emergencyExitAndFlush(reason _: String) {}
    func modelLoadCompleted(duration _: TimeInterval, reusedCompiledCache _: Bool) {}
    func memory(context _: DiagnosticMemoryContext, bytes _: UInt64?) {}
    func memoryPressure(critical _: Bool) {}
    func mainThreadStall(duration _: TimeInterval) {}
    func eventTapDisabled(reason _: String) {}
}
