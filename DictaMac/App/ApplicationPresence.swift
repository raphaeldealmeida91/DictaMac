import AppKit

/// Rend DictaMac visible dans « Forcer à quitter » : macOS n'y liste que les apps `.regular`.
enum ApplicationPresence {
    static let defaultShowsInDock = true

    @MainActor
    static func apply(showsInDock: Bool) {
        NSApp.setActivationPolicy(showsInDock ? .regular : .accessory)
    }
}
