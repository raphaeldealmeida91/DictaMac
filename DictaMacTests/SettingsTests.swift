import ApplicationServices
import AppKit
import Combine
import WhisperKit
import XCTest
@testable import DictaMac

final class SettingsTests: XCTestCase {
    override func tearDown() {
        SafeModeState.setEnabled(false)
        super.tearDown()
    }

    func testDefaultValuesArePreserved() {
        let store = InMemorySettingsStore()
        let transcription = StoredTranscriptionSettings(
            store: store,
            physicalMemory: { StoredTranscriptionSettings.lowMemoryThreshold }
        )
        let cleanup = StoredTextCleanupSettings(
            store: store,
            physicalMemory: { StoredTranscriptionSettings.lowMemoryThreshold }
        )

        XCTAssertEqual(transcription.configuredModel, StoredTranscriptionSettings.defaultModel)
        XCTAssertEqual(transcription.configuredLanguage, "fr")
        XCTAssertEqual(cleanup.configuredEngine, .local)
        XCTAssertEqual(cleanup.configuredModel, StoredTextCleanupSettings.defaultModel)
        XCTAssertEqual(cleanup.configuredLocalModel, StoredTextCleanupSettings.defaultLocalModel)
        XCTAssertEqual(cleanup.cleanupStyle, .polished)
        XCTAssertTrue(cleanup.removeIsolatedGenre)
        XCTAssertEqual(cleanup.localTimeout, StoredTextCleanupSettings.defaultLocalTimeout)
        XCTAssertEqual(cleanup.cloudTimeout, StoredTextCleanupSettings.defaultCloudTimeout)
        XCTAssertTrue(StoredHistorySettings(store: store).isEnabled)
        XCTAssertTrue(StoredFeedbackSoundSettings(store: store).isEnabled)
        let selection = StoredSelectionCorrectionSettings(store: store)
        XCTAssertFalse(selection.isEnabled)
        XCTAssertFalse(selection.isClipboardFallbackEnabled)
        XCTAssertFalse(selection.allowsCloud)
        XCTAssertEqual(selection.excludedBundleIDs, StoredSelectionCorrectionSettings.defaultExcludedBundleIDs)
        XCTAssertEqual(StoredRecordingSettings(store: store).maximumDuration, 120)
        XCTAssertEqual(
            StoredEmergencyHotkeySettings(store: store).configuredModifiers,
            [.maskControl, .maskAlternate, .maskCommand]
        )
    }

    func testLowMemoryDefaultsUseLightModels() {
        let store = InMemorySettingsStore()
        let lowMemory = StoredTranscriptionSettings.lowMemoryThreshold - 1

        XCTAssertEqual(
            StoredTranscriptionSettings(store: store, physicalMemory: { lowMemory }).configuredModel,
            StoredTranscriptionSettings.fallbackModel
        )
        XCTAssertEqual(
            StoredTextCleanupSettings(store: store, physicalMemory: { lowMemory }).configuredLocalModel,
            StoredTextCleanupSettings.lightLocalModel
        )
    }

    func testSafeModeOverridesConfiguredEnginesAndModels() {
        let store = InMemorySettingsStore(values: [
            .transcriptionModel: .string("custom-whisper"),
            .textCleanupEngine: .string(TextCleanupEngine.cloud.rawValue),
            .textCleanupLocalModel: .string("custom-local")
        ])
        SafeModeState.setEnabled(true)

        XCTAssertEqual(
            StoredTranscriptionSettings(store: store).configuredModel,
            StoredTranscriptionSettings.fallbackModel
        )
        let cleanup = StoredTextCleanupSettings(store: store)
        XCTAssertEqual(cleanup.configuredEngine, .fast)
        XCTAssertEqual(cleanup.configuredLocalModel, StoredTextCleanupSettings.lightLocalModel)
    }

    @MainActor
    func testLocalModelActivationBlockedBySafeModePublishesExplicitStatus() async {
        let state = LocalCleanupModelState()
        let safeMode = TestSafeModeController(isEnabled: true)
        let manager = LocalCleanupModelManager(
            settings: TestCleanupSettings(),
            modelState: state,
            modelLoadingGate: TestIdleModelLoadingGate(),
            diagnosticLog: TestDiagnosticLog(),
            safeMode: safeMode
        )

        await manager.activateConfiguredModel()
        await Task.yield()

        XCTAssertEqual(state.status, SafeModeState.localCleanupUnavailableMessage)
        XCTAssertFalse(state.isBusy)
        XCTAssertFalse(state.hasError)
    }

    @MainActor
    func testCleanupModelBadgeDistinguishesInactiveLoadingAndError() {
        let inactive = makeCleanupSettingsViewModel(state: TestCleanupModelState())
        let loading = makeCleanupSettingsViewModel(state: TestCleanupModelState(isBusy: true))
        let error = makeCleanupSettingsViewModel(state: TestCleanupModelState(hasError: true))

        XCTAssertEqual(inactive.modelBadge, .inactive)
        XCTAssertEqual(loading.modelBadge, .loading)
        XCTAssertEqual(error.modelBadge, .error)
    }

    @MainActor
    func testExitSafeModeDisablesItAndRestartsActivation() async throws {
        let safeMode = TestSafeModeController(isEnabled: true)
        let manager = TestCleanupModelManager()
        let viewModel = makeCleanupSettingsViewModel(
            state: TestCleanupModelState(),
            manager: manager,
            safeMode: safeMode
        )

        viewModel.exitSafeMode()
        try await Task.sleep(for: .milliseconds(20))

        let activationCount = await manager.activationCount
        XCTAssertFalse(safeMode.isEnabled)
        XCTAssertFalse(viewModel.isSafeModeEnabled)
        XCTAssertEqual(activationCount, 1)
    }

    @MainActor
    func testBusyModelLoadingGatePublishesWaitingStatus() async throws {
        let state = LocalCleanupModelState()
        let manager = LocalCleanupModelManager(
            settings: TestCleanupSettings(),
            modelState: state,
            modelLoadingGate: TestBusyModelLoadingGate(),
            diagnosticLog: TestDiagnosticLog(),
            safeMode: TestSafeModeController(isEnabled: false)
        )

        await manager.activateConfiguredModel()
        try await Task.sleep(for: .milliseconds(20))

        XCTAssertEqual(state.status, "En attente du chargement du modèle de transcription…")
        XCTAssertTrue(state.isBusy)
        await manager.cancelDownload()
    }

    @MainActor
    func testActivationCoalescesSameModelAndReplacesDifferentModel() async {
        let settings = TestMutableCleanupSettings(modelID: "model-a")
        let gate = TestSuspendingModelLoadingGate()
        let manager = LocalCleanupModelManager(
            settings: settings,
            modelState: LocalCleanupModelState(),
            modelLoadingGate: gate,
            diagnosticLog: TestDiagnosticLog(),
            safeMode: TestSafeModeController(isEnabled: false)
        )

        await manager.activateConfiguredModel()
        let firstActivationStarted = await gate.waitForInvocationCount(1)
        XCTAssertTrue(firstActivationStarted)
        await manager.activateConfiguredModel()
        let countAfterDuplicate = await gate.invocationCount
        let cancellationsAfterDuplicate = await gate.cancellationCount
        XCTAssertEqual(countAfterDuplicate, 1)
        XCTAssertEqual(cancellationsAfterDuplicate, 0)

        settings.setModelID("model-b")
        await manager.activateConfiguredModel()
        let replacementStarted = await gate.waitForInvocationCount(2)
        let previousActivationCancelled = await gate.waitForCancellationCount(1)
        XCTAssertTrue(replacementStarted)
        XCTAssertTrue(previousActivationCancelled)
        let countAfterReplacement = await gate.invocationCount
        XCTAssertEqual(countAfterReplacement, 2)
        await manager.cancelDownload()
    }

    func testFrenchDecodingOptionsFavorDeterministicQuality() {
        let options = WhisperKitTranscriptionService.decodingOptions(
            language: "fr",
            promptTokens: [41, 42]
        )

        XCTAssertEqual(options.language, "fr")
        XCTAssertFalse(options.detectLanguage)
        XCTAssertEqual(options.temperature, 0)
        XCTAssertEqual(options.temperatureIncrementOnFallback, 0.2)
        XCTAssertEqual(options.temperatureFallbackCount, 5)
        XCTAssertTrue(options.usePrefillPrompt)
        XCTAssertTrue(options.skipSpecialTokens)
        XCTAssertFalse(options.withoutTimestamps)
        XCTAssertTrue(options.suppressBlank)
        XCTAssertEqual(options.promptTokens, [41, 42])
        XCTAssertEqual(options.compressionRatioThreshold, 2.4)
        XCTAssertEqual(options.logProbThreshold, -1)
        XCTAssertEqual(options.noSpeechThreshold, 0.6)
        XCTAssertNil(options.chunkingStrategy)
    }

    func testAutomaticLanguageEnablesDetection() {
        let options = WhisperKitTranscriptionService.decodingOptions(
            language: nil,
            promptTokens: nil
        )

        XCTAssertNil(options.language)
        XCTAssertTrue(options.detectLanguage)
    }

    func testWhisperRejectsTooShortAudioBeforeInference() {
        let samples = Array(repeating: Float(0.5), count: 3_999)

        XCTAssertFalse(WhisperKitTranscriptionService.containsAudibleSpeech(samples))
    }

    func testWhisperRejectsDigitalSilenceBeforeInference() {
        let samples = Array(repeating: Float.zero, count: 16_000)

        XCTAssertFalse(WhisperKitTranscriptionService.containsAudibleSpeech(samples))
    }

    func testWhisperAcceptsAudibleAudio() {
        let samples = (0..<16_000).map { index in
            Float(sin(2 * Double.pi * 440 * Double(index) / 16_000) * 0.02)
        }

        XCTAssertTrue(WhisperKitTranscriptionService.containsAudibleSpeech(samples))
    }

    func testWhisperCleanerRejectsObservedCaptionHallucination() {
        XCTAssertEqual(
            WhisperTranscriptionTextCleaner.clean("Sous-titrage Société Radio-Canada, merci."),
            ""
        )
    }

    func testWhisperCleanerKeepsCaptionWordsInsideRealDictation() {
        let dictation = "Je dois vérifier le sous-titrage de Société Radio-Canada demain."

        XCTAssertEqual(WhisperTranscriptionTextCleaner.clean(dictation), dictation)
    }

    @MainActor
    func testSelectionMonitorReadsOnlyMousePropertiesForMouseEvent() throws {
        let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 1,
            clickCount: 2,
            pressure: 0
        ))

        let monitored = GlobalSelectionEventMonitor.MonitoredEvent(event: event)

        XCTAssertEqual(monitored.clickCount, 2)
        XCTAssertEqual(monitored.keyCode, 0)
    }

    @MainActor
    func testSelectionMonitorReadsOnlyKeyboardPropertiesForKeyEvent() throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyUp,
            location: .zero,
            modifierFlags: .shift,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 123
        ))

        let monitored = GlobalSelectionEventMonitor.MonitoredEvent(event: event)

        XCTAssertEqual(monitored.clickCount, 0)
        XCTAssertEqual(monitored.keyCode, 123)
    }

    func testAppVersionDescription() {
        let version = AppVersionInfo(marketingVersion: "1.0", buildNumber: "42")

        XCTAssertEqual(version.description, "Version 1.0 (build 42)")
    }

    func testDictionaryPromptUsesCanonicalTermsInNaturalSentence() {
        let prompt = WhisperKitTranscriptionService.dictionaryPrompt(
            for: ["SFM30", "Prazo Elevator", "devis", "ChatGPT"]
        )

        XCTAssertEqual(
            prompt,
            "La dictée peut contenir notamment SFM30, Prazo Elevator, devis et ChatGPT."
        )
        XCTAssertNil(WhisperKitTranscriptionService.dictionaryPrompt(for: []))
    }

    @MainActor
    func testFirstLaunchAssistantRequiresAuthorizationOrExplicitSkip() {
        let viewModel = makeFirstLaunchViewModel(store: InMemorySettingsStore())

        XCTAssertEqual(viewModel.step, .microphone)
        XCTAssertFalse(viewModel.canContinue)

        viewModel.skipCurrentPermission()

        XCTAssertTrue(viewModel.canContinue)
        viewModel.continueForward()
        XCTAssertEqual(viewModel.step, .inputMonitoring)
    }

    @MainActor
    func testFirstLaunchAssistantPersistsCompletionAfterExplicitChoices() {
        let store = InMemorySettingsStore()
        let viewModel = makeFirstLaunchViewModel(store: store)

        for expectedStep in FirstLaunchStep.allCases.dropLast() {
            XCTAssertEqual(viewModel.step, expectedStep)
            viewModel.skipCurrentPermission()
            viewModel.continueForward()
        }
        viewModel.fnConfigurationConfirmed = true
        viewModel.modelSkipped = true
        viewModel.cleanupModelSkipped = true
        viewModel.dictationTrialSkipped = true

        XCTAssertTrue(viewModel.finish())
        XCTAssertEqual(store.bool(for: .firstLaunchAssistantCompleted), true)
    }

    @MainActor
    private func makeFirstLaunchViewModel(
        store: any SettingsStoring
    ) -> FirstLaunchAssistantViewModel {
        FirstLaunchAssistantViewModel(
            store: store,
            permissions: DeniedPermissionManager(),
            modelState: PreviewTranscriptionModelState(),
            modelLoader: PreviewTranscriptionModelLoader(),
            cleanupModelState: PreviewCleanupModelState(),
            cleanupModelManager: PreviewCleanupModelManager(),
            activity: TestDictationActivity(),
            openKeyboardSettings: {}
        )
    }

    @MainActor
    private func makeCleanupSettingsViewModel(
        state: TestCleanupModelState,
        manager: TestCleanupModelManager = TestCleanupModelManager(),
        safeMode: TestSafeModeController = TestSafeModeController(isEnabled: false)
    ) -> TextCleanupSettingsViewModel {
        TextCleanupSettingsViewModel(
            store: InMemorySettingsStore(),
            state: state,
            manager: manager,
            keyStore: PreviewAPIKeyStore(),
            recommendedLocalModel: StoredTextCleanupSettings.defaultLocalModel,
            isLowMemoryMac: false,
            safeMode: safeMode
        )
    }
}

private final class TestSafeModeController: SafeModeControlling, @unchecked Sendable {
    private let lock = NSLock()
    private var enabled: Bool

    init(isEnabled: Bool) {
        enabled = isEnabled
    }

    var isEnabled: Bool { lock.withLock { enabled } }

    func setEnabled(_ value: Bool) {
        lock.withLock { enabled = value }
    }
}

@MainActor
private final class TestCleanupModelState: LocalCleanupModelStateProviding {
    @Published var status: String
    @Published var downloadProgress: Double?
    @Published var isBusy: Bool
    @Published var isReady: Bool
    @Published var hasError: Bool

    init(isBusy: Bool = false, isReady: Bool = false, hasError: Bool = false) {
        status = "Test"
        downloadProgress = nil
        self.isBusy = isBusy
        self.isReady = isReady
        self.hasError = hasError
    }
}

private actor TestCleanupModelManager: LocalCleanupModelManaging {
    private(set) var activationCount = 0

    func activateConfiguredModel() { activationCount += 1 }
    func approveDownloadAndActivate() {}
    func cancelDownload() {}
    func unload(reason: String) {}
}

private struct TestCleanupSettings: TextCleanupSettings, TextCleanupSettingsWriting {
    let configuredEngine = TextCleanupEngine.local
    let isEnabled = true
    let configuredModel = "test"
    let configuredLocalModel = "test"
    let cleanupStyle = CleanupStyle.correction
    let removeIsolatedGenre = false
    let localTimeout: TimeInterval = 1
    let cloudTimeout: TimeInterval = 1
    let localDownloadApproved = true

    func migrate() {}
    func approveLocalDownload() {}
    func setEngine(_ engine: TextCleanupEngine) {}
}

private final class TestMutableCleanupSettings: TextCleanupSettings, TextCleanupSettingsWriting, @unchecked Sendable {
    private let lock = NSLock()
    private var modelID: String

    init(modelID: String) {
        self.modelID = modelID
    }

    let configuredEngine = TextCleanupEngine.local
    let isEnabled = true
    let configuredModel = "test"
    var configuredLocalModel: String { lock.withLock { modelID } }
    let cleanupStyle = CleanupStyle.correction
    let removeIsolatedGenre = false
    let localTimeout: TimeInterval = 1
    let cloudTimeout: TimeInterval = 1
    let localDownloadApproved = true

    func setModelID(_ value: String) {
        lock.withLock { modelID = value }
    }

    func migrate() {}
    func approveLocalDownload() {}
    func setEngine(_ engine: TextCleanupEngine) {}
}

private struct TestIdleModelLoadingGate: ModelLoadingGating {
    let isLoading = false

    func run<Value: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        try await operation()
    }
}

private struct TestBusyModelLoadingGate: ModelLoadingGating {
    let isLoading = true

    func run<Value: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        try await Task.sleep(for: .seconds(10))
        return try await operation()
    }
}

private final class TestSuspendingModelLoadingGate: ModelLoadingGating, @unchecked Sendable {
    private let recorder = TestActivationGateRecorder()
    let isLoading = false

    var invocationCount: Int {
        get async { await recorder.invocationCount }
    }

    var cancellationCount: Int {
        get async { await recorder.cancellationCount }
    }

    func waitForInvocationCount(_ expectedCount: Int) async -> Bool {
        await waitUntil {
            let count = await self.invocationCount
            return count >= expectedCount
        }
    }

    func waitForCancellationCount(_ expectedCount: Int) async -> Bool {
        await waitUntil {
            let count = await self.cancellationCount
            return count >= expectedCount
        }
    }

    private func waitUntil(_ condition: @escaping @Sendable () async -> Bool) async -> Bool {
        for _ in 0 ..< 100 {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    func run<Value: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        await recorder.recordInvocation()
        do {
            try await Task.sleep(for: .seconds(10))
            return try await operation()
        } catch is CancellationError {
            await recorder.recordCancellation()
            throw CancellationError()
        }
    }
}

private actor TestActivationGateRecorder {
    private(set) var invocationCount = 0
    private(set) var cancellationCount = 0

    func recordInvocation() {
        invocationCount += 1
    }

    func recordCancellation() {
        cancellationCount += 1
    }
}

private final class TestDiagnosticLog: DiagnosticLogging, @unchecked Sendable {
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
    func memory(context _: DiagnosticMemoryContext, bytes _: UInt64?) {}
    func memoryPressure(critical _: Bool) {}
    func mainThreadStall(duration _: TimeInterval) {}
    func eventTapDisabled(reason _: String) {}
}

@MainActor
private final class DeniedPermissionManager: PermissionManaging {
    @Published private var revision = false

    func status(for permission: AppPermission) -> PermissionStatus { .denied }
    func request(_ permission: AppPermission) async -> PermissionStatus { .denied }
    func startPeriodicRefresh() { revision.toggle() }
    func stopPeriodicRefresh() {}
    func openSystemSettings(for permission: AppPermission) {}
}

@MainActor
private final class TestDictationActivity: DictationActivityProviding {
    @Published var state: DictationState = .idle
}
