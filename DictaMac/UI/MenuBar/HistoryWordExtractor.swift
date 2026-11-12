import Foundation

enum HistoryWordExtractor {
    static func words(in text: String) -> [String] {
        let pattern = #"[\p{L}\p{N}]+(?:[-’'][\p{L}\p{N}]+)*"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        var seen = Set<String>()
        return expression.matches(in: text, range: range).compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            let word = String(text[range])
            let key = word.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            return seen.insert(key).inserted ? word : nil
        }
    }
}
