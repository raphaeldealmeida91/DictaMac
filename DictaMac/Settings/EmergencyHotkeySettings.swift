@preconcurrency import ApplicationServices

protocol EmergencyHotkeySettings: Sendable {
    var configuredModifiers: CGEventFlags { get }
}
