import AppKit
import Foundation

struct TranscriptionHistoryEntry: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let text: String
    let rawText: String?
    let date: Date
    let targetApplication: String

    init(
        id: UUID = UUID(),
        text: String,
        rawText: String? = nil,
        date: Date,
        targetApplication: String
    ) {
        self.id = id
        self.text = text
        self.rawText = rawText
        self.date = date
        self.targetApplication = targetApplication
    }
}

@MainActor
final class TranscriptionHistoryStore: ObservableObject {
    static let maximumEntryCount = 20

    @Published private(set) var entries: [TranscriptionHistoryEntry] = []

    private let fileURL: URL
    private let fileManager: FileManager
    private let settings: any HistorySettings

    init(
        fileURL: URL? = nil,
        fileManager: FileManager = .default,
        settings: any HistorySettings = StoredHistorySettings()
    ) {
        self.fileManager = fileManager
        self.settings = settings
        self.fileURL = fileURL ?? Self.defaultFileURL(fileManager: fileManager)
        entries = loadEntries()
    }

    func add(
        text: String,
        rawText: String? = nil,
        date: Date = Date(),
        targetApplication: String
    ) throws {
        guard settings.isEnabled, !text.isEmpty else { return }
        entries.insert(TranscriptionHistoryEntry(
            text: text,
            rawText: rawText,
            date: date,
            targetApplication: targetApplication
        ), at: 0)
        entries = Array(entries.prefix(Self.maximumEntryCount))
        try persist()
    }

    func clear() throws {
        entries = []
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try fileManager.removeItem(at: fileURL)
    }

    func copyToPasteboard(_ entry: TranscriptionHistoryEntry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.text, forType: .string)
    }

    private func loadEntries() -> [TranscriptionHistoryEntry] {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([TranscriptionHistoryEntry].self, from: data) else {
            return []
        }
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        return Array(decoded.prefix(Self.maximumEntryCount))
    }

    private func persist() throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let data = try JSONEncoder().encode(entries)
        try data.write(to: fileURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    private static func defaultFileURL(fileManager: FileManager) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base
            .appendingPathComponent("DictaMac", isDirectory: true)
            .appendingPathComponent("History", isDirectory: true)
            .appendingPathComponent("transcriptions.json", isDirectory: false)
    }
}

extension TranscriptionHistoryStore: DictationHistoryRecording {
    func record(rawText: String, text: String, targetApplication: String) throws {
        try add(text: text, rawText: rawText, targetApplication: targetApplication)
    }
}
