import AppKit
import Foundation

@MainActor
final class MainThreadHeartbeat {
    private enum Constants {
        static let interval: TimeInterval = 0.5
    }

    private let runtime: EmergencyRuntime
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []

    init(runtime: EmergencyRuntime) {
        self.runtime = runtime
    }

    func start() {
        guard timer == nil else { return }
        updateHeartbeat()
        let timer = Timer(timeInterval: Constants.interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.updateHeartbeat() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        observeSleepAndWake()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
    }

    private func updateHeartbeat() {
        runtime.heartbeat(windowIsVisible: NSApp.windows.contains(where: \.isVisible))
    }

    private func observeSleepAndWake() {
        let center = NSWorkspace.shared.notificationCenter
        observers = [
            center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) {
                [runtime] _ in runtime.willSleep()
            },
            center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) {
                [runtime] _ in runtime.didWake()
            }
        ]
    }
}
