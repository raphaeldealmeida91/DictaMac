import Foundation
import XCTest
@testable import DictaMac

@MainActor
final class DictionarySettingsTests: XCTestCase {
    func testViewModelAddsEditsDeletesAndPersistsEntries() {
        let dictionary = DictionaryMemoryStore(entries: [])
        let viewModel = DictionarySettingsViewModel(
            dictionary: dictionary,
            fileManager: DictionaryFileManagerSpy()
        )

        viewModel.addEntry()
        viewModel.drafts[0].canonical = " ChatGPT "
        viewModel.drafts[0].variants = "chat gpt, achat de gpt, chat gpt"
        viewModel.save()

        XCTAssertEqual(dictionary.entries(), [DictionaryEntry(
            canonical: "ChatGPT",
            variants: ["achat de gpt", "chat gpt"]
        )])
        XCTAssertEqual(viewModel.statusMessage, "Dictionnaire enregistré")

        viewModel.removeEntry(id: viewModel.drafts[0].id)
        viewModel.save()
        XCTAssertTrue(dictionary.entries().isEmpty)
    }

    func testViewModelRejectsDuplicateCanonicalTerms() {
        let dictionary = DictionaryMemoryStore(entries: [])
        let viewModel = DictionarySettingsViewModel(
            dictionary: dictionary,
            fileManager: DictionaryFileManagerSpy()
        )
        viewModel.drafts = [
            DictionaryEntryDraft(canonical: "Devis"),
            DictionaryEntryDraft(canonical: "dévis")
        ]

        viewModel.save()

        XCTAssertTrue(dictionary.entries().isEmpty)
        XCTAssertEqual(viewModel.statusMessage, "Chaque terme doit avoir une forme correcte unique.")
    }

    func testImportAndExportUseInjectedFileManager() {
        let imported = [DictionaryEntry(canonical: "SFM30", variants: ["SFM 30"])]
        let dictionary = DictionaryMemoryStore(entries: [])
        let files = DictionaryFileManagerSpy(importedEntries: imported)
        let viewModel = DictionarySettingsViewModel(dictionary: dictionary, fileManager: files)

        viewModel.importJSON()
        viewModel.exportJSON()

        XCTAssertEqual(dictionary.entries(), imported)
        XCTAssertEqual(files.exportedEntries, imported)
    }

    func testHistoryWordExtractorPreservesOrderAndRemovesDuplicates() {
        XCTAssertEqual(
            HistoryWordExtractor.words(in: "ChatGPT prépare le devis, puis chatgpt relit Prazo-Elevator."),
            ["ChatGPT", "prépare", "le", "devis", "puis", "relit", "Prazo-Elevator"]
        )
    }
}

private final class DictionaryMemoryStore: PersonalDictionary, @unchecked Sendable {
    private let lock = NSLock()
    private var storedEntries: [DictionaryEntry]

    init(entries: [DictionaryEntry]) {
        storedEntries = entries
    }

    func entries() -> [DictionaryEntry] { lock.withLock { storedEntries } }
    func replaceEntries(_ entries: [DictionaryEntry]) throws {
        lock.withLock { storedEntries = entries }
    }
    func addCanonicalTerm(_ canonical: String) throws -> Bool {
        lock.withLock { storedEntries.append(DictionaryEntry(canonical: canonical, variants: [])) }
        return true
    }
}

@MainActor
private final class DictionaryFileManagerSpy: DictionaryFileManaging {
    let importedEntries: [DictionaryEntry]?
    private(set) var exportedEntries: [DictionaryEntry]?

    init(importedEntries: [DictionaryEntry]? = nil) {
        self.importedEntries = importedEntries
    }

    func importEntries() throws -> [DictionaryEntry]? { importedEntries }
    func export(_ entries: [DictionaryEntry]) throws -> Bool {
        exportedEntries = entries
        return true
    }
}
