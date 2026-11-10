import Foundation

@MainActor
protocol HotkeyProviding: AnyObject {
    var onPress: (() -> Void)? { get set }
    var onRelease: (() -> Void)? { get set }
    var onCancel: (() -> Void)? { get set }

    func start()
    func stop()
}
