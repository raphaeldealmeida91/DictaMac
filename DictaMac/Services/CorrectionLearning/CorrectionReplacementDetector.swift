import Foundation

struct CorrectionReplacementDetector: Sendable {
    private enum Constants {
        static let maximumReplacementWordCount = 3
        static let maximumChangedFraction = 0.35
        static let shortTextWordCount = 3
        static let maximumShortTextEditFraction = 0.5
    }

    private let diff = SelectionCorrectionDiff()

    func replacements(from dictated: String, in candidate: String) -> [CorrectionReplacement] {
        let sourceWords = words(in: dictated)
        let candidateWords = words(in: candidate)
        guard !sourceWords.isEmpty, !candidateWords.isEmpty, dictated != candidate else { return [] }
        return bestReplacements(from: dictated, sourceWordCount: sourceWords.count, in: candidateWords)
    }

    private func validatedChanges(
        from source: String,
        to candidate: String,
        sourceWordCount: Int
    ) -> [CorrectionReplacement]? {
        let changes = diff.changes(from: source, to: candidate)
        guard !changes.isEmpty, changes.count <= Constants.maximumReplacementWordCount else { return nil }
        let replacements = changes.compactMap { replacement(for: $0, source: source) }
        guard replacements.count == changes.count else { return nil }
        let changedWords = replacements.reduce(0) { $0 + words(in: $1.dictated).count }
        guard acceptsGlobalMeaning(
            replacements,
            changedWords: changedWords,
            sourceWordCount: sourceWordCount
        ) else { return nil }
        return replacements
    }

    private func replacement(for change: TextChange, source: String) -> CorrectionReplacement? {
        let dictated = (source as NSString).substring(with: change.range)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let corrected = change.replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceCount = words(in: dictated).count
        let correctedCount = words(in: corrected).count
        guard (1...Constants.maximumReplacementWordCount).contains(sourceCount),
              (1...Constants.maximumReplacementWordCount).contains(correctedCount),
              dictated.caseInsensitiveCompare(corrected) != .orderedSame else { return nil }
        return CorrectionReplacement(dictated: dictated, corrected: corrected)
    }

    private func acceptsGlobalMeaning(
        _ replacements: [CorrectionReplacement],
        changedWords: Int,
        sourceWordCount: Int
    ) -> Bool {
        if changedWords < sourceWordCount {
            return Double(changedWords) / Double(sourceWordCount) <= Constants.maximumChangedFraction
        }
        guard sourceWordCount <= Constants.shortTextWordCount else { return false }
        return replacements.allSatisfy(isSimilarRecognition)
    }

    private func isSimilarRecognition(_ replacement: CorrectionReplacement) -> Bool {
        let source = normalizedCharacters(replacement.dictated)
        let corrected = normalizedCharacters(replacement.corrected)
        guard !source.isEmpty, !corrected.isEmpty else { return false }
        let distance = levenshteinDistance(source, corrected)
        return Double(distance) / Double(max(source.count, corrected.count))
            <= Constants.maximumShortTextEditFraction
    }

    private func normalizedCharacters(_ text: String) -> [Character] {
        Array(text.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        ).filter(\.isLetter))
    }

    private func levenshteinDistance(_ lhs: [Character], _ rhs: [Character]) -> Int {
        var previous = Array(0...rhs.count)
        for (leftIndex, left) in lhs.enumerated() {
            var current = [leftIndex + 1]
            for (rightIndex, right) in rhs.enumerated() {
                current.append(min(
                    current[rightIndex] + 1,
                    previous[rightIndex + 1] + 1,
                    previous[rightIndex] + (left == right ? 0 : 1)
                ))
            }
            previous = current
        }
        return previous[rhs.count]
    }

    private func bestReplacements(
        from source: String,
        sourceWordCount: Int,
        in candidateWords: [Substring]
    ) -> [CorrectionReplacement] {
        var best: [CorrectionReplacement] = []
        let bestScore: ([CorrectionReplacement]) -> Int = {
            self.score($0, sourceWordCount: sourceWordCount)
        }
        for length in candidateLengths(sourceCount: sourceWordCount, candidateCount: candidateWords.count) {
            for start in 0...(candidateWords.count - length) {
                let candidate = candidateWords[start..<(start + length)].joined(separator: " ")
                guard let replacements = validatedChanges(
                    from: source,
                    to: candidate,
                    sourceWordCount: sourceWordCount
                ), best.isEmpty || bestScore(replacements) > bestScore(best) else { continue }
                best = replacements
            }
        }
        return best
    }

    private func candidateLengths(sourceCount: Int, candidateCount: Int) -> [Int] {
        let minimumLength = max(1, sourceCount - Constants.maximumReplacementWordCount)
        let maximumLength = min(
            candidateCount,
            sourceCount + Constants.maximumReplacementWordCount
        )
        guard minimumLength <= maximumLength else { return [] }
        return Array(minimumLength...maximumLength)
    }

    private func score(_ replacements: [CorrectionReplacement], sourceWordCount: Int) -> Int {
        let changed = replacements.reduce(0) { $0 + words(in: $1.dictated).count }
        return (sourceWordCount - changed) * 100 - replacements.count
    }

    private func words(in text: String) -> [Substring] {
        text.split(whereSeparator: \.isWhitespace)
    }
}
