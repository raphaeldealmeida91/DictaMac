import Foundation

protocol InactivityClock: Sendable {
    func sleep(for duration: Duration) async throws
}

struct ContinuousInactivityClock: InactivityClock {
    func sleep(for duration: Duration) async throws {
        try await ContinuousClock().sleep(for: duration)
    }
}
