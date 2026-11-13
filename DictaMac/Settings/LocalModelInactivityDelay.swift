import Foundation

enum LocalModelInactivityDelay: TimeInterval, CaseIterable, Identifiable, Sendable {
    case twoMinutes = 120
    case fiveMinutes = 300
    case fifteenMinutes = 900
    case never = 0

    var id: TimeInterval { rawValue }

    var title: String {
        switch self {
        case .twoMinutes: "2 min"
        case .fiveMinutes: "5 min"
        case .fifteenMinutes: "15 min"
        case .never: "Jamais"
        }
    }

    static func storedValue(_ value: TimeInterval?) -> LocalModelInactivityDelay {
        guard let value else { return .never }
        return Self(rawValue: value) ?? .fiveMinutes
    }
}
