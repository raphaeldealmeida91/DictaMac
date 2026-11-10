@preconcurrency import AVFoundation
import AppKit
import Foundation

final class AudioEnvironmentObserver: AudioEnvironmentObserving, @unchecked Sendable {
    private struct Registration {
        let center: NotificationCenter
        let observer: NSObjectProtocol
    }

    private let applicationNotificationCenter: NotificationCenter
    private let workspaceNotificationCenter: NotificationCenter
    private let lock = NSLock()
    private var registrations: [Registration] = []

    init(
        applicationNotificationCenter: NotificationCenter = .default,
        workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
    ) {
        self.applicationNotificationCenter = applicationNotificationCenter
        self.workspaceNotificationCenter = workspaceNotificationCenter
    }

    func start(
        permissionChanged: @escaping @Sendable () -> Void,
        configurationChanged: @escaping @Sendable () -> Void,
        systemWillSleep: @escaping @Sendable () -> Void,
        systemDidWake: @escaping @Sendable () -> Void
    ) {
        lock.withLock {
            guard registrations.isEmpty else { return }
            registrations = [
                observe(.microphonePermissionDidChange, handler: permissionChanged),
                observe(NSApplication.didBecomeActiveNotification, handler: permissionChanged),
                observe(.AVAudioEngineConfigurationChange, handler: configurationChanged),
                observe(NSWorkspace.willSleepNotification, in: workspaceNotificationCenter, handler: systemWillSleep),
                observe(NSWorkspace.didWakeNotification, in: workspaceNotificationCenter, handler: systemDidWake)
            ]
        }
    }

    func stop() {
        let registered = lock.withLock {
            defer { registrations.removeAll() }
            return registrations
        }
        registered.forEach { $0.center.removeObserver($0.observer) }
    }

    private func observe(
        _ name: Notification.Name,
        in center: NotificationCenter? = nil,
        handler: @escaping @Sendable () -> Void
    ) -> Registration {
        let center = center ?? applicationNotificationCenter
        let observer = center.addObserver(forName: name, object: nil, queue: nil) { _ in
            handler()
        }
        return Registration(center: center, observer: observer)
    }
}
