import Foundation

protocol LocalModelInactivityPolicy: Sendable {
    func activityStarted()
    func activityEnded(unload: @escaping @Sendable () async -> Void)
    func modelBecameReady(unload: @escaping @Sendable () async -> Void)
    func cancel()
}

final class DefaultLocalModelInactivityPolicy: LocalModelInactivityPolicy, @unchecked Sendable {
    private let lock = NSLock()
    private let clock: any InactivityClock
    private let timeout: @Sendable () -> TimeInterval?
    private var activeActivityCount = 0
    private var scheduledTask: Task<Void, Never>?
    private var scheduledToken: UUID?

    init(
        clock: any InactivityClock = ContinuousInactivityClock(),
        timeout: @escaping @Sendable () -> TimeInterval?
    ) {
        self.clock = clock
        self.timeout = timeout
    }

    func activityStarted() {
        lock.withLock {
            activeActivityCount += 1
            cancelScheduledUnload()
        }
    }

    func activityEnded(unload: @escaping @Sendable () async -> Void) {
        lock.withLock {
            activeActivityCount = max(0, activeActivityCount - 1)
            scheduleUnloadIfIdle(unload: unload)
        }
    }

    func modelBecameReady(unload: @escaping @Sendable () async -> Void) {
        lock.withLock {
            cancelScheduledUnload()
            scheduleUnloadIfIdle(unload: unload)
        }
    }

    func cancel() {
        lock.withLock { cancelScheduledUnload() }
    }

    private func scheduleUnloadIfIdle(unload: @escaping @Sendable () async -> Void) {
        guard activeActivityCount == 0, let seconds = timeout() else { return }
        let token = UUID()
        scheduledToken = token
        let delay = Duration.milliseconds(Int64(seconds * 1_000))
        scheduledTask = Task { [clock] in
            do { try await clock.sleep(for: delay) } catch { return }
            guard self.claimUnload(token: token) else { return }
            await unload()
        }
    }

    private func claimUnload(token: UUID) -> Bool {
        lock.withLock {
            guard scheduledToken == token, activeActivityCount == 0 else { return false }
            scheduledTask = nil
            scheduledToken = nil
            return true
        }
    }

    private func cancelScheduledUnload() {
        scheduledTask?.cancel()
        scheduledTask = nil
        scheduledToken = nil
    }
}
