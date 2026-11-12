import Foundation

struct FastRulesTextCleanupService: TextCleanupService {
    private let settings: any TextCleanupSettings

    init(settings: any TextCleanupSettings = StoredTextCleanupSettings()) {
        self.settings = settings
    }

    func cleanup(_ text: String, dictionary: [String]) async throws -> String {
        Self.cleanup(text, removeIsolatedGenre: settings.removeIsolatedGenre)
    }

    static func cleanup(_ text: String, removeIsolatedGenre: Bool = true) -> String {
        var value = text
            .replacingOccurrences(of: #"[\t\r ]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return value }

        value = removingHesitations(from: value, removeIsolatedGenre: removeIsolatedGenre)
        value = RepeatedSequenceRemover.remove(from: value)
        let repeatedWord = #"(?i)\b([\p{L}\p{M}]+(?:['’][\p{L}\p{M}]+)?)\b(?:\s+\1\b){2,}"#
        value = replacing(repeatedWord, in: value, with: "$1")
        value = PunctuationNormalizer.normalize(value)
        guard !value.isEmpty else { return value }

        if let last = value.last, !".!?…".contains(last) {
            if ",;:".contains(last) { value.removeLast() }
            value.append(".")
        }
        return value
    }

    private static func removingHesitations(
        from text: String,
        removeIsolatedGenre: Bool
    ) -> String {
        var value = replacing(
            #"(?i)(?<![\p{L}\p{M}])(?:euh|heu|hum|hmm)(?![\p{L}\p{M}])"#,
            in: text,
            with: " "
        )
        value = replacing(#"(?i)(^|[.!?;:\n]\s*)(?:ben|bah)(?=$|[\s,;:!?])\s*[,;:]?\s*"#, in: value, with: "$1")
        if removeIsolatedGenre {
            value = replacing(#"(?i)(?<![\p{L}\p{M}])genre(?![\p{L}\p{M}])\s*[,;:]?"#, in: value, with: " ")
        }
        let repeated = #"(?i)\b(euh|heu|hum|hmm|ben|bah|genre)\b(?:\s+\1\b)+"#
        return replacing(repeated, in: value, with: "$1")
    }

    private static func replacing(_ pattern: String, in value: String, with replacement: String) -> String {
        value.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
    }
}
