import Foundation

final class StoredPersonalDictionary: PersonalDictionary, @unchecked Sendable {
    private let storage: any DictionaryStoring
    private let lock = NSLock()
    private var cachedEntries: [DictionaryEntry]

    init(
        storage: any DictionaryStoring,
        seedEntries: [DictionaryEntry] = DictionaryEntry.defaults
    ) {
        self.storage = storage
        let storedEntries: [DictionaryEntry]?
        do {
            storedEntries = try storage.load()
        } catch {
            storedEntries = nil
        }
        cachedEntries = storedEntries ?? seedEntries
        if storedEntries == nil {
            try? storage.save(seedEntries)
        }
    }

    func entries() -> [DictionaryEntry] {
        lock.withLock { cachedEntries }
    }

    func replaceEntries(_ entries: [DictionaryEntry]) throws {
        try lock.withLock {
            try storage.save(entries)
            cachedEntries = entries
        }
    }

    @discardableResult
    func addCanonicalTerm(_ canonical: String) throws -> Bool {
        let term = canonical.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return false }
        return try lock.withLock {
            guard !cachedEntries.contains(where: { Self.matches($0.canonical, term) }) else { return false }
            let updated = cachedEntries + [DictionaryEntry(canonical: term, variants: [])]
            try storage.save(updated)
            cachedEntries = updated
            return true
        }
    }

    private static func matches(_ lhs: String, _ rhs: String) -> Bool {
        lhs.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            == rhs.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
