#if DEBUG
import Foundation

struct CleanupBenchmarkCase: Decodable, Sendable {
    let id: String
    let raw: String
    let expected: String
    let usage: String
    let tags: [String]
    let dictionary: [String]

    var context: DictationContext {
        DictationContext(
            bundleID: nil,
            applicationName: nil,
            category: DictationContext.UsageCategory(rawValue: usage) ?? .other
        )
    }
}
#endif
