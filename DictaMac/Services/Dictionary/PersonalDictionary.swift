protocol PersonalDictionary: Sendable {
    func entries() -> [DictionaryEntry]
    func replaceEntries(_ entries: [DictionaryEntry]) throws
    @discardableResult func addCanonicalTerm(_ canonical: String) throws -> Bool
}
