import Foundation

struct RepeatedSequenceRemover {
    private static let minimumSequenceLength = 2
    private static let maximumSequenceLength = 6
    private static let sequenceLengths = Array(
        stride(from: maximumSequenceLength, through: minimumSequenceLength, by: -1)
    )

    static func remove(from text: String) -> String {
        var words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        var index = 0

        while index < words.count {
            guard let length = repeatedSequenceLength(in: words, at: index) else {
                index += 1
                continue
            }
            words.removeSubrange((index + length)..<(index + (2 * length)))
            index = max(0, index - length)
        }
        return words.joined(separator: " ")
    }

    private static func repeatedSequenceLength(in words: [String], at index: Int) -> Int? {
        sequenceLengths.first { length in
            guard index + (2 * length) <= words.count else { return false }
            let first = words[index..<(index + length)].map(normalized)
            let second = words[(index + length)..<(index + (2 * length))].map(normalized)
            return first == second
        }
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
