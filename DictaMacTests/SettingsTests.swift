import ApplicationServices
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
