import Foundation

@MainActor
final class MainThreadHeartbeat {
    private enum Constants {
        static let interval: TimeInterval = 0.5
    }

    private let runtime: EmergencyRuntime
    private var timer: Timer?

    init(runtime: EmergencyRuntime) {
        self.runtime = runtime
    }

    func start() {
        guard timer == nil else { return }
        runtime.heartbeat()
        let timer = Timer(timeInterval: Constants.interval, repeats: true) { [runtime] _ in
            runtime.heartbeat()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
