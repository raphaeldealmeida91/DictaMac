import Foundation

protocol AudioEmergencyStopRegistering: Sendable {
    func install(_ handler: @escaping @Sendable (TimeInterval) -> Bool)
}

extension EmergencyAudioRegistry: AudioEmergencyStopRegistering {}
