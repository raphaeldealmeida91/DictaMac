import Darwin
import Foundation

struct MonotonicClock: Sendable {
    let now: @Sendable () -> TimeInterval

    static let live = MonotonicClock {
        var value = timespec()
        clock_gettime(CLOCK_UPTIME_RAW, &value)
        return TimeInterval(value.tv_sec) + TimeInterval(value.tv_nsec) / 1_000_000_000
    }
}
