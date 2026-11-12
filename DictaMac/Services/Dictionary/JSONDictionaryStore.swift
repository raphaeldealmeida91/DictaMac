import Foundation

final class JSONDictionaryStore: DictionaryStoring, @unchecked Sendable {
    typealias DirectoryProvider = @Sendable () throws -> URL

    private enum StorageError: Error {
        case applicationSupportUnavailable
    }

    private static let fileName = "personal-dictionary.json"
    private static let directoryName = "DictaMac"

    private let settingsStore: any SettingsStoring
    private let fileManager: FileManager
    private let directoryProvider: DirectoryProvider
    private let lock = NSLock()

    init(
        settingsStore: any SettingsStoring,
        fileManager: FileManager = FileManager(),
        directoryProvider: @escaping DirectoryProvider = {
            try JSONDictionaryStore.applicationSupportDirectory()
        }
    ) {
        self.settingsStore = settingsStore
        self.fileManager = fileManager
        self.directoryProvider = directoryProvider
    }

    func load() throws -> [DictionaryEntry]? {
        try lock.withLock {
            let url = try storageURL()
            guard fileManager.fileExists(atPath: url.path) else { return nil }
            return try JSONDecoder().decode([DictionaryEntry].self, from: Data(contentsOf: url))
        }
    }

    func save(_ entries: [DictionaryEntry]) throws {
        try lock.withLock {
            let url = try storageURL()
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(entries)
            try data.write(to: url, options: .atomic)
        }
    }

    private func storageURL() throws -> URL {
        if let path = settingsStore.string(for: .personalDictionaryPath), !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: false)
        }
        let url = try directoryProvider().appendingPathComponent(Self.fileName, isDirectory: false)
        settingsStore.set(.string(url.path), for: .personalDictionaryPath)
        return url
    }

    private static func applicationSupportDirectory() throws -> URL {
        let urls = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        guard let baseURL = urls.first else { throw StorageError.applicationSupportUnavailable }
        return baseURL.appendingPathComponent(directoryName, isDirectory: true)
    }
}
