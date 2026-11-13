import XCTest
@testable import DictaMac

final class LocalModelLifecycleTests: XCTestCase {
    func testModelUnloadsAfterInactivityDelay() async {
        let clock = TestInactivityClock()
        let recorder = UnloadRecorder()
        let policy = makePolicy(clock: clock, timeout: 300)

        policy.modelBecameReady { await recorder.record() }
        await clock.waitUntilScheduled()
        await clock.advance()
        await recorder.waitForUnload()

        let unloadCount = await recorder.count
        XCTAssertEqual(unloadCount, 1)
    }

    func testModelDoesNotUnloadDuringCorrection() async {
        let clock = TestInactivityClock()
        let recorder = UnloadRecorder()
        let policy = makePolicy(clock: clock, timeout: 300)
        policy.modelBecameReady { await recorder.record() }
        await clock.waitUntilScheduled()

        policy.activityStarted()
        await clock.advance()
        let countDuringCorrection = await recorder.count
        XCTAssertEqual(countDuringCorrection, 0)

        policy.activityEnded { await recorder.record() }
        await clock.waitUntilScheduled()
        await clock.advance()
        await recorder.waitForUnload()
        let countAfterCorrection = await recorder.count
        XCTAssertEqual(countAfterCorrection, 1)
    }

    func testLocalCorrectionReloadsModelAutomatically() async throws {
        let generator = ReloadingLocalGenerator()
        let service = ConfiguredSelectionCorrectionService(
            selectionSettings: LifecycleSelectionSettings(),
            cleanupSettings: LifecycleCleanupSettings(),
            localGenerator: generator,
            cloudGenerator: LifecycleCloudGenerator()
        )

        let requiresPreparation = await service.requiresPreparation()
        XCTAssertTrue(requiresPreparation)
        let execution = try await service.correctWithMetrics(
            "Les enfant jouent dans le jardin.",
            dictionary: []
        )

        let prepareCount = await generator.prepareCount
        let generateCount = await generator.generateCount
        XCTAssertEqual(prepareCount, 1)
        XCTAssertEqual(generateCount, 1)
        XCTAssertFalse(execution.modelAlreadyLoaded)
        XCTAssertEqual(execution.engine, .local)
    }

    func testNeverDoesNotScheduleUnload() async {
        let clock = TestInactivityClock()
        let recorder = UnloadRecorder()
        let policy = makePolicy(clock: clock, timeout: nil)

        policy.modelBecameReady { await recorder.record() }

        let scheduledCount = await clock.scheduledCount
        let unloadCount = await recorder.count
        XCTAssertEqual(scheduledCount, 0)
        XCTAssertEqual(unloadCount, 0)
    }

    func testStoredDelayDefaultsToFiveMinutesAndSupportsNever() {
        let store = InMemorySettingsStore()
        let settings = StoredTextCleanupSettings(store: store)

        XCTAssertEqual(settings.localModelInactivityTimeout, 300)

        store.set(.double(LocalModelInactivityDelay.never.rawValue), for: .textCleanupLocalModelInactivityDelay)
        XCTAssertNil(settings.localModelInactivityTimeout)
    }

    @MainActor
    func testPreparationPresentationUsesDedicatedState() {
        let viewModel = SelectionCorrectionViewModel(
            replacer: LifecycleSelectionReplacer(),
            clipboard: LifecycleClipboard()
        )

        viewModel.presentPreparing {}

        XCTAssertEqual(viewModel.state, .preparing)
    }

    private func makePolicy(
        clock: TestInactivityClock,
        timeout: TimeInterval?
    ) -> DefaultLocalModelInactivityPolicy {
        DefaultLocalModelInactivityPolicy(clock: clock, timeout: { timeout })
    }
}

private actor TestInactivityClock: InactivityClock {
    private var sleepers: [UUID: CheckedContinuation<Void, Error>] = [:]
    private var schedulingWaiters: [CheckedContinuation<Void, Never>] = []

    var scheduledCount: Int { sleepers.count }

    func sleep(for duration: Duration) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                sleepers[id] = continuation
                let waiters = schedulingWaiters
                schedulingWaiters.removeAll()
                waiters.forEach { $0.resume() }
            }
        } onCancel: {
            Task { await self.cancel(id: id) }
        }
    }

    func waitUntilScheduled() async {
        guard sleepers.isEmpty else { return }
        await withCheckedContinuation { schedulingWaiters.append($0) }
    }

    func advance() {
        let continuations = Array(sleepers.values)
        sleepers.removeAll()
        continuations.forEach { $0.resume() }
    }

    private func cancel(id: UUID) {
        sleepers.removeValue(forKey: id)?.resume(throwing: CancellationError())
    }
}

private actor UnloadRecorder {
    private(set) var count = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func record() {
        count += 1
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }

    func waitForUnload() async {
        guard count == 0 else { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}

private actor ReloadingLocalGenerator: LocalTextGenerating {
    private var ready = false
    private(set) var prepareCount = 0
    private(set) var generateCount = 0

    var isReady: Bool { ready }

    func prepare() async throws {
        prepareCount += 1
        ready = true
    }

    func generate(text: String, messages: [[String: String]], maxTokens: Int) async throws -> String {
        generateCount += 1
        return "Les enfants jouent dans le jardin."
    }
}

private struct LifecycleCloudGenerator: TextGenerating {
    func generate(text: String, messages: [[String: String]], maxTokens: Int) async throws -> String {
        text
    }
}

private struct LifecycleSelectionSettings: SelectionCorrectionSettings {
    let isEnabled = true
    let excludedBundleIDs: Set<String> = []
    let isClipboardFallbackEnabled = true
    let allowsCloud = false
}

private struct LifecycleCleanupSettings: TextCleanupSettings {
    let configuredEngine = TextCleanupEngine.local
    let isEnabled = true
    let configuredModel = "cloud"
    let configuredLocalModel = "local"
    let cleanupStyle = CleanupStyle.correction
    let removeIsolatedGenre = false
    let localTimeout: TimeInterval = 8
    let cloudTimeout: TimeInterval = 8
    let localDownloadApproved = true
}

@MainActor
private final class LifecycleSelectionReplacer: SelectionReplacing {
    func replace(
        _ correction: SelectionCorrection,
        for snapshot: SelectionSnapshot
    ) -> SelectionReplacementOutcome {
        .replaced
    }
}

@MainActor
private final class LifecycleClipboard: SelectionClipboardCopying {
    func copy(_ text: String) {}
}
