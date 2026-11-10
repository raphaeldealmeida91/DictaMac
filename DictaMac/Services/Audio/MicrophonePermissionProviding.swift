@preconcurrency import AVFoundation

protocol MicrophonePermissionProviding: Sendable {
    var isAuthorized: Bool { get }
    var statusDescription: String { get }
}

struct SystemMicrophonePermissionProvider: MicrophonePermissionProviding {
    var isAuthorized: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    var statusDescription: String {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined: "non demandée"
        case .restricted: "restreinte"
        case .denied: "refusée"
        case .authorized: "autorisée"
        @unknown default: "inconnue"
        }
    }
}
