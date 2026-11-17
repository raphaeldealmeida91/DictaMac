import Foundation

final class LearnedCorrectionRepository: @unchecked Sendable {
    static let maximumEntryCount = 200
    static let proposalThreshold = 2

    private let storage: any LearnedCorrectionStoring
    private let lock = NSLock()
    private var cachedEntries: [LearnedCorrectionEntry]

    init(storage: any LearnedCorrectionStoring) {
        self.storage = storage
        cachedEntries = (try? storage.load()) ?? []
    }

    func record(dictated: String, corrected: String, at date: Date) throws {
        try lock.withLock {
            if let index = cachedEntries.firstIndex(where: {
                Self.matches($0.dictated, dictated) && Self.matches($0.corrected, corrected)
            }) {
                cachedEntries[index].occurrenceCount += 1
                cachedEntries[index].lastSeen = date
            } else {
                cachedEntries.append(LearnedCorrectionEntry(
                    id: UUID(),
                    dictated: dictated,
                    corrected: corrected,
                    occurrenceCount: 1,
                    lastSeen: date,
                    status: .observed
                ))
            }
            trimToLimit()
            try storage.save(cachedEntries)
        }
    }

    func nextProposal() -> LearnedCorrectionEntry? {
        lock.withLock {
            cachedEntries
                .filter { $0.status == .observed && $0.occurrenceCount >= Self.proposalThreshold }
                .max(by: { $0.lastSeen < $1.lastSeen })
        }
    }

    func setStatus(_ status: LearnedCorrectionEntry.Status, for identifier: UUID) throws {
        try lock.withLock {
            guard let index = cachedEntries.firstIndex(where: { $0.id == identifier }) else { return }
            cachedEntries[index].status = status
            try storage.save(cachedEntries)
        }
    }

    func entries() -> [LearnedCorrectionEntry] {
        lock.withLock { cachedEntries }
    }

    func clear() throws {
        try lock.withLock {
            try storage.clear()
            cachedEntries = []
        }
    }

    private func trimToLimit() {
        while cachedEntries.count > Self.maximumEntryCount {
            guard let index = oldestReplaceableEntryIndex() else { return }
            cachedEntries.remove(at: index)
        }
    }

    private func oldestReplaceableEntryIndex() -> Int? {
        cachedEntries.indices
            .filter { cachedEntries[$0].status != .refused }
            .min { cachedEntries[$0].lastSeen < cachedEntries[$1].lastSeen }
    }

    private static func matches(_ lhs: String, _ rhs: String) -> Bool {
        lhs.precomposedStringWithCanonicalMapping == rhs.precomposedStringWithCanonicalMapping
    }
}
