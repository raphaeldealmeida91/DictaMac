import Foundation

final class HotkeyPermissionObserver: HotkeyPermissionObserving, @unchecked Sendable {
    private let notificationCenter: NotificationCenter
    private let lock = NSLock()
    private var observer: NSObjectProtocol?

    init(notificationCenter: NotificationCenter = .default) {
        self.notificationCenter = notificationCenter
    }

    func start(_ handler: @escaping @Sendable (Bool) -> Void) {
        lock.withLock {
            guard observer == nil else { return }
            observer = notificationCenter.addObserver(
                forName: .inputMonitoringPermissionDidChange,
                object: nil,
                queue: nil
            ) { notification in
                handler(notification.userInfo?["authorized"] as? Bool ?? false)
            }
        }
    }

    func stop() {
        let registered = lock.withLock {
            defer { observer = nil }
            return observer
        }
        if let registered { notificationCenter.removeObserver(registered) }
    }
}
