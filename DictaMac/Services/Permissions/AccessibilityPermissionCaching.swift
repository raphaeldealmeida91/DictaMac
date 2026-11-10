protocol AccessibilityPermissionReading: Sendable {
    var isAccessibilityAuthorized: Bool { get }
}

protocol AccessibilityPermissionCaching: AccessibilityPermissionReading {
    func updateAccessibility(_ authorized: Bool)
}
