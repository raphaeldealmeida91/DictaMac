enum SelectionEvent: Equatable, Sendable {
    case selected(SelectionSnapshot)
    case cleared
}
