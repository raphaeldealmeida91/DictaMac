import Foundation

@MainActor
protocol DictionaryFileManaging {
    func importEntries() throws -> [DictionaryEntry]?
    func export(_ entries: [DictionaryEntry]) throws -> Bool
}
