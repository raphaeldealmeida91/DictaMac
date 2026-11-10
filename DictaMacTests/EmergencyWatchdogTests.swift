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
                stage: stage,
                stageStartedAt: 0,
                physicalFootprint: nil
            )
            XCTAssertEqual(policy.evaluate(input), .recover(reason: reason))
        }
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

    func testRecordingDurationIsClamped() {
        XCTAssertEqual(RecordingDurationPreferences.clamped(1), 10)
        XCTAssertEqual(RecordingDurationPreferences.clamped(120), 120)
        XCTAssertEqual(RecordingDurationPreferences.clamped(1_000), 600)
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
        memory: UInt64? = nil
    ) -> EmergencyWatchdogPolicy.Snapshot {
        EmergencyWatchdogPolicy.Snapshot(
            now: now,
            mainHeartbeat: heartbeat,
            stage: nil,
            stageStartedAt: nil,
            physicalFootprint: memory
        )
    }
}
