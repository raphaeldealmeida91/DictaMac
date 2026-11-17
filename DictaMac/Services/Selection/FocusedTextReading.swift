@MainActor
protocol FocusedTextReading: AnyObject {
    func readFocusedText() -> FocusedTextSnapshot?
}
