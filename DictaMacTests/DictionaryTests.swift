import Foundation
import XCTest
@testable import DictaMac

final class DictionaryTests: XCTestCase {
    func testCorrectsExactVariantsWithoutChangingLongerWords() {
        let entries = [DictionaryEntry(canonical: "devis", variants: ["de vie"])]

        XCTAssertEqual(
            DictionaryCorrector.correct("Le de vie est prêt.", entries: entries),
            "Le devis est prêt."
        )
        XCTAssertEqual(
            DictionaryCorrector.correct("La devise est stable.", entries: entries),
            "La devise est stable."
        )
    }

    func testCorrectsAlphanumericVariantsAndPreservesEveryOccurrence() {
        let entry = DictionaryEntry.defaults[0]

        XCTAssertEqual(DictionaryCorrector.correct("SFM 30", entries: [entry]), "SFM30")
        XCTAssertEqual(DictionaryCorrector.correct("s f m trente", entries: [entry]), "SFM30")
        XCTAssertEqual(DictionaryCorrector.correct("sfm30", entries: [entry]), "SFM30")
        XCTAssertEqual(
            DictionaryCorrector.correct("sfm30 sfm30 sfm30", entries: [entry]),
            "SFM30 SFM30 SFM30"
        )
    }

    func testCorrectsCaseAccentsAndOneCharacterTransposition() {
        let entries = [
            DictionaryEntry(canonical: "ChatGPT", variants: ["chât gpt"]),
            DictionaryEntry(canonical: "devis", variants: [])
        ]

        XCTAssertEqual(DictionaryCorrector.correct("chât gpt", entries: entries), "ChatGPT")
        XCTAssertEqual(DictionaryCorrector.correct("devsi", entries: entries), "devis")
        XCTAssertEqual(DictionaryCorrector.correct("devi", entries: entries), "devis")
        XCTAssertEqual(DictionaryCorrector.correct("chatgpt répond", entries: entries), "ChatGPT répond")
    }

    func testDoesNotFuzzyCorrectShortTerms() {
        let entries = [DictionaryEntry(canonical: "API", variants: [])]

        XCTAssertEqual(DictionaryCorrector.correct("AIP", entries: entries), "AIP")
        XCTAssertEqual(DictionaryCorrector.correct("api", entries: entries), "API")
    }

    func testStoredDictionarySeedsAndPersistsJSONThroughSettingsPath() throws {
        let settings = InMemorySettingsStore()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let storage = JSONDictionaryStore(
            settingsStore: settings,
            directoryProvider: { directory }
        )
        let dictionary = StoredPersonalDictionary(storage: storage)

        XCTAssertEqual(dictionary.entries(), DictionaryEntry.defaults)
        let replacement = [DictionaryEntry(canonical: "DictaMac", variants: ["dicta mac"])]
        try dictionary.replaceEntries(replacement)

        XCTAssertEqual(StoredPersonalDictionary(storage: storage).entries(), replacement)
        XCTAssertEqual(
            settings.string(for: .personalDictionaryPath),
            directory.appendingPathComponent("personal-dictionary.json").path
        )

        try dictionary.replaceEntries([])
        XCTAssertTrue(StoredPersonalDictionary(storage: storage).entries().isEmpty)
    }

    func testQuickAddTrimsAndRejectsCaseOrAccentDuplicates() throws {
        let storage = InMemoryDictionaryStorage(entries: [])
        let dictionary = StoredPersonalDictionary(storage: storage, seedEntries: [])

        XCTAssertTrue(try dictionary.addCanonicalTerm("  Dévis  "))
        XCTAssertFalse(try dictionary.addCanonicalTerm("devis"))
        XCTAssertEqual(dictionary.entries(), [DictionaryEntry(canonical: "Dévis", variants: [])])
    }
}

private final class InMemoryDictionaryStorage: DictionaryStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var storedEntries: [DictionaryEntry]?

    init(entries: [DictionaryEntry]?) {
        storedEntries = entries
    }

    func load() throws -> [DictionaryEntry]? { lock.withLock { storedEntries } }
    func save(_ entries: [DictionaryEntry]) throws { lock.withLock { storedEntries = entries } }
}
