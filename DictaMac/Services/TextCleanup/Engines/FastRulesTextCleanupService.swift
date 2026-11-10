import Foundation

struct FastRulesTextCleanupService: TextCleanupService {
    private let settings: any TextCleanupSettings

    init(settings: any TextCleanupSettings = StoredTextCleanupSettings()) {
        self.settings = settings
    }

    func cleanup(_ text: String) async throws -> String {
        Self.cleanup(text, removeIsolatedGenre: settings.removeIsolatedGenre)
    }

    static func cleanup(_ text: String, removeIsolatedGenre: Bool = true) -> String {
        var value = text
            .replacingOccurrences(of: #"[\t\r ]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return value }

        value = replacing(#"(?i)(?<![\p{L}\p{M}])(?:euh|heu|hum|hmm)(?![\p{L}\p{M}])"#, in: value, with: " ")
        value = replacing(#"(?i)(^|[.!?;:\n]\s*)(?:ben|bah)(?=$|[\s,;:!?])\s*[,;:]?\s*"#, in: value, with: "$1")
        if removeIsolatedGenre {
            value = replacing(#"(?i)(?<![\p{L}\p{M}])genre(?![\p{L}\p{M}])\s*[,;:]?"#, in: value, with: " ")
        }

        let repeatedWord = #"(?i)\b([\p{L}\p{M}]+(?:['’][\p{L}\p{M}]+)?)\b(?:\s+\1\b)+"#
        value = replacing(repeatedWord, in: value, with: "$1")
        value = replacing(#"\s+([,.;:!?])"#, in: value, with: "$1")
        value = replacing(#"([,.;:!?])(?=[\p{L}\p{M}])"#, in: value, with: "$1 ")
        value = replacing(#"\s+"#, in: value, with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return value }

        if let firstLetter = value.firstIndex(where: { $0.isLetter }) {
            value.replaceSubrange(firstLetter...firstLetter, with: String(value[firstLetter]).uppercased())
        }
        if let last = value.last, !".!?…".contains(last) {
            if ",;:".contains(last) { value.removeLast() }
            value.append(".")
        }
        return value
    }

    private static func replacing(_ pattern: String, in value: String, with replacement: String) -> String {
        value.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
    }
}
