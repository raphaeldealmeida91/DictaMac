import Foundation

@MainActor
protocol SelectionCorrectionPresenting: AnyObject {
    func present(
        _ correction: SelectionCorrection,
        for snapshot: SelectionSnapshot,
        onDismiss: @escaping @MainActor () -> Void
    )
    func dismiss()
}
