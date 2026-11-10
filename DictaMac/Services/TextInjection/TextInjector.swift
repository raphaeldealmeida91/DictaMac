import AppKit
import ApplicationServices
import Carbon.HIToolbox

enum TextInjectionError: LocalizedError {
    case accessibilityUnavailable
    case eventCreationFailed

    var errorDescription: String? {
        switch self {
        case .accessibilityUnavailable:
            "L’autorisation Accessibilité est nécessaire pour insérer le texte."
        case .eventCreationFailed:
            "Impossible de simuler le raccourci de collage."
        }
    }
}

@MainActor
protocol TextInjector: AnyObject {
    func insert(_ text: String) -> TextInjectionOutcome
}

enum TextInjectionOutcome: Equatable {
    case pasted
    case copiedToClipboard
}

struct PasteboardItemContents: Equatable {
    let representations: [NSPasteboard.PasteboardType: Data]
}

@MainActor
protocol PasteboardProviding: AnyObject {
    var changeCount: Int { get }

    func readItems() -> [PasteboardItemContents]
    @discardableResult func replaceItems(with items: [PasteboardItemContents]) -> Int
    @discardableResult func writeTransientText(_ text: String) -> Int
    @discardableResult func writeText(_ text: String) -> Int
}

@MainActor
final class GeneralPasteboardProvider: PasteboardProviding {
    private static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    private static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    var changeCount: Int { pasteboard.changeCount }

    func readItems() -> [PasteboardItemContents] {
        (pasteboard.pasteboardItems ?? []).map { item in
            let representations = item.types.reduce(into: [NSPasteboard.PasteboardType: Data]()) { result, type in
                if let data = item.data(forType: type) {
                    result[type] = data
                }
            }
            return PasteboardItemContents(representations: representations)
        }
    }

    @discardableResult
    func replaceItems(with items: [PasteboardItemContents]) -> Int {
        pasteboard.clearContents()
        if !items.isEmpty {
            let pasteboardItems = items.map { contents in
                let item = NSPasteboardItem()
                for (type, data) in contents.representations {
                    item.setData(data, forType: type)
                }
                return item
            }
            pasteboard.writeObjects(pasteboardItems)
        }
        return pasteboard.changeCount
    }

    @discardableResult
    func writeTransientText(_ text: String) -> Int {
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setData(Data(), forType: Self.concealedType)
        item.setData(Data(), forType: Self.transientType)

        pasteboard.clearContents()
        pasteboard.writeObjects([item])
        return pasteboard.changeCount
    }

    @discardableResult
    func writeText(_ text: String) -> Int {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        return pasteboard.changeCount
    }
}

/// Inserts through the pasteboard while deliberately leaving the frontmost app alone.
/// No NSApplication activation or key-window API is used here.
@MainActor
final class ClipboardTextInjector: TextInjector {
    typealias PasteCommand = @MainActor () throws -> Void
    typealias RestoreScheduler = @MainActor (@escaping @MainActor () -> Void) -> Void
    typealias AccessibilityTrustCheck = @MainActor () -> Bool

    private let pasteboard: any PasteboardProviding
    private let permissionCache: any AccessibilityPermissionReading
    private let accessibilityIsTrusted: AccessibilityTrustCheck
    private let canPasteIntoFocusedElement: @MainActor () -> Bool
    private let pasteCommand: PasteCommand
    private let scheduleRestore: RestoreScheduler

    init(
        permissionCache: any AccessibilityPermissionReading,
        pasteboard: any PasteboardProviding = GeneralPasteboardProvider(),
        accessibilityIsTrusted: @escaping AccessibilityTrustCheck = AXIsProcessTrusted,
        canPasteIntoFocusedElement: @escaping @MainActor () -> Bool = ClipboardTextInjector.defaultDestinationCheck,
        pasteCommand: @escaping PasteCommand = ClipboardTextInjector.postPasteCommand,
        scheduleRestore: @escaping RestoreScheduler = ClipboardTextInjector.scheduleDefaultRestore
    ) {
        self.permissionCache = permissionCache
        self.pasteboard = pasteboard
        self.accessibilityIsTrusted = accessibilityIsTrusted
        self.canPasteIntoFocusedElement = canPasteIntoFocusedElement
        self.pasteCommand = pasteCommand
        self.scheduleRestore = scheduleRestore
    }

    func insert(_ text: String) -> TextInjectionOutcome {
        let cachedAuthorization = permissionCache.isAccessibilityAuthorized
        guard (cachedAuthorization || accessibilityIsTrusted()),
              canPasteIntoFocusedElement() else {
            pasteboard.writeText(text)
            return .copiedToClipboard
        }

        let previousItems = pasteboard.readItems()
        let injectionChangeCount = pasteboard.writeTransientText(text)

        do {
            try pasteCommand()
        } catch {
            pasteboard.writeText(text)
            return .copiedToClipboard
        }

        scheduleRestore { [pasteboard] in
            guard pasteboard.changeCount == injectionChangeCount else { return }
            pasteboard.replaceItems(with: previousItems)
        }
        return .pasted
    }

    private func restore(_ items: [PasteboardItemContents], ifUnchangedSince changeCount: Int) {
        guard pasteboard.changeCount == changeCount else { return }
        pasteboard.replaceItems(with: items)
    }

    private static func scheduleDefaultRestore(_ action: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            action()
        }
    }

    private static func postPasteCommand() throws {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            throw TextInjectionError.eventCreationFailed
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    /// Only refuses when the system forbids synthetic input (secure fields such as passwords).
    /// We deliberately do not require the focused element to expose a settable AXValue:
    /// browsers, Electron apps and many web inputs do not, which used to force a manual Cmd+V.
    private static func defaultDestinationCheck() -> Bool {
        !IsSecureEventInputEnabled()
    }
}
