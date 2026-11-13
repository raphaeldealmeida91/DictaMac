import Foundation

struct TextChange: Equatable, Sendable {
    let range: NSRange
    let replacement: String
}
