import Foundation
import XCTest
@testable import DictaMac

final class SharedServicesInjectionTests: XCTestCase {
    func testModelLoadingGateSerializesConcurrentOperations() async throws {
        let gate = ModelLoadingGate()
        let tracker = ConcurrentOperationTracker()

        async let first: Void = gate.run {
            await tracker.enter()
            try await Task.sleep(for: .milliseconds(30))
            await tracker.leave()
        }
        async let second: Void = gate.run {
            await tracker.enter()
            try await Task.sleep(for: .milliseconds(10))
            await tracker.leave()
        }

        _ = try await (first, second)
        let maximum = await tracker.maximumConcurrentOperations
        XCTAssertEqual(maximum, 1)
    }

    func testMemoryDiagnosticsUsesInjectedLog() {
        let log = DiagnosticLogSpy()

        ProcessMemoryDiagnostics.logFootprint(.startup, diagnosticLog: log)

        XCTAssertEqual(log.memoryContexts, [.startup])
    }
}

private actor ConcurrentOperationTracker {
    private var activeOperations = 0
    private(set) var maximumConcurrentOperations = 0

    func enter() {
        activeOperations += 1
        maximumConcurrentOperations = max(maximumConcurrentOperations, activeOperations)
    }

    func leave() {
        activeOperations -= 1
    }
}

private final class DiagnosticLogSpy: DiagnosticLogging, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var memoryContexts: [DiagnosticMemoryContext] = []

    func stage(
        _: DiagnosticStage,
        phase _: String,
        duration _: TimeInterval?,
        audioDuration _: TimeInterval?,
        segmentCount _: Int?
    ) {}

    func inputLost() {}
    func emergencyRecovery(reason _: String) {}
    func emergencyExitAndFlush(reason _: String) {}
    func modelLoadCompleted(duration _: TimeInterval, reusedCompiledCache _: Bool) {}
    func memoryPressure(critical _: Bool) {}
    func mainThreadStall(duration _: TimeInterval) {}
    func eventTapDisabled(reason _: String) {}

    func memory(context: DiagnosticMemoryContext, bytes _: UInt64?) {
        lock.withLock { memoryContexts.append(context) }
    }
}
