import Darwin
import Foundation

enum MonotonicClock {
    static var now: TimeInterval {
        var value = timespec()
        clock_gettime(CLOCK_MONOTONIC_RAW, &value)
        return TimeInterval(value.tv_sec) + TimeInterval(value.tv_nsec) / 1_000_000_000
    }
}
