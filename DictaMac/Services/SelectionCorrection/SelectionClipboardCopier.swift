@MainActor
final class SelectionClipboardCopier: SelectionClipboardCopying {
    private let pasteboard: any PasteboardProviding

    init(pasteboard: any PasteboardProviding) {
        self.pasteboard = pasteboard
    }

    func copy(_ text: String) {
        pasteboard.writeText(text)
    }
}
