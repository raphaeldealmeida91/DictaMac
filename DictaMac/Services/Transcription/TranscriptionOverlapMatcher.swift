import Foundation

struct TranscriptionOverlapMatcher {
    private static let substitutionWordBlockSize = 4
    private static let maximumTrustedOverlap = 12

    static func overlapCount(existing: [String], incoming: [String]) -> Int {
        let maximumOverlap = min(existing.count, incoming.count, maximumTrustedOverlap)
        guard maximumOverlap > 0 else { return 0 }

        for candidate in stride(from: maximumOverlap, through: 1, by: -1) {
            let suffix = Array(existing.suffix(candidate))
            let prefix = Array(incoming.prefix(candidate))
            if matches(suffix, prefix) { return candidate }
        }
        return 0
    }

    private static func matches(_ lhs: [String], _ rhs: [String]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        let maximumSubstitutions = min(1, lhs.count / substitutionWordBlockSize)
        let substitutions = zip(lhs, rhs).reduce(into: 0) { count, pair in
            if normalized(pair.0) != normalized(pair.1) { count += 1 }
        }
        return substitutions <= maximumSubstitutions
    }

    private static func normalized(_ word: String) -> String {
        word
            .trimmingCharacters(in: .punctuationCharacters)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "fr_FR")
            )
    }
}
