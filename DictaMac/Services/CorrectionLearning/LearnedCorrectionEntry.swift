import Foundation

struct LearnedCorrectionEntry: Codable, Equatable, Identifiable, Sendable {
    enum Status: String, Codable, Sendable {
        case observed
        case accepted
        case refused
    }

    let id: UUID
    let dictated: String
    let corrected: String
    var occurrenceCount: Int
    var lastSeen: Date
    var status: Status
}
