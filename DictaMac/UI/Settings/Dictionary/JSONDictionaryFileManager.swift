import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
struct JSONDictionaryFileManager: DictionaryFileManaging {
    func importEntries() throws -> [DictionaryEntry]? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        return try JSONDecoder().decode([DictionaryEntry].self, from: Data(contentsOf: url))
    }

    func export(_ entries: [DictionaryEntry]) throws -> Bool {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "dictamac-dictionary.json"
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(entries).write(to: url, options: .atomic)
        return true
    }
}
