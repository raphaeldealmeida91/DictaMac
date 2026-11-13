import Foundation

struct SelectionCorrectionFastRules: Sendable {
    private static let thinSpace = "\u{202F}"

    func correct(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { normalizeLine(String($0)) }
            .joined(separator: "\n")
    }

    private func normalizeLine(_ line: String) -> String {
        var value = replace(#"[ \t\u{00A0}\u{202F}]*([?!;])"#, in: line, with: "\(Self.thinSpace)$1")
        value = replace(
            #"(?<!\d)[ \t\u{00A0}\u{202F}]*:(?!\d)"#,
            in: value,
            with: "\(Self.thinSpace):"
        )
        value = replace(#"[ \t\u{00A0}\u{202F}]+([,.])"#, in: value, with: "$1")
        return replace(#"([,?!:;])[ \t]*(?=[\p{L}\p{M}])"#, in: value, with: "$1 ")
    }

    private func replace(_ pattern: String, in text: String, with replacement: String) -> String {
        text.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
    }
}
