import SwiftUI

struct SelectionCorrectionView: View {
    @ObservedObject var viewModel: SelectionCorrectionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            header
            ScrollView {
                Text(viewModel.highlightedText)
                    .font(Theme.Typography.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: Theme.SelectionCorrection.textMaximumHeight)
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
            Label("Correction proposée", systemImage: "text.badge.checkmark")
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
            Button("Copier", action: viewModel.copy)
                .buttonStyle(SecondaryButtonStyle())
                .keyboardShortcut("c", modifiers: .command)
            Button("Remplacer", action: viewModel.replace)
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.return, modifiers: [])
        }
        .disabled(viewModel.state != .suggestion)
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
