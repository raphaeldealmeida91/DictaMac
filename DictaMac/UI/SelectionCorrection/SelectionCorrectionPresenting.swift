import Foundation

@MainActor
protocol SelectionCorrectionPresenting: AnyObject {
    func present(
        _ correction: SelectionCorrection,
        for snapshot: SelectionSnapshot,
        onDismiss: @escaping @MainActor () -> Void
    )
    func presentEngineUnavailable(
        for snapshot: SelectionSnapshot,
        message: String?,
        onActivateCloud: @escaping @MainActor () -> Void,
        onLoadLocal: @escaping @MainActor () -> Void,
        onDismiss: @escaping @MainActor () -> Void
    )
    func dismiss()
}

extension SelectionCorrectionPresenting {
    func presentEngineUnavailable(
        for snapshot: SelectionSnapshot,
        message: String?,
        onActivateCloud: @escaping @MainActor () -> Void,
        onLoadLocal: @escaping @MainActor () -> Void,
        onDismiss: @escaping @MainActor () -> Void
    ) {}
}
