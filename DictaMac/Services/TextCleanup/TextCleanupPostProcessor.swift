import Foundation

enum TextCleanupPostProcessor {
    static func shouldClean(_ text: String) -> Bool {
        text.split(whereSeparator: { $0.isWhitespace }).count >= 4
    }

    static func process(raw: String, candidate: String) -> CleanupDecision {
        let cleaned = removingDictationTags(from: candidate).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return .fallback(reason: "empty output") }
        let rawCount = raw.count
        guard rawCount > 0 else { return .fallback(reason: "empty input") }
        let ratio = Double(cleaned.count) / Double(rawCount)
        if ratio > 1.3 || (rawCount >= 20 && ratio < 0.3) {
            return .fallback(reason: "length ratio")
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
}
