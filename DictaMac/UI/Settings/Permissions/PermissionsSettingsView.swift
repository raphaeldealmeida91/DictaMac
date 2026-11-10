import SwiftUI

struct PermissionsSettingsView: View {
    @StateObject private var viewModel: PermissionsSettingsViewModel

    init(viewModel: PermissionsSettingsViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        SettingsSectionContainer(title: "Autorisations") {
            SettingsCard(
                title: "Accès système",
                footer: "Le microphone enregistre la voix, la surveillance détecte fn et l’accessibilité colle le texte."
            ) {
                ForEach(viewModel.permissions) { permission in
                    permissionRow(permission)
                    if permission != viewModel.permissions.last {
                        Divider()
                    }
                }
            }

            InfoCallout(
                kind: .information,
                message: "Dans Réglages Système → Clavier, réglez « Appuyer sur 🌐 pour » sur « Ne rien faire » afin de réserver fn à DictaMac."
            )
        }
        .onAppear(perform: viewModel.appear)
        .onDisappear(perform: viewModel.disappear)
    }

    private func permissionRow(_ permission: AppPermission) -> some View {
        let status = viewModel.status(for: permission)
        return SettingsRow(title: permission.title, description: status.description) {
            HStack(spacing: Theme.Spacing.medium) {
                Label(status.badgeTitle, systemImage: status.badgeSymbol)
                    .font(Theme.Typography.caption.weight(.medium))
                    .foregroundStyle(status.isAuthorized ? Color.accentColor : Color.orange)
                    .accessibilityLabel(status.badgeTitle)
                Button("Autoriser") { viewModel.request(permission) }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(status.isAuthorized)
                Button("Réglages Système") { viewModel.openSystemSettings(for: permission) }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
    }
}

private extension PermissionStatus {
    var badgeTitle: String {
        isAuthorized ? "Accordée" : "À accorder"
    }

    var badgeSymbol: String {
        isAuthorized ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
    }

    var description: String {
        switch self {
        case .authorized: "DictaMac dispose de cet accès."
        case .notDetermined: "Cette autorisation n’a pas encore été demandée."
        case .denied: "Autorisez cet accès pour utiliser toutes les fonctions."
        }
    }
}

#Preview {
    PermissionsSettingsView(viewModel: PermissionsSettingsViewModel(
        manager: PreviewPermissionManager(store: InMemorySettingsStore())
    ))
    .frame(width: Theme.Settings.windowWidth, height: Theme.Settings.windowHeight)
}
