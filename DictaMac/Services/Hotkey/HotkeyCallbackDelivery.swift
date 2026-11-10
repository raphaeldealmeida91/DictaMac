import Foundation

enum HotkeyCallbackEvent: Sendable {
    case press
    case release
    case cancel
}

final class HotkeyCallbackDelivery: @unchecked Sendable {
    private var onPress: (@MainActor @Sendable () -> Void)?
    private var onRelease: (@MainActor @Sendable () -> Void)?
    private var onCancel: (@MainActor @Sendable () -> Void)?

    @MainActor
    func setHandlers(
        onPress: @escaping @MainActor @Sendable () -> Void,
        onRelease: @escaping @MainActor @Sendable () -> Void,
        onCancel: @escaping @MainActor @Sendable () -> Void
    ) {
        self.onPress = onPress
        self.onRelease = onRelease
        self.onCancel = onCancel
    }

    func deliver(_ event: HotkeyCallbackEvent) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            switch event {
            case .press: onPress?()
            case .release: onRelease?()
            case .cancel: onCancel?()
            }
        }
    }
}
