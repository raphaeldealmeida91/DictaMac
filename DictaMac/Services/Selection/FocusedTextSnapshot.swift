import Foundation

struct FocusedTextSnapshot: Equatable, Sendable {
    let text: String
    let sourceBundleID: String?
    let isSecure: Bool
}
