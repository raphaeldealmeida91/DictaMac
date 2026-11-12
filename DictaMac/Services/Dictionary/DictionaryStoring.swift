protocol DictionaryStoring: Sendable {
    func load() throws -> [DictionaryEntry]?
    func save(_ entries: [DictionaryEntry]) throws
}
