import Foundation

struct DictionaryCorrector {
    private struct Token {
        let range: Range<String.Index>
        let normalized: String
    }

    private struct Pattern {
        let canonical: String
        let tokens: [String]
    }

    private static let minimumFuzzyLength = 5
    private static let maximumFuzzyDistance = 1
    private static let tokenPattern = #"[\p{L}\p{M}\p{N}]+"#

    static func correct(_ text: String, entries: [DictionaryEntry]) -> String {
        let tokens = tokenize(text)
        guard !tokens.isEmpty, !entries.isEmpty else { return text }
        let exactPatterns = patterns(from: entries)
        let fuzzyPatterns = fuzzyPatterns(from: entries)
        return replacing(
            tokens: tokens,
            in: text,
            exactPatterns: exactPatterns,
            fuzzyPatterns: fuzzyPatterns
        )
    }

    private static func replacing(
        tokens: [Token],
        in text: String,
        exactPatterns: [Pattern],
        fuzzyPatterns: [Pattern]
    ) -> String {
        var result = ""
        var sourceIndex = text.startIndex
        var tokenIndex = 0
        while tokenIndex < tokens.count {
            guard let match = match(
                at: tokenIndex,
                tokens: tokens,
                exactPatterns: exactPatterns,
                fuzzyPatterns: fuzzyPatterns
            ) else {
                tokenIndex += 1
                continue
            }
            let lastToken = tokens[tokenIndex + match.tokens.count - 1]
            result += text[sourceIndex..<tokens[tokenIndex].range.lowerBound]
            result += match.canonical
            sourceIndex = lastToken.range.upperBound
            tokenIndex += match.tokens.count
        }
        result += text[sourceIndex...]
        return result
    }

    private static func match(
        at index: Int,
        tokens: [Token],
        exactPatterns: [Pattern],
        fuzzyPatterns: [Pattern]
    ) -> Pattern? {
        if let exact = exactPatterns.first(where: { matches($0, at: index, tokens: tokens) }) {
            return exact
        }
        return fuzzyPatterns.first { pattern in
            guard index < tokens.count else { return false }
            let candidate = tokens[index].normalized
            let canonical = pattern.tokens[0]
            return isFuzzyMatch(candidate, canonical: canonical)
        }
    }

    private static func isFuzzyMatch(_ candidate: String, canonical: String) -> Bool {
        guard abs(candidate.count - canonical.count) <= maximumFuzzyDistance else { return false }
        guard damerauLevenshtein(candidate, canonical) <= maximumFuzzyDistance else { return false }
        let isLongerWord = candidate.count > canonical.count && candidate.hasPrefix(canonical)
        return !isLongerWord
    }

    private static func matches(_ pattern: Pattern, at index: Int, tokens: [Token]) -> Bool {
        guard index + pattern.tokens.count <= tokens.count else { return false }
        let candidate = tokens[index..<(index + pattern.tokens.count)].map(\.normalized)
        return candidate == pattern.tokens
    }

    private static func patterns(from entries: [DictionaryEntry]) -> [Pattern] {
        entries.flatMap { entry in
            ([entry.canonical] + entry.variants).compactMap { value in
                let tokens = normalizedTokens(in: value)
                return tokens.isEmpty ? nil : Pattern(canonical: entry.canonical, tokens: tokens)
            }
        }
        .sorted { $0.tokens.count > $1.tokens.count }
    }

    private static func fuzzyPatterns(from entries: [DictionaryEntry]) -> [Pattern] {
        entries.compactMap { entry in
            let tokens = normalizedTokens(in: entry.canonical)
            guard tokens.count == 1, tokens[0].count >= minimumFuzzyLength else { return nil }
            return Pattern(canonical: entry.canonical, tokens: tokens)
        }
    }

    private static func tokenize(_ text: String) -> [Token] {
        guard let expression = try? NSRegularExpression(pattern: tokenPattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.matches(in: text, range: range).compactMap { match in
            guard let tokenRange = Range(match.range, in: text) else { return nil }
            return Token(range: tokenRange, normalized: normalized(String(text[tokenRange])))
        }
    }

    private static func normalizedTokens(in text: String) -> [String] {
        tokenize(text).map(\.normalized)
    }

    private static func normalized(_ text: String) -> String {
        text.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "fr_FR")
        )
    }

    private static func damerauLevenshtein(_ lhs: String, _ rhs: String) -> Int {
        let left = Array(lhs)
        let right = Array(rhs)
        var distances = Array(
            repeating: Array(repeating: 0, count: right.count + 1),
            count: left.count + 1
        )
        for index in 0...left.count { distances[index][0] = index }
        for index in 0...right.count { distances[0][index] = index }
        for leftIndex in 1...left.count {
            for rightIndex in 1...right.count {
                let cost = left[leftIndex - 1] == right[rightIndex - 1] ? 0 : 1
                distances[leftIndex][rightIndex] = min(
                    distances[leftIndex - 1][rightIndex] + 1,
                    distances[leftIndex][rightIndex - 1] + 1,
                    distances[leftIndex - 1][rightIndex - 1] + cost
                )
                if leftIndex > 1, rightIndex > 1,
                   left[leftIndex - 1] == right[rightIndex - 2],
                   left[leftIndex - 2] == right[rightIndex - 1] {
                    distances[leftIndex][rightIndex] = min(
                        distances[leftIndex][rightIndex],
                        distances[leftIndex - 2][rightIndex - 2] + cost
                    )
                }
            }
        }
        return distances[left.count][right.count]
    }
}
