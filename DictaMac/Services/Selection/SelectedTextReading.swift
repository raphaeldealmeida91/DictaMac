import Foundation

@MainActor
protocol SelectedTextReading: AnyObject {
    func readSelection() -> SelectionSnapshot?
}
