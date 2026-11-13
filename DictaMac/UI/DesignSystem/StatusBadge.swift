import SwiftUI

struct StatusBadge: View {
    enum Status: Equatable {
        case inactive
        case ready
        case loading
        case error

        var label: String {
            switch self {
            case .inactive: "Inactif"
            case .ready: "Prêt"
            case .loading: "Chargement"
            case .error: "Erreur"
            }
        }

        var symbol: String {
            switch self {
            case .inactive: "pause.circle.fill"
            case .ready: "checkmark.circle.fill"
            case .loading: "clock.fill"
            case .error: "exclamationmark.circle.fill"
            }
        }

        var tint: Color {
            switch self {
            case .inactive: .secondary
            case .ready: .accentColor
            case .loading: .secondary
            case .error: .red
            }
        }
    }

    let status: Status

    var body: some View {
        Label(status.label, systemImage: status.symbol)
            .font(Theme.Typography.caption.weight(.medium))
            .foregroundStyle(status.tint)
            .padding(.horizontal, Theme.Spacing.small)
            .padding(.vertical, Theme.Spacing.xSmall)
            .background(status.tint.opacity(Theme.Border.standardOpacity), in: Capsule())
            .accessibilityLabel(status.label)
    }
}

#Preview {
    HStack(spacing: Theme.Spacing.small) {
        StatusBadge(status: .inactive)
        StatusBadge(status: .ready)
        StatusBadge(status: .loading)
        StatusBadge(status: .error)
    }
    .padding(Theme.Spacing.xLarge)
}
