import Foundation
import XCTest
@testable import DictaMac

@MainActor
final class TranscriptionHistoryTests: XCTestCase {
    func testKeepsNewestTwentyEntriesAndPersistsWithOwnerOnlyPermissions() throws {
        let settingsStore = InMemorySettingsStore(values: [.historyEnabled: .bool(true)])
        let settings = StoredHistorySettings(store: settingsStore)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("history.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TranscriptionHistoryStore(fileURL: fileURL, settings: settings)

        for index in 0..<25 {
            try store.add(
                text: "dictée \(index)",
                date: Date(timeIntervalSince1970: TimeInterval(index)),
                targetApplication: "Tests"
            )
        }

        XCTAssertEqual(store.entries.count, 20)
        XCTAssertEqual(store.entries.first?.text, "dictée 24")
        XCTAssertEqual(store.entries.last?.text, "dictée 5")
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)

        let reloaded = TranscriptionHistoryStore(fileURL: fileURL, settings: settings)
        XCTAssertEqual(reloaded.entries, store.entries)
    }

    func testDisabledHistoryDoesNotStoreTextAndClearRemovesFile() throws {
        let settingsStore = InMemorySettingsStore(values: [.historyEnabled: .bool(true)])
        let settings = StoredHistorySettings(store: settingsStore)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("history.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TranscriptionHistoryStore(fileURL: fileURL, settings: settings)
        try store.add(text: "à supprimer", targetApplication: "Tests")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        try store.clear()
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))

        settingsStore.set(.bool(false), for: .historyEnabled)
        try store.add(text: "secret", targetApplication: "Tests")
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testPersistsRawAndCleanedTextForComparison() throws {
        let settingsStore = InMemorySettingsStore(values: [.historyEnabled: .bool(true)])
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("history.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TranscriptionHistoryStore(
            fileURL: fileURL,
            settings: StoredHistorySettings(store: settingsStore)
        )

        try store.add(
            text: "Texte nettoyé.",
            rawText: "texte brut",
            targetApplication: "Tests"
        )

        let reloaded = TranscriptionHistoryStore(
            fileURL: fileURL,
            settings: StoredHistorySettings(store: settingsStore)
        )
        XCTAssertEqual(reloaded.entries.first?.text, "Texte nettoyé.")
        XCTAssertEqual(reloaded.entries.first?.rawText, "texte brut")
    }

}
