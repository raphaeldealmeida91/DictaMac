import Foundation
import SwiftUI

enum SelectionCorrectionHighlighting {
    static func attributedText(for correction: SelectionCorrection) -> AttributedString {
        let mutable = NSMutableAttributedString(string: correction.corrected)
        let ranges = correctedRanges(for: correction)
        for range in ranges where range.length > .zero {
            mutable.addAttribute(
                .backgroundColor,
                value: NSColor.controlAccentColor.withAlphaComponent(0.18),
                range: range
            )
            mutable.addAttribute(.foregroundColor, value: NSColor.labelColor, range: range)
        }
        return AttributedString(mutable)
    }

    private static func correctedRanges(for correction: SelectionCorrection) -> [NSRange] {
        var offset = 0
        return correction.changes.sorted(by: { $0.range.location < $1.range.location }).map { change in
            let replacementLength = (change.replacement as NSString).length
            let location = change.range.location + offset
            offset += replacementLength - change.range.length
            return NSRange(location: location, length: replacementLength)
        }
    }
}
