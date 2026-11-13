import SwiftUI

struct SelectionCorrectionSettingsView: View {
    @StateObject private var viewModel: SelectionCorrectionSettingsViewModel

    init(viewModel: SelectionCorrectionSettingsViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        SettingsSectionContainer(title: "Correction du texte sélectionné") {
            SettingsCard(title: "Détection") {
                SettingsRow(
                    title: "Proposer une correction",
                    description: "Détecte le texte sélectionné dans les autres apps."
                ) {
                    Toggle("", isOn: Binding(
                        get: { viewModel.isEnabled },
                        set: { enabled in viewModel.setEnabled(enabled) }
                    ))
                    .labelsHidden()
                }
                Divider()
                SettingsRow(
                    title: "Repli par copier/coller",
                    description: "Lit aussi les apps qui n’exposent pas leur sélection."
                ) {
                    Toggle("", isOn: $viewModel.usesClipboardFallback).labelsHidden()
                }
            }

            SettingsCard(title: "Confidentialité") {
                SettingsRow(
                    title: "Autoriser le cloud pour cette fonction",
                    description: "Utilise le moteur cloud lorsqu’il est configuré."
                ) {
                    Toggle("", isOn: $viewModel.allowsCloud).labelsHidden()
                }
                InfoCallout(
                    kind: .information,
                    message: "Si cette option est activée, le texte sélectionné est envoyé à OpenAI pour correction."
                )
                .padding(.top, Theme.Spacing.small)
            }

            SettingsCard(title: "Apps exclues", footer: "La détection est désactivée dans ces apps.") {
                excludedApplications
                Divider()
                addApplicationMenu
            }
        }
    }

    private var excludedApplications: some View {
        ForEach(viewModel.excludedApps) { application in
            HStack(spacing: Theme.Spacing.medium) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xSmall) {
                    Text(application.name).font(Theme.Typography.rowTitle)
                    Text(application.bundleID)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    viewModel.removeExcludedApplication(bundleID: application.bundleID)
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Retirer \(application.name)")
            }
            if application.id != viewModel.excludedApps.last?.id { Divider() }
        }
    }

    private var addApplicationMenu: some View {
        Menu("Ajouter une app en cours") {
            if viewModel.availableApplications.isEmpty {
                Text("Aucune app disponible")
            } else {
                ForEach(viewModel.availableApplications) { application in
                    Button(application.name) { viewModel.addExcludedApplication(application) }
                }
            }
        }
        .buttonStyle(SecondaryButtonStyle())
    }
}

#Preview {
    SelectionCorrectionSettingsView(viewModel: SelectionCorrectionSettingsViewModel(
        store: InMemorySettingsStore(),
        permissions: PreviewPermissionManager(store: InMemorySettingsStore()),
        applications: PreviewRunningApplicationProvider(),
        ownBundleID: "com.example.DictaMac",
        setFeatureEnabled: { _ in }
    ))
    .frame(width: Theme.Settings.windowWidth, height: Theme.Settings.windowHeight)
}

@MainActor
private struct PreviewRunningApplicationProvider: RunningApplicationProviding {
    func applications() -> [RunningApplicationInfo] {
        [
            RunningApplicationInfo(name: "Notes", bundleID: "com.apple.Notes"),
            RunningApplicationInfo(name: "Safari", bundleID: "com.apple.Safari")
        ]
    }
}
