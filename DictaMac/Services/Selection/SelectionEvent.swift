enum SelectionEvent: Equatable, Sendable {
    case selected(SelectionSnapshot)
    case focusedText(FocusedTextSnapshot)
    case cleared
}
