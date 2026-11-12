import Foundation

struct TranscriptionOverlapMatcher {
    private static let minimumRepeatedPassageLength = 2
    private static let substitutionWordBlockSize = 4

    static func overlapCount(existing: [String], incoming: [String]) -> Int {
        let maximumOverlap = min(existing.count, incoming.count)
        guard maximumOverlap > 0 else { return 0 }

        for candidate in stride(from: maximumOverlap, through: 1, by: -1) {
            let suffix = Array(existing.suffix(candidate))
            let prefix = Array(incoming.prefix(candidate))
            if matches(suffix, prefix) { return candidate }
        }
        return 0
    }

    static func removingRepeatedPassage(from words: [String]) -> [String] {
        guard words.count.isMultiple(of: 2) else { return words }
        let passageLength = words.count / 2
        guard passageLength >= minimumRepeatedPassageLength else { return words }

        let firstPassage = Array(words.prefix(passageLength))
        let secondPassage = Array(words.suffix(passageLength))
        return matches(firstPassage, secondPassage) ? firstPassage : words
    }

    private static func matches(_ lhs: [String], _ rhs: [String]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        let maximumSubstitutions = lhs.count / substitutionWordBlockSize
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
