import Foundation

struct SelectionCorrectionValidator: Sendable {
    static let maximumWordEditRatio = 0.35

    func accepts(original: String, candidate: String, dictionary: [String]) -> Bool {
        guard preservesLineBreaks(original: original, candidate: candidate) else { return false }
        guard preserves(pattern: Patterns.number, original: original, candidate: candidate) else { return false }
        guard preserves(pattern: Patterns.url, original: original, candidate: candidate) else { return false }
        guard preservesDictionaryTerms(original: original, candidate: candidate, dictionary: dictionary) else {
            return false
        }
        guard !candidate.contains("…") || original.contains("…") else { return false }
        return wordEditRatio(from: original, to: candidate) <= Self.maximumWordEditRatio
    }

    private func preservesLineBreaks(original: String, candidate: String) -> Bool {
        original.filter(\.isLineBreak) == candidate.filter(\.isLineBreak)
    }

    private func preserves(pattern: String, original: String, candidate: String) -> Bool {
        let required = occurrences(of: pattern, in: original)
        let available = occurrences(of: pattern, in: candidate)
        return required.allSatisfy { value in
            required.filter { $0 == value }.count <= available.filter { $0 == value }.count
        }
    }

    private func preservesDictionaryTerms(
        original: String,
        candidate: String,
        dictionary: [String]
    ) -> Bool {
        dictionary.filter(original.contains).allSatisfy(candidate.contains)
    }

    private func wordEditRatio(from original: String, to candidate: String) -> Double {
        let source = occurrences(of: Patterns.word, in: original)
        let target = occurrences(of: Patterns.word, in: candidate)
        guard !source.isEmpty else { return target.isEmpty ? 0 : 1 }
        return Double(editDistance(source, target)) / Double(source.count)
    }

    private func editDistance(_ source: [String], _ target: [String]) -> Int {
        var previous = Array(0...target.count)
        for (sourceIndex, sourceWord) in source.enumerated() {
            var current = [sourceIndex + 1]
            for (targetIndex, targetWord) in target.enumerated() {
                let substitution = previous[targetIndex] + (sourceWord == targetWord ? 0 : 1)
                current.append(min(previous[targetIndex + 1] + 1, current[targetIndex] + 1, substitution))
            }
            previous = current
        }
        return previous[target.count]
    }

    private func occurrences(of pattern: String, in text: String) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.matches(in: text, range: range).compactMap { match in
            Range(match.range, in: text).map { String(text[$0]) }
        }
    }
}

private enum Patterns {
    static let word = #"[\p{L}\p{M}\p{N}]+(?:['’][\p{L}\p{M}\p{N}]+)*"#
    static let number = #"(?<![\p{L}\p{N}])\d+(?:[.,]\d+)*(?![\p{L}\p{N}])"#
    static let url = #"(?:https?://|www\.)[^\s<>]+"#
}

private extension Character {
    var isLineBreak: Bool { self == "\n" || self == "\r" }
}
