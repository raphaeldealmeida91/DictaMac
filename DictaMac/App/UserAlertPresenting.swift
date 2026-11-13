import AppKit

enum UserAlertStyle: Sendable, Equatable {
    case warning
    case critical
}

struct UserAlert: Sendable {
    let style: UserAlertStyle
    let title: String
    let message: String
    let primaryButton: String
    let secondaryButton: String?
}

enum UserAlertResponse: Sendable {
    case primary
    case secondary
}

@MainActor
protocol UserAlertPresenting: AnyObject, Sendable {
    func present(_ alert: UserAlert) -> UserAlertResponse
    func presentNonBlocking(
        _ alert: UserAlert,
        completion: @escaping @MainActor @Sendable (UserAlertResponse) -> Void
    ) -> Bool
}

extension UserAlertPresenting {
    func presentNonBlocking(
        _ alert: UserAlert,
        completion: @escaping @MainActor @Sendable (UserAlertResponse) -> Void
    ) -> Bool {
        completion(present(alert))
        return true
    }
}

@MainActor
final class NSAlertPresenter: UserAlertPresenting {
    private var presentedAlert: NSAlert?
    private var actionTarget: NonBlockingAlertActionTarget?

    func present(_ request: UserAlert) -> UserAlertResponse {
        let alert = NSAlert()
        alert.alertStyle = request.style == .critical ? .critical : .warning
        alert.messageText = request.title
        alert.informativeText = request.message
        alert.addButton(withTitle: request.primaryButton)
        if let secondaryButton = request.secondaryButton {
            alert.addButton(withTitle: secondaryButton)
        }
        return alert.runModal() == .alertSecondButtonReturn ? .secondary : .primary
    }

    func presentNonBlocking(
        _ request: UserAlert,
        completion: @escaping @MainActor @Sendable (UserAlertResponse) -> Void
    ) -> Bool {
        guard presentedAlert == nil else { return false }
        let alert = makeAlert(request)
        presentedAlert = alert
        if let parent = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }) {
            alert.beginSheetModal(for: parent) { [weak self] response in
                self?.finish(response: response, completion: completion)
            }
        } else {
            let target = NonBlockingAlertActionTarget { [weak self] response in
                self?.finish(response: response, completion: completion)
            }
            actionTarget = target
            alert.buttons.enumerated().forEach { index, button in
                button.tag = index
                button.target = target
                button.action = #selector(NonBlockingAlertActionTarget.respond(_:))
            }
            alert.window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        return true
    }

    private func makeAlert(_ request: UserAlert) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = request.style == .critical ? .critical : .warning
        alert.messageText = request.title
        alert.informativeText = request.message
        alert.addButton(withTitle: request.primaryButton)
        if let secondaryButton = request.secondaryButton { alert.addButton(withTitle: secondaryButton) }
        return alert
    }

    private func finish(
        response: NSApplication.ModalResponse,
        completion: @escaping @MainActor @Sendable (UserAlertResponse) -> Void
    ) {
        if let alert = presentedAlert, let parent = alert.window.sheetParent {
            parent.endSheet(alert.window)
        }
        presentedAlert?.window.orderOut(nil)
        presentedAlert = nil
        actionTarget = nil
        completion(response == .alertSecondButtonReturn ? .secondary : .primary)
    }
}

@MainActor
private final class NonBlockingAlertActionTarget: NSObject {
    private let completion: (NSApplication.ModalResponse) -> Void

    init(completion: @escaping (NSApplication.ModalResponse) -> Void) {
        self.completion = completion
    }

    @objc func respond(_ sender: NSButton) {
        completion(sender.tag == 1 ? .alertSecondButtonReturn : .alertFirstButtonReturn)
    }
}
