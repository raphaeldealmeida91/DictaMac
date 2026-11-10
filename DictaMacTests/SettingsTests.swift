import ApplicationServices
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
}
