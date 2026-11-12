import Foundation

enum TextCleanupPostProcessor {
    static func shouldClean(_ text: String) -> Bool {
        text.split(whereSeparator: { $0.isWhitespace }).count >= 2
    }

    static func process(
        raw: String,
        candidate: String,
        style: CleanupStyle,
        dictionary: [String]
    ) -> CleanupDecision {
        let cleaned = removingDictationTags(from: candidate).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return .fallback(reason: "empty output") }
        let rawCount = raw.count
        guard rawCount > 0 else { return .fallback(reason: "empty input") }
        let ratio = Double(cleaned.count) / Double(rawCount)
        guard acceptedRatio(style).contains(ratio) else { return .fallback(reason: "length ratio") }
        guard inputNumbers(raw).isSubset(of: inputNumbers(cleaned)) else {
            return .fallback(reason: "missing number")
        }
        guard preservesDetectedDictionaryTerms(raw: raw, candidate: cleaned, dictionary: dictionary) else {
            return .fallback(reason: "dictionary term")
        }
        guard !cleaned.contains("…"), !cleaned.contains("...") else {
            return .fallback(reason: "ellipsis")
        }
        return .cleaned(cleaned)
    }

    static func removingDictationTags(from text: String) -> String {
        text.replacingOccurrences(
            of: #"</?dictation\s*>"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
    }

    private static func acceptedRatio(_ style: CleanupStyle) -> ClosedRange<Double> {
        switch style {
        case .correction: 0.7...1.3
        case .polished: 0.5...1.6
        }
    }

    private static func inputNumbers(_ text: String) -> Set<String> {
        let pattern = #"\d+(?:[.,]\d+)*"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return Set(expression.matches(in: text, range: range).compactMap { match in
            Range(match.range, in: text).map { String(text[$0]) }
        })
    }

    private static func preservesDetectedDictionaryTerms(
        raw: String,
        candidate: String,
        dictionary: [String]
    ) -> Bool {
        dictionary.allSatisfy { term in
            !contains(term, in: raw, caseSensitive: false)
                || contains(term, in: candidate, caseSensitive: true)
        }
    }

    private static func contains(_ term: String, in text: String, caseSensitive: Bool) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: term)
        let pattern = #"(?<![\p{L}\p{N}])"# + escaped + #"(?![\p{L}\p{N}])"#
        let options: NSRegularExpression.Options = caseSensitive ? [] : [.caseInsensitive]
        guard let expression = try? NSRegularExpression(pattern: pattern, options: options) else { return false }
        return expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}
