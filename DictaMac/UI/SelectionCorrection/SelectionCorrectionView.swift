import SwiftUI

struct SelectionCorrectionView: View {
    @ObservedObject var viewModel: SelectionCorrectionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            header
            if viewModel.state == .engineUnavailable {
                Text(viewModel.engineUnavailableMessage)
                    .font(Theme.Typography.body)
            } else if viewModel.state == .preparing {
                HStack(spacing: Theme.Spacing.small) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Préparation…")
                        .font(Theme.Typography.body)
                }
            } else {
                ScrollView {
                    Text(viewModel.highlightedText)
                        .font(Theme.Typography.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: Theme.SelectionCorrection.textMaximumHeight)
            }
            actions
        }
        .padding(Theme.Spacing.large)
        .frame(width: Theme.SelectionCorrection.panelWidth)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .stroke(.primary.opacity(Theme.Border.standardOpacity), lineWidth: Theme.Border.width)
        }
        .shadow(
            color: .black.opacity(Theme.Shadow.colorOpacity),
            radius: Theme.SelectionCorrection.shadowRadius,
            y: Theme.SelectionCorrection.shadowY
        )
    }

    private var header: some View {
        HStack {
            Label(
                headerTitle,
                systemImage: headerSymbol
            )
                .font(Theme.Typography.rowTitle)
            Spacer()
            if viewModel.state == .copied {
                Label("Copié", systemImage: "checkmark")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: Theme.Spacing.small) {
            Spacer()
            if viewModel.state == .engineUnavailable {
                Button("Charger le modèle local", action: viewModel.loadLocalModel)
                    .buttonStyle(SecondaryButtonStyle())
                Button("Activer le cloud", action: viewModel.activateCloud)
                    .buttonStyle(PrimaryButtonStyle())
            } else if viewModel.state != .preparing {
                Button("Copier", action: viewModel.copy)
                    .buttonStyle(SecondaryButtonStyle())
                    .keyboardShortcut("c", modifiers: .command)
                Button("Remplacer", action: viewModel.replace)
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.return, modifiers: [])
            }
        }
    }

    private var headerTitle: String {
        switch viewModel.state {
        case .engineUnavailable: "Correction indisponible"
        case .preparing: "Correction"
        default: "Correction proposée"
        }
    }

    private var headerSymbol: String {
        switch viewModel.state {
        case .engineUnavailable: "exclamationmark.circle"
        case .preparing: "hourglass"
        default: "text.badge.checkmark"
        }
    }
}

#Preview {
    SelectionCorrectionView(viewModel: SelectionCorrectionViewModel(
        replacer: PreviewSelectionReplacer(),
        clipboard: PreviewSelectionClipboard()
    ))
    .padding()
}

@MainActor
private final class PreviewSelectionReplacer: SelectionReplacing {
    func replace(
        _ correction: SelectionCorrection,
        for snapshot: SelectionSnapshot
    ) -> SelectionReplacementOutcome { .replaced }
}

@MainActor
private final class PreviewSelectionClipboard: SelectionClipboardCopying {
    func copy(_ text: String) {}
}
