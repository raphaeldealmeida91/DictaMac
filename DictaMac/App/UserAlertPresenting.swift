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
}

@MainActor
final class NSAlertPresenter: UserAlertPresenting {
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
}
