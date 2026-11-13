import AppKit
import Carbon.HIToolbox

@MainActor
final class ClipboardSelectedTextReader: SelectedTextReading {
    typealias CopyCommand = @MainActor () -> Bool
    typealias ChangeWaiter = @MainActor (_ initialCount: Int, _ pasteboard: any PasteboardProviding) -> Bool
    typealias SourceBundleIDProvider = @MainActor () -> String?
    typealias SecureInputCheck = @MainActor () -> Bool

    static let copyWaitDuration = TimeInterval(0.15)
    static let pollingInterval = TimeInterval(0.01)

    private let pasteboard: any PasteboardProviding
    private let copyCommand: CopyCommand
    private let changeWaiter: ChangeWaiter
    private let sourceBundleIDProvider: SourceBundleIDProvider
    private let secureInputCheck: SecureInputCheck

    init(
        pasteboard: any PasteboardProviding,
        copyCommand: @escaping CopyCommand = ClipboardSelectedTextReader.postCopyCommand,
        changeWaiter: @escaping ChangeWaiter = ClipboardSelectedTextReader.waitForChange,
        sourceBundleIDProvider: @escaping SourceBundleIDProvider,
        secureInputCheck: @escaping SecureInputCheck = IsSecureEventInputEnabled
    ) {
        self.pasteboard = pasteboard
        self.copyCommand = copyCommand
        self.changeWaiter = changeWaiter
        self.sourceBundleIDProvider = sourceBundleIDProvider
        self.secureInputCheck = secureInputCheck
    }

    func readSelection() -> SelectionSnapshot? {
        guard !secureInputCheck() else { return nil }
        let originalItems = pasteboard.readItems()
        let initialCount = pasteboard.changeCount
        let sourceBundleID = sourceBundleIDProvider()
        defer { pasteboard.replaceItems(with: originalItems) }

        guard copyCommand(), changeWaiter(initialCount, pasteboard),
              let text = copiedText(from: pasteboard.readItems()) else {
            return nil
        }
        return SelectionSnapshot(
            text: text,
            screenRect: nil,
            sourceBundleID: sourceBundleID,
            isSecure: false
        )
    }

    private func copiedText(from items: [PasteboardItemContents]) -> String? {
        guard let data = items.first?.representations[.string] else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func waitForChange(
        initialCount: Int,
        pasteboard: any PasteboardProviding
    ) -> Bool {
        let deadline = Date().addingTimeInterval(copyWaitDuration)
        while pasteboard.changeCount == initialCount && Date() < deadline {
            _ = RunLoop.current.run(
                mode: .default,
                before: min(Date().addingTimeInterval(pollingInterval), deadline)
            )
        }
        return pasteboard.changeCount != initialCount
    }

    private static func postCopyCommand() -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: false) else {
            return false
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }
}
