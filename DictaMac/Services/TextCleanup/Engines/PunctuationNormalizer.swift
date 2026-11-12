import Foundation

struct PunctuationNormalizer {
    private static let spokenEllipsisMarker = "\u{E000}"
    private static let punctuation = CharacterSet(charactersIn: ",.;:!?")

    static func normalize(_ text: String) -> String {
        var value = preservingSpokenEllipsis(in: text)
        value = replacing(#"[\t\r\n ]+"#, in: value, with: " ")
        value = replacing(#"\.{3,}|…"#, in: value, with: ".")
        value = replacing(#"([,.;:!?])\s+(?=[,.;:!?])"#, in: value, with: "$1")
        value = collapsingPunctuationRuns(in: value)
        value = convertingQuotationMarks(in: value)
        value = applyingFrenchSpacing(to: value)
        value = capitalizingSentences(in: value)
        return restoringSpokenEllipsis(in: value)
    }

    private static func preservingSpokenEllipsis(in text: String) -> String {
        replacing(
            #"(?i)\bpoints?\s+de\s+suspension\s*[.!?…]*\s*$"#,
            in: text,
            with: spokenEllipsisMarker
        )
    }

    private static func collapsingPunctuationRuns(in text: String) -> String {
        var result = ""
        var run: [Character] = []
        for character in text {
            if isPunctuation(character) {
                run.append(character)
            } else {
                flush(&run, into: &result)
                result.append(character)
            }
        }
        flush(&run, into: &result)
        return result
    }

    private static func flush(_ run: inout [Character], into result: inout String) {
        guard !run.isEmpty else { return }
        let selected = run.contains("?") ? "?" : run.contains("!") ? "!" : run[run.count - 1]
        result.append(selected)
        run.removeAll(keepingCapacity: true)
    }

    private static func convertingQuotationMarks(in text: String) -> String {
        var value = replacing(#"[“\"]([^”\"]+)[”\"]"#, in: text, with: "« $1 »")
        value = replacing(#"(?<=\p{L})«"#, in: value, with: " «")
        return replacing(#"»(?=\p{L})"#, in: value, with: "» ")
    }

    private static func applyingFrenchSpacing(to text: String) -> String {
        var value = replacing(#"\s*([,.])\s*"#, in: text, with: "$1 ")
        value = replacing(#"\s*([?!:;])\s*"#, in: value, with: " $1 ")
        value = replacing(#"«\s*"#, in: value, with: "« ")
        value = replacing(#"\s*»"#, in: value, with: " »")
        return replacing(#"\s+"#, in: value, with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func capitalizingSentences(in text: String) -> String {
        var result = ""
        var shouldCapitalize = true
        for character in text {
            if character.isLetter, shouldCapitalize {
                result.append(contentsOf: String(character).uppercased())
                shouldCapitalize = false
            } else {
                result.append(character)
                if character.isLetter { shouldCapitalize = false }
            }
            if ".!?".contains(character) { shouldCapitalize = true }
        }
        return result
    }

    private static func restoringSpokenEllipsis(in text: String) -> String {
        text.replacingOccurrences(of: " \(spokenEllipsisMarker)", with: "…")
            .replacingOccurrences(of: spokenEllipsisMarker, with: "…")
    }

    private static func isPunctuation(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy(punctuation.contains)
    }

    private static func replacing(_ pattern: String, in text: String, with replacement: String) -> String {
        text.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
    }
}
