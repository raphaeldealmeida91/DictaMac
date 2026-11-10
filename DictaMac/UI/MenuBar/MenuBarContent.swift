import AppKit
import SwiftUI

struct MenuBarContent: View {
    @ObservedObject private var activity: AppActivityModel
    @ObservedObject private var transcriptionState: TranscriptionModelState
    @ObservedObject private var cleanupState: LocalCleanupModelState
    @ObservedObject private var history: TranscriptionHistoryStore
    @State private var copiedEntryID: UUID?
    private let textCleanupSettings: any TextCleanupSettings

    init(environment: AppEnvironment) {
        activity = environment.activity
        transcriptionState = environment.transcriptionState
        cleanupState = environment.cleanupModelState
        history = environment.history
        textCleanupSettings = environment.textCleanupSettings
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.large) {
            header
            Divider()
            historySection
            Divider()
            footer
        }
        .padding(Theme.Spacing.large)
        .frame(width: Theme.MenuBar.width)
        .background(.regularMaterial)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            HStack {
                Label("DictaMac", systemImage: "waveform.badge.mic")
                    .font(.title3.weight(.semibold))
                Spacer()
                Text(activityLabel)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(.secondary)
            }
            modelStatus(title: "Whisper", ready: transcriptionState.isReady, status: transcriptionState.status)
            if textCleanupSettings.configuredEngine == .local {
                modelStatus(title: "LLM local", ready: cleanupState.isReady, status: cleanupState.status)
            }
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            Text("Dernières dictées")
                .font(Theme.Typography.sectionTitle)
            if history.entries.isEmpty {
                Text("Aucune dictée pour le moment")
                    .font(Theme.Typography.description)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: Theme.MenuBar.historyRowHeight)
            } else {
                ForEach(history.entries.prefix(Theme.MenuBar.historyLimit)) { entry in
                    historyButton(entry)
                }
            }
        }
    }

    private func modelStatus(title: String, ready: Bool, status: String) -> some View {
        HStack(spacing: Theme.Spacing.small) {
            Circle()
                .fill(ready ? Color.accentColor : Color.secondary)
                .frame(width: Theme.MenuBar.statusDotSize, height: Theme.MenuBar.statusDotSize)
            Text(title)
                .font(Theme.Typography.rowTitle)
            Spacer()
            Text(ready ? "Prêt" : status)
                .font(Theme.Typography.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    private func historyButton(_ entry: TranscriptionHistoryEntry) -> some View {
        Button { copy(entry) } label: {
            HStack(spacing: Theme.Spacing.medium) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xSmall) {
                    Text(excerpt(for: entry))
                        .lineLimit(1)
                    if let rawText = entry.rawText, rawText != entry.text {
                        Text("Brut : \(excerpt(rawText))")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Text("\(entry.date.formatted(date: .omitted, time: .shortened)) · \(entry.targetApplication)")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if copiedEntryID == entry.id {
                    Label("Copié", systemImage: "checkmark.circle.fill")
                        .font(Theme.Typography.caption.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                } else {
                    Image(systemName: "doc.on.doc")
                        .foregroundStyle(Color.secondary)
                        .accessibilityLabel("Copier")
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(minHeight: Theme.MenuBar.historyRowHeight)
    }

    private var footer: some View {
        HStack(spacing: Theme.Spacing.small) {
            SettingsLink {
                Label("Réglages…", systemImage: "gearshape")
            }
            .buttonStyle(SecondaryButtonStyle())
            Spacer()
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quitter", systemImage: "power")
            }
            .buttonStyle(SecondaryButtonStyle())
            .keyboardShortcut("q")
        }
    }

    private var activityLabel: String {
        switch activity.state {
        case .idle: "Prêt"
        case .recording: "Enregistrement"
        case .transcribing, .injecting: "Transcription"
        }
    }

    private func excerpt(for entry: TranscriptionHistoryEntry) -> String {
        excerpt(entry.text)
    }

    private func excerpt(_ text: String) -> String {
        let oneLine = text.replacingOccurrences(of: "\n", with: " ")
        guard oneLine.count > Theme.MenuBar.excerptLimit else { return oneLine }
        return String(oneLine.prefix(Theme.MenuBar.excerptLimit)) + "…"
    }

    private func copy(_ entry: TranscriptionHistoryEntry) {
        history.copyToPasteboard(entry)
        copiedEntryID = entry.id
        Task {
            try? await Task.sleep(for: Theme.MenuBar.copiedFeedbackDuration)
            guard copiedEntryID == entry.id else { return }
            copiedEntryID = nil
        }
    }
}
