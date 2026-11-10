import Foundation

enum FirstLaunchStep: Int, CaseIterable, Identifiable {
    case microphone
    case inputMonitoring
    case accessibility
    case readyToDictate

    var id: Self { self }

    var number: Int { rawValue + 1 }

    var title: String {
        switch self {
        case .microphone: "Microphone"
        case .inputMonitoring: "Surveillance de l’entrée"
        case .accessibility: "Accessibilité"
        case .readyToDictate: "Prêt à dicter"
        }
    }

    var permission: AppPermission? {
        switch self {
        case .microphone: .microphone
        case .inputMonitoring: .inputMonitoring
        case .accessibility: .accessibility
        case .readyToDictate: nil
        }
    }
}
