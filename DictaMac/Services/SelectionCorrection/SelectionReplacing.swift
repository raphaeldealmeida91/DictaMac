@MainActor
protocol SelectionReplacing: AnyObject {
    func replace(_ correction: SelectionCorrection, for snapshot: SelectionSnapshot) -> SelectionReplacementOutcome
}
