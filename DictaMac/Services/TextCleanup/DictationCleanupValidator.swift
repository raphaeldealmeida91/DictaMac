import Foundation

struct DictationCleanupValidator: Sendable {
    static let maximumLengthGrowthRatio = 0.30
    static let minimumSignificantWordRetentionRatio = 0.60
    static let minimumSignificantWordLength = 4

    enum RejectionReason: String, Equatable, Sendable {
        case emptyOutput = "empty-output"
        case excessiveLength = "excessive-length"
        case significantWordLoss = "significant-word-loss"
        case unrelatedPreamble = "unrelated-preamble"
        case assistantAnswer = "assistant-answer"
        case missingNumber = "missing-number"
        case missingURL = "missing-url"
        case dictionaryTerm = "dictionary-term"
        case introducedEllipsis = "introduced-ellipsis"
    }

    enum Result: Equatable, Sendable {
        case accepted(String)
        case rejected(RejectionReason)
    }

    func validate(original: String, candidate: String, dictionary: [String] = []) -> Result {
        let cleaned = TextCleanupPostProcessor.removingDictationTags(from: candidate)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return .rejected(.emptyOutput) }
        if let reason = rejectionReason(original: original, candidate: cleaned, dictionary: dictionary) {
            return .rejected(reason)
        }
        return .accepted(cleaned)
    }

    private func rejectionReason(
        original: String,
        candidate: String,
        dictionary: [String]
    ) -> RejectionReason? {
        if !hasAcceptedLength(original: original, candidate: candidate) { return .excessiveLength }
        if startsWithIntroducedPreamble(candidate, original: original) { return .unrelatedPreamble }
        if looksLikeIntroducedAssistantAnswer(candidate, original: original) { return .assistantAnswer }
        if !preserves(pattern: Patterns.number, original: original, candidate: candidate) { return .missingNumber }
        if !preserves(pattern: Patterns.url, original: original, candidate: candidate) { return .missingURL }
        if !preservesDictionaryTerms(original: original, candidate: candidate, dictionary: dictionary) {
            return .dictionaryTerm
        }
        if containsIntroducedEllipsis(original: original, candidate: candidate) { return .introducedEllipsis }
        if !preservesSignificantWords(original: original, candidate: candidate) { return .significantWordLoss }
        return nil
    }

    private func hasAcceptedLength(original: String, candidate: String) -> Bool {
        guard !original.isEmpty else { return false }
        let maximumLength = Double(original.count) * (1 + Self.maximumLengthGrowthRatio)
        return Double(candidate.count) <= maximumLength
    }

    private func preservesSignificantWords(original: String, candidate: String) -> Bool {
        let source = significantWords(in: original)
        guard !source.isEmpty else { return true }
        let target = significantWords(in: candidate)
        let retainedCount = source.filter { sourceWord in
            target.contains { wordsAreEquivalent(sourceWord, $0) }
        }.count
        return Double(retainedCount) / Double(source.count)
            >= Self.minimumSignificantWordRetentionRatio
    }

    private func significantWords(in text: String) -> [String] {
        words(in: text).filter { word in
            word.count >= Self.minimumSignificantWordLength
                && !Self.ignoredWords.contains(word)
        }
    }

    private func words(in text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    private func wordsAreEquivalent(_ lhs: String, _ rhs: String) -> Bool {
        lhs == rhs || normalizedEnding(lhs) == normalizedEnding(rhs)
    }

    private func normalizedEnding(_ word: String) -> String {
        guard word.count > Self.minimumSignificantWordLength else { return word }
        return word.trimmingCharacters(in: CharacterSet(charactersIn: "sx"))
    }

    private func startsWithIntroducedPreamble(_ text: String, original: String) -> Bool {
        hasIntroducedPrefix(from: Self.unrelatedPreambles, candidate: text, original: original)
    }

    private func looksLikeIntroducedAssistantAnswer(_ text: String, original: String) -> Bool {
        hasIntroducedPrefix(from: Self.assistantAnswerPreambles, candidate: text, original: original)
            || answersQuestion(candidate: text, original: original)
    }

    private func answersQuestion(candidate: String, original: String) -> Bool {
        guard looksLikeQuestion(original) else { return false }
        return !candidate.contains("?") && !looksLikeQuestion(candidate)
    }

    private func looksLikeQuestion(_ text: String) -> Bool {
        if text.contains("?") { return true }
        let value = normalized(text)
        return Self.questionOpenings.contains { value.hasPrefix($0) }
    }

    private func hasIntroducedPrefix(
        from prefixes: [String],
        candidate: String,
        original: String
    ) -> Bool {
        let normalizedCandidate = normalized(candidate)
        let normalizedOriginal = normalized(original)
        return prefixes.contains {
            normalizedCandidate.hasPrefix($0) && !normalizedOriginal.hasPrefix($0)
        }
    }

    private func preserves(pattern: String, original: String, candidate: String) -> Bool {
        let required = occurrences(of: pattern, in: original)
        let available = occurrences(of: pattern, in: candidate)
        return required.allSatisfy { value in
            required.filter { $0 == value }.count <= available.filter { $0 == value }.count
        }
    }

    private func occurrences(of pattern: String, in text: String) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.matches(in: text, range: range).compactMap { match in
            Range(match.range, in: text).map { String(text[$0]) }
        }
    }

    private func preservesDictionaryTerms(
        original: String,
        candidate: String,
        dictionary: [String]
    ) -> Bool {
        dictionary.filter { contains($0, in: original, caseSensitive: false) }.allSatisfy {
            contains($0, in: candidate, caseSensitive: true)
        }
    }

    private func contains(_ term: String, in text: String, caseSensitive: Bool) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: term)
        let pattern = #"(?<![\p{L}\p{N}])"# + escaped + #"(?![\p{L}\p{N}])"#
        let options: NSRegularExpression.Options = caseSensitive ? [] : [.caseInsensitive]
        guard let expression = try? NSRegularExpression(pattern: pattern, options: options) else { return false }
        return expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    private func containsIntroducedEllipsis(original: String, candidate: String) -> Bool {
        let originalContainsEllipsis = original.contains("…") || original.contains("...")
        return !originalContainsEllipsis && (candidate.contains("…") || candidate.contains("..."))
    }

    private func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let ignoredWords: Set<String> = [
        "alors", "donc", "enfin", "euh", "genre", "heu", "mais", "plutot"
    ]

    private static let unrelatedPreambles = [
        "voici le texte", "voici la version", "texte corrige", "version corrigee"
    ]

    private static let assistantAnswerPreambles = [
        "bien sur, voici", "bien sur :", "je peux vous", "la reponse est",
        "en tant qu'assistant", "en tant qu’assistant"
    ]

    private static let questionOpenings = [
        "combien ", "comment ", "est-ce que ", "ou ", "pourquoi ", "quand ",
        "quel ", "quelle ", "quels ", "quelles ", "qui ", "peux-tu ", "pouvez-vous "
    ]

    private enum Patterns {
        static let number = #"(?<![\p{L}\p{N}])\d+(?:[.,]\d+)*(?![\p{L}\p{N}])"#
        static let url = #"(?:https?://|www\.)[^\s<>]+"#
    }
}
