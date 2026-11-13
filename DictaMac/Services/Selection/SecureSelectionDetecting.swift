import Foundation

@MainActor
protocol SecureSelectionDetecting: AnyObject {
    var didEncounterSecureField: Bool { get }
}
