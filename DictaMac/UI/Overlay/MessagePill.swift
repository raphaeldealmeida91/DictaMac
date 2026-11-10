import SwiftUI

struct MessagePill: View {
    enum Kind {
        case message
        case error

        var symbol: String {
            switch self {
            case .message: "checkmark.circle.fill"
            case .error: "exclamationmark.circle.fill"
            }
        }

        var tint: Color {
            switch self {
            case .message: .accentColor
            case .error: .orange
            }
        }

        var accessibilityPrefix: String {
            switch self {
            case .message: "Information"
            case .error: "Erreur"
            }
        }
    }

    let kind: Kind
    let message: String

    var body: some View {
        OverlayPillContainer(tint: kind.tint) {
            HStack(spacing: Theme.Overlay.itemSpacing) {
                Image(systemName: kind.symbol)
                    .foregroundStyle(kind.tint)
                Text(message)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(kind.accessibilityPrefix) : \(message)")
    }
}

#Preview("Message") {
    MessagePill(kind: .message, message: "Texte collé")
        .padding(Theme.Spacing.xLarge)
}

#Preview("Erreur") {
    MessagePill(kind: .error, message: "Microphone indisponible")
        .padding(Theme.Spacing.xLarge)
}
