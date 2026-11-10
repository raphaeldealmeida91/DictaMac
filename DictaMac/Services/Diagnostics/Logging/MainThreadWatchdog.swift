import Foundation
import OSLog

// Lifecycle mutations are serialized on queue and callbacks capture only Sendable values.
final class MainThreadWatchdog: @unchecked Sendable {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "DictaMac",
        category: "MainThreadWatchdog"
    )
    private let queue = DispatchQueue(
        label: "com.raphaeldealmeida.DictaMac.main-watchdog",
        qos: .utility
    )
    private var timer: DispatchSourceTimer?
    private let lock = NSLock()
    private var pingOutstanding = false
    private let diagnosticLog: any DiagnosticLogging

    init(diagnosticLog: any DiagnosticLogging) {
        self.diagnosticLog = diagnosticLog
    }

    func start() {
        lock.lock()
        guard timer == nil else {
            lock.unlock()
            return
        }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        self.timer = timer
        lock.unlock()
        timer.schedule(deadline: .now() + .milliseconds(250), repeating: .milliseconds(250))
        timer.setEventHandler { [weak self] in self?.ping() }
        timer.resume()
    }

    func stop() {
        let timer = lock.withLock { () -> DispatchSourceTimer? in
            defer { self.timer = nil }
            return self.timer
        }
        timer?.cancel()
    }

    private func ping() {
        let shouldSend = lock.withLock {
            guard !pingOutstanding else { return false }
            pingOutstanding = true
            return true
        }
        guard shouldSend else { return }
        let sent = DispatchTime.now().uptimeNanoseconds
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let delay = Double(DispatchTime.now().uptimeNanoseconds - sent) / 1_000_000_000
            self.lock.withLock { self.pingOutstanding = false }
            if delay > 0.5 {
                self.logger.fault("main thread stall duration=\(delay, format: .fixed(precision: 3))s")
                self.diagnosticLog.mainThreadStall(duration: delay)
            }
        }
    }
}
