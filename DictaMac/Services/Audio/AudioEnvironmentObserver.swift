@preconcurrency import AVFoundation
import AppKit
import Foundation

final class AudioEnvironmentObserver: AudioEnvironmentObserving, @unchecked Sendable {
    private let notificationCenter: NotificationCenter
    private let lock = NSLock()
    private var observers: [NSObjectProtocol] = []

    init(notificationCenter: NotificationCenter = .default) {
        self.notificationCenter = notificationCenter
    }

    func start(
        permissionChanged: @escaping @Sendable () -> Void,
        configurationChanged: @escaping @Sendable () -> Void
    ) {
        lock.withLock {
            guard observers.isEmpty else { return }
            observers = [
                observe(.microphonePermissionDidChange, handler: permissionChanged),
                observe(NSApplication.didBecomeActiveNotification, handler: permissionChanged),
                observe(.AVAudioEngineConfigurationChange, handler: configurationChanged)
            ]
        }
    }

    func stop() {
        let registered = lock.withLock {
            defer { observers.removeAll() }
            return observers
        }
        registered.forEach(notificationCenter.removeObserver)
    }

    private func observe(
        _ name: Notification.Name,
        handler: @escaping @Sendable () -> Void
    ) -> NSObjectProtocol {
        notificationCenter.addObserver(forName: name, object: nil, queue: nil) { _ in
            handler()
        }
    }
}
