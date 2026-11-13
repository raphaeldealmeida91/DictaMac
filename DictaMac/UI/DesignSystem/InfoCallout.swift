import SwiftUI

struct InfoCallout: View {
    enum Kind {
        case information
        case warning

        var symbol: String {
            switch self {
            case .information: "info.circle.fill"
            case .warning: "exclamationmark.triangle.fill"
            }
        }

        var tint: Color {
            switch self {
            case .information: .accentColor
            case .warning: .orange
            }
        }
    }

    let kind: Kind
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?

    init(
        kind: Kind,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.kind = kind
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.medium) {
            Label {
                Text(message)
                    .font(Theme.Typography.description)
            } icon: {
                Image(systemName: kind.symbol)
                    .foregroundStyle(kind.tint)
            }
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(Theme.Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(kind.tint.opacity(Theme.Border.standardOpacity), in: RoundedRectangle(
            cornerRadius: Theme.Radius.callout
        ))
    }
}

#Preview {
    VStack(spacing: Theme.Spacing.medium) {
        InfoCallout(kind: .information, message: "Aucune donnée ne quitte ce Mac.")
        InfoCallout(kind: .warning, message: "La mémoire disponible est faible.")
    }
    .padding(Theme.Spacing.xLarge)
}
