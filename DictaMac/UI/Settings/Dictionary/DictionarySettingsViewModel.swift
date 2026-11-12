import Combine
import Foundation

@MainActor
final class DictionarySettingsViewModel: ObservableObject {
    @Published var drafts: [DictionaryEntryDraft]
    @Published private(set) var statusMessage: String?

    private let dictionary: any PersonalDictionary
    private let fileManager: any DictionaryFileManaging

    init(
        dictionary: any PersonalDictionary,
        fileManager: any DictionaryFileManaging = JSONDictionaryFileManager()
    ) {
        self.dictionary = dictionary
        self.fileManager = fileManager
        drafts = dictionary.entries().map(DictionaryEntryDraft.init(entry:))
    }

    func addEntry() {
        drafts.append(DictionaryEntryDraft())
        statusMessage = nil
    }

    func removeEntry(id: UUID) {
        drafts.removeAll { $0.id == id }
        statusMessage = nil
    }

    func save() {
        guard let entries = validatedEntries() else {
            statusMessage = "Chaque terme doit avoir une forme correcte unique."
            return
        }
        do {
            try dictionary.replaceEntries(entries)
            statusMessage = "Dictionnaire enregistré"
        } catch {
            statusMessage = "Enregistrement impossible"
        }
    }

    func importJSON() {
        do {
            guard let entries = try fileManager.importEntries() else { return }
            try dictionary.replaceEntries(entries)
            drafts = entries.map(DictionaryEntryDraft.init(entry:))
            statusMessage = "Dictionnaire importé"
        } catch {
            statusMessage = "Import JSON impossible"
        }
    }

    func exportJSON() {
        guard let entries = validatedEntries() else {
            statusMessage = "Corrigez les termes avant l’export"
            return
        }
        do {
            if try fileManager.export(entries) { statusMessage = "Dictionnaire exporté" }
        } catch {
            statusMessage = "Export JSON impossible"
        }
    }

    func reload() {
        drafts = dictionary.entries().map(DictionaryEntryDraft.init(entry:))
    }

    private func validatedEntries() -> [DictionaryEntry]? {
        let entries = drafts.compactMap(Self.entry(from:))
        guard entries.count == drafts.count else { return nil }
        let keys = entries.map { Self.normalized($0.canonical) }
        guard Set(keys).count == keys.count else { return nil }
        return entries
    }

    private static func entry(from draft: DictionaryEntryDraft) -> DictionaryEntry? {
        let canonical = draft.canonical.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !canonical.isEmpty else { return nil }
        let variants = draft.variants
            .components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return DictionaryEntry(canonical: canonical, variants: Array(Set(variants)).sorted())
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
