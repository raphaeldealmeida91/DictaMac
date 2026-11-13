import XCTest
@testable import DictaMac

final class EmergencyWatchdogTests: XCTestCase {
    private let gibibyte = UInt64(1_024 * 1_024 * 1_024)

    func testMainThreadStallEscalatesThenExitsAfterGracePeriod() {
        var policy = makePolicy()
        let first = snapshot(now: 6, heartbeat: 0)

        XCTAssertEqual(policy.evaluate(first), .recover(reason: "main_thread_stall"))
        XCTAssertEqual(policy.evaluate(snapshot(now: 8.9, heartbeat: 0)), .none)
        XCTAssertEqual(policy.evaluate(snapshot(now: 9.1, heartbeat: 0)), .exit(reason: "main_thread_stall"))
    }

    func testStageBudgetsUseSimulatedClock() {
        let cases: [(EmergencyStage, TimeInterval, String)] = [
            (.finalTranscription, 8.1, "stage_timeout_final_transcription"),
            (.cleanup, 10.1, "stage_timeout_cleanup"),
            (.injection, 2.1, "stage_timeout_injection")
        ]

        for (stage, elapsed, reason) in cases {
            var policy = makePolicy()
            let input = EmergencyWatchdogPolicy.Snapshot(
                now: elapsed,
                mainHeartbeat: elapsed,
                mainThreadMonitoringActive: true,
                isSleeping: false,
                lastWakeAt: nil,
                stage: stage,
                stageStartedAt: 0,
                modelIsLoading: false,
                physicalFootprint: nil
            )
            XCTAssertEqual(policy.evaluate(input), .recover(reason: reason))
        }
    }

    func testFinalTranscriptionDoesNotTimeoutWhileModelIsLoading() {
        var policy = makePolicy()
        let input = EmergencyWatchdogPolicy.Snapshot(
            now: 30,
            mainHeartbeat: 30,
            mainThreadMonitoringActive: true,
            isSleeping: false,
            lastWakeAt: nil,
            stage: .finalTranscription,
            stageStartedAt: 0,
            modelIsLoading: true,
            physicalFootprint: nil
        )

        XCTAssertEqual(policy.evaluate(input), .none)
        XCTAssertEqual(
            policy.evaluate(EmergencyWatchdogPolicy.Snapshot(
                now: 30.1,
                mainHeartbeat: 30.1,
                mainThreadMonitoringActive: true,
                isSleeping: false,
                lastWakeAt: nil,
                stage: .finalTranscription,
                stageStartedAt: 0,
                modelIsLoading: false,
                physicalFootprint: nil
            )),
            .none
        )
        XCTAssertEqual(
            policy.evaluate(EmergencyWatchdogPolicy.Snapshot(
                now: 38.2,
                mainHeartbeat: 38.2,
                mainThreadMonitoringActive: true,
                isSleeping: false,
                lastWakeAt: nil,
                stage: .finalTranscription,
                stageStartedAt: 0,
                modelIsLoading: false,
                physicalFootprint: nil
            )),
            .recover(reason: "stage_timeout_final_transcription")
        )
    }

    func testMemoryLimitIsLowerOfHalfRAMAndSixGiB() {
        let lowMemory = EmergencyWatchdogPolicy.Configuration(physicalMemory: 8 * gibibyte)
        let highMemory = EmergencyWatchdogPolicy.Configuration(physicalMemory: 32 * gibibyte)

        XCTAssertEqual(lowMemory.memoryLimit, 4 * gibibyte)
        XCTAssertEqual(highMemory.memoryLimit, 6 * gibibyte)

        var policy = EmergencyWatchdogPolicy(configuration: lowMemory)
        XCTAssertEqual(
            policy.evaluate(snapshot(now: 1, heartbeat: 1, memory: 4 * gibibyte + 1)),
            .recover(reason: "memory_limit")
        )
    }

    func testHealthySnapshotResetsEscalation() {
        var policy = makePolicy()
        _ = policy.evaluate(snapshot(now: 6, heartbeat: 0))
        XCTAssertEqual(policy.evaluate(snapshot(now: 7, heartbeat: 7)), .none)
        XCTAssertNil(policy.recoveryStartedAt)
        XCTAssertNil(policy.recoveryReason)
    }

    func testMainThreadStallIsIgnoredWhileInactive() {
        var policy = makePolicy()

        XCTAssertEqual(
            policy.evaluate(snapshot(now: 30, heartbeat: 0, isActive: false)),
            .none
        )
    }

    func testInjectedClockIgnoresSleepAndTenSecondsAfterWake() {
        let clock = TestEmergencyClock(now: 0)
        let runtime = EmergencyRuntime(clock: MonotonicClock(now: { clock.now }))
        var policy = makePolicy()
        runtime.setIdle(false)
        runtime.heartbeat()
        clock.now = 30
        runtime.willSleep()
        XCTAssertEqual(policy.evaluate(snapshot(from: runtime)), .none)

        clock.now = 300
        runtime.didWake()
        clock.now = 309.9
        XCTAssertEqual(policy.evaluate(snapshot(from: runtime)), .none)

        clock.now = 316
        XCTAssertEqual(
            policy.evaluate(snapshot(from: runtime)),
            .recover(reason: "main_thread_stall")
        )
    }

    func testRecordingDurationIsClamped() {
        XCTAssertEqual(StoredRecordingSettings.clamped(1), 10)
        XCTAssertEqual(StoredRecordingSettings.clamped(120), 120)
        XCTAssertEqual(StoredRecordingSettings.clamped(1_000), 600)
    }

    func testSafeModeMarkerDetectsAbnormalExitAndCleanExit() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = SafeModeManager(markerURL: directory.appendingPathComponent("running.marker"))

        XCTAssertFalse(try manager.detectAbnormalExitAndMarkRunning())
        XCTAssertTrue(try manager.detectAbnormalExitAndMarkRunning())
        try manager.markCleanExit()
        XCTAssertFalse(FileManager.default.fileExists(atPath: manager.markerURL.path))
    }

    private func makePolicy() -> EmergencyWatchdogPolicy {
        EmergencyWatchdogPolicy(configuration: .init(physicalMemory: 16 * gibibyte))
    }

    private func snapshot(
        now: TimeInterval,
        heartbeat: TimeInterval,
        memory: UInt64? = nil,
        isActive: Bool = true
    ) -> EmergencyWatchdogPolicy.Snapshot {
        EmergencyWatchdogPolicy.Snapshot(
            now: now,
            mainHeartbeat: heartbeat,
            mainThreadMonitoringActive: isActive,
            isSleeping: false,
            lastWakeAt: nil,
            stage: nil,
            stageStartedAt: nil,
            modelIsLoading: false,
            physicalFootprint: memory
        )
    }

    private func snapshot(from runtime: EmergencyRuntime) -> EmergencyWatchdogPolicy.Snapshot {
        let value = runtime.snapshot()
        return EmergencyWatchdogPolicy.Snapshot(
            now: runtime.currentTime(),
            mainHeartbeat: value.mainHeartbeat,
            mainThreadMonitoringActive: value.mainThreadMonitoringActive,
            isSleeping: value.isSleeping,
            lastWakeAt: value.lastWakeAt,
            stage: value.stage,
            stageStartedAt: value.stageStartedAt,
            modelIsLoading: false,
            physicalFootprint: nil
        )
    }
}

private final class TestEmergencyClock: @unchecked Sendable {
    var now: TimeInterval
    init(now: TimeInterval) { self.now = now }
}
