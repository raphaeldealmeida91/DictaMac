import Foundation
import XCTest
@testable import DictaMac

@MainActor
final class TranscriptionHistoryTests: XCTestCase {
    func testKeepsNewestTwentyEntriesAndPersistsWithOwnerOnlyPermissions() throws {
        let originalSetting = enableHistoryForTest()
        defer { restoreHistorySetting(originalSetting) }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("history.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TranscriptionHistoryStore(fileURL: fileURL)

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

        let reloaded = TranscriptionHistoryStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.entries, store.entries)
    }

    func testDisabledHistoryDoesNotStoreTextAndClearRemovesFile() throws {
        let originalSetting = enableHistoryForTest()
        defer { restoreHistorySetting(originalSetting) }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("history.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TranscriptionHistoryStore(fileURL: fileURL)
        try store.add(text: "à supprimer", targetApplication: "Tests")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        try store.clear()
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))

        UserDefaults.standard.set(false, forKey: HistoryPreferences.enabledKey)
        try store.add(text: "secret", targetApplication: "Tests")
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    private func enableHistoryForTest() -> Any? {
        let original = UserDefaults.standard.object(forKey: HistoryPreferences.enabledKey)
        UserDefaults.standard.set(true, forKey: HistoryPreferences.enabledKey)
        return original
    }

    private func restoreHistorySetting(_ setting: Any?) {
        if let setting {
            UserDefaults.standard.set(setting, forKey: HistoryPreferences.enabledKey)
        } else {
            UserDefaults.standard.removeObject(forKey: HistoryPreferences.enabledKey)
        }
    }
}
