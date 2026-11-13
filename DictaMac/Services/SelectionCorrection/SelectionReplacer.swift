import AppKit

@MainActor
final class SelectionReplacer: SelectionReplacing {
    typealias FrontmostBundleIDProvider = @MainActor () -> String?

    private let selectionReader: any SelectedTextReading
    private let injector: any TextInjector
    private let pasteboard: any PasteboardProviding
    private let frontmostBundleID: FrontmostBundleIDProvider

    init(
        selectionReader: any SelectedTextReading,
        injector: any TextInjector,
        pasteboard: any PasteboardProviding,
        frontmostBundleID: @escaping FrontmostBundleIDProvider
    ) {
        self.selectionReader = selectionReader
        self.injector = injector
        self.pasteboard = pasteboard
        self.frontmostBundleID = frontmostBundleID
    }

    func replace(
        _ correction: SelectionCorrection,
        for snapshot: SelectionSnapshot
    ) -> SelectionReplacementOutcome {
        guard sourceIsStillFrontmost(snapshot), selectionIsUnchanged(snapshot) else {
            pasteboard.writeText(correction.corrected)
            return .copied
        }
        let outcome = injector.insert(correction.corrected)
        return outcome == .pasted ? .replaced : .copied
    }

    private func sourceIsStillFrontmost(_ snapshot: SelectionSnapshot) -> Bool {
        guard let sourceBundleID = snapshot.sourceBundleID else { return false }
        return frontmostBundleID() == sourceBundleID
    }

    private func selectionIsUnchanged(_ snapshot: SelectionSnapshot) -> Bool {
        selectionReader.readSelection()?.text == snapshot.text
    }
}
