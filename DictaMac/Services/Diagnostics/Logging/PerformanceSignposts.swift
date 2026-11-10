import Foundation
import OSLog

enum PerformanceSignposts {
    static let signposter = OSSignposter(
        subsystem: Bundle.main.bundleIdentifier ?? "DictaMac",
        category: "Pipeline"
    )
}
