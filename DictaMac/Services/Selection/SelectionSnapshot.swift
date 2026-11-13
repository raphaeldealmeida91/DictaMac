import CoreGraphics

struct SelectionSnapshot: Equatable, Sendable {
    let text: String
    let screenRect: CGRect?
    let sourceBundleID: String?
    let isSecure: Bool
}
