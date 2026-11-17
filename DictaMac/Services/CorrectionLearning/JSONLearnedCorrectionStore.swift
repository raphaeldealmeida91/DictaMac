import Foundation

final class JSONLearnedCorrectionStore: LearnedCorrectionStoring, @unchecked Sendable {
    typealias DirectoryProvider = @Sendable () throws -> URL

    private enum StorageError: Error {
        case applicationSupportUnavailable
    }

    private static let directoryName = "DictaMac"
    private static let fileName = "learned-corrections.json"
    private static let securePermissions = 0o600

    private let fileManager: FileManager
    private let directoryProvider: DirectoryProvider
    private let lock = NSLock()

    init(
        fileManager: FileManager = FileManager(),
        directoryProvider: @escaping DirectoryProvider = {
            try JSONLearnedCorrectionStore.applicationSupportDirectory()
        }
    ) {
        self.fileManager = fileManager
        self.directoryProvider = directoryProvider
    }

    func load() throws -> [LearnedCorrectionEntry] {
        try lock.withLock {
            let url = try storageURL()
            guard fileManager.fileExists(atPath: url.path) else { return [] }
            try applySecurePermissions(to: url)
            return try JSONDecoder().decode(
                [LearnedCorrectionEntry].self,
                from: Data(contentsOf: url)
            )
        }
    }

    func save(_ entries: [LearnedCorrectionEntry]) throws {
        try lock.withLock {
            let url = try storageURL()
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try JSONEncoder().encode(entries).write(to: url, options: .atomic)
            try applySecurePermissions(to: url)
        }
    }

    func clear() throws {
        try lock.withLock {
            let url = try storageURL()
            guard fileManager.fileExists(atPath: url.path) else { return }
            try fileManager.removeItem(at: url)
        }
    }

    func storageURL() throws -> URL {
        try directoryProvider().appendingPathComponent(Self.fileName, isDirectory: false)
    }

    private static func applicationSupportDirectory() throws -> URL {
        guard let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { throw StorageError.applicationSupportUnavailable }
        return baseURL.appendingPathComponent(directoryName, isDirectory: true)
    }

    private func applySecurePermissions(to url: URL) throws {
        try fileManager.setAttributes(
            [.posixPermissions: Self.securePermissions],
            ofItemAtPath: url.path
        )
    }
}
