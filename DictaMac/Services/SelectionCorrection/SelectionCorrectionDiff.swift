import Foundation

struct SelectionCorrectionDiff: Sendable {
    func changes(from original: String, to corrected: String) -> [TextChange] {
        guard original != corrected else { return [] }
        let originalTokens = tokens(in: original)
        let correctedTokens = tokens(in: corrected)
        let difference = correctedTokens.map(\.value).difference(from: originalTokens.map(\.value))
        let offsets = changedOffsets(in: difference)
        let anchors = anchors(
            original: originalTokens,
            corrected: correctedTokens,
            removed: offsets.removed,
            inserted: offsets.inserted
        )
        return changes(original: original, corrected: corrected, anchors: anchors)
    }

    private func changedOffsets(
        in difference: CollectionDifference<String>
    ) -> (removed: Set<Int>, inserted: Set<Int>) {
        var removed: Set<Int> = []
        var inserted: Set<Int> = []
        for change in difference {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }
        return (removed, inserted)
    }

    private func anchors(
        original: [WordToken],
        corrected: [WordToken],
        removed: Set<Int>,
        inserted: Set<Int>
    ) -> [(NSRange, NSRange)] {
        var result: [(NSRange, NSRange)] = []
        var sourceIndex = 0
        var targetIndex = 0
        while sourceIndex < original.count, targetIndex < corrected.count {
            if removed.contains(sourceIndex) { sourceIndex += 1; continue }
            if inserted.contains(targetIndex) { targetIndex += 1; continue }
            guard original[sourceIndex].value == corrected[targetIndex].value else { break }
            result.append((original[sourceIndex].range, corrected[targetIndex].range))
            sourceIndex += 1
            targetIndex += 1
        }
        return result
    }

    private func changes(
        original: String,
        corrected: String,
        anchors: [(NSRange, NSRange)]
    ) -> [TextChange] {
        var result: [TextChange] = []
        var originalStart = 0
        var correctedStart = 0
        for anchor in anchors {
            appendChange(
                original: original,
                corrected: corrected,
                originalRange: NSRange(location: originalStart, length: anchor.0.location - originalStart),
                correctedRange: NSRange(location: correctedStart, length: anchor.1.location - correctedStart),
                to: &result
            )
            originalStart = NSMaxRange(anchor.0)
            correctedStart = NSMaxRange(anchor.1)
        }
        appendTail(original, corrected, originalStart, correctedStart, to: &result)
        return result
    }

    private func appendTail(
        _ original: String,
        _ corrected: String,
        _ originalStart: Int,
        _ correctedStart: Int,
        to result: inout [TextChange]
    ) {
        appendChange(
            original: original,
            corrected: corrected,
            originalRange: NSRange(location: originalStart, length: original.utf16.count - originalStart),
            correctedRange: NSRange(location: correctedStart, length: corrected.utf16.count - correctedStart),
            to: &result
        )
    }

    private func appendChange(
        original: String,
        corrected: String,
        originalRange: NSRange,
        correctedRange: NSRange,
        to result: inout [TextChange]
    ) {
        let source = (original as NSString).substring(with: originalRange)
        let replacement = (corrected as NSString).substring(with: correctedRange)
        guard source != replacement else { return }
        result.append(TextChange(range: originalRange, replacement: replacement))
    }

    private func tokens(in text: String) -> [WordToken] {
        guard let expression = try? NSRegularExpression(pattern: #"\S+"#) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.matches(in: text, range: range).map { match in
            WordToken(value: (text as NSString).substring(with: match.range), range: match.range)
        }
    }
}

private struct WordToken {
    let value: String
    let range: NSRange
}
