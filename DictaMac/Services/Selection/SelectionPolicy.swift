import Foundation

struct SelectionPolicy: Sendable {
    static let minimumWordCount = 2
    static let maximumCharacterCount = 2_000

    private let excludedBundleIDs: Set<String>
    private let ownBundleID: String?

    init(excludedBundleIDs: Set<String>, ownBundleID: String?) {
        self.excludedBundleIDs = excludedBundleIDs
        self.ownBundleID = ownBundleID
    }

    func accepts(_ snapshot: SelectionSnapshot) -> Bool {
        guard !snapshot.isSecure,
              snapshot.text.count <= Self.maximumCharacterCount,
              wordCount(in: snapshot.text) >= Self.minimumWordCount else {
            return false
        }
        return accepts(bundleID: snapshot.sourceBundleID)
    }

    private func accepts(bundleID: String?) -> Bool {
        guard let bundleID else { return true }
        return bundleID != ownBundleID && !excludedBundleIDs.contains(bundleID)
    }

    private func wordCount(in text: String) -> Int {
        text.split(whereSeparator: \Character.isWhitespace).count
    }
}
