import ApplicationServices
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
        XCTAssertEqual(transcription.vocabulary, "")
        XCTAssertEqual(cleanup.configuredEngine, .fast)
        XCTAssertEqual(cleanup.configuredModel, StoredTextCleanupSettings.defaultModel)
        XCTAssertEqual(cleanup.configuredLocalModel, StoredTextCleanupSettings.defaultLocalModel)
        XCTAssertTrue(cleanup.removeIsolatedGenre)
        XCTAssertEqual(cleanup.localTimeout, StoredTextCleanupSettings.defaultLocalTimeout)
        XCTAssertTrue(StoredHistorySettings(store: store).isEnabled)
        XCTAssertTrue(StoredFeedbackSoundSettings(store: store).isEnabled)
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

    func testVocabularyPromptContainsOnlyNormalizedTerms() {
        let prompt = WhisperKitTranscriptionService.vocabularyPrompt(
            for: " WhisperKit,\n DictaMac ,, SwiftUI "
        )

        XCTAssertEqual(prompt, "WhisperKit, DictaMac, SwiftUI")
        XCTAssertNil(WhisperKitTranscriptionService.vocabularyPrompt(for: " \n, "))
    }
}
