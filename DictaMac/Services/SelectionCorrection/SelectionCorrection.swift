struct SelectionCorrection: Equatable, Sendable {
    let original: String
    let corrected: String
    let changes: [TextChange]

    static func unchanged(_ text: String) -> SelectionCorrection {
        SelectionCorrection(original: text, corrected: text, changes: [])
    }
}
