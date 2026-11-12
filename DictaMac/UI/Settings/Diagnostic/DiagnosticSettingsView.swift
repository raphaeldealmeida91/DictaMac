import SwiftUI

struct DiagnosticSettingsView: View {
    @StateObject private var viewModel: DiagnosticSettingsViewModel

    init(viewModel: DiagnosticSettingsViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        SettingsSectionContainer(title: "Diagnostic") {
            SettingsCard(
                title: "Dernière dictée",
                footer: timingDateDescription
            ) {
                if let timings = viewModel.timings {
                    timingTable(timings)
                } else {
                    Text("Aucune mesure disponible.")
                        .font(Theme.Typography.description)
                        .foregroundStyle(.secondary)
                }
                if let diagnostics = viewModel.wordDiagnostics {
                    Divider()
                    wordCountTable(diagnostics)
                }
            }

            SettingsCard(
                title: "Journaux",
                footer: "Les journaux contiennent les étapes techniques et les mesures, jamais le texte dicté."
            ) {
                SettingsRow(title: "Fichiers de diagnostic", description: "Utiles pour analyser un blocage ou un échec.") {
                    Button("Ouvrir le dossier", action: viewModel.openLogsDirectory)
                        .buttonStyle(SecondaryButtonStyle())
                }
            }

            #if DEBUG
            benchmarkCard
            #endif
        }
    }

    private var timingDateDescription: String? {
        viewModel.timings?.date.formatted(.dateTime.day().month().hour().minute().second())
    }

    private func timingTable(_ timings: DictationTimings) -> some View {
        Grid(alignment: .leading, horizontalSpacing: Theme.Spacing.xLarge, verticalSpacing: Theme.Spacing.small) {
            timingRow("Arrêt audio", seconds: timings.stopAudio)
            timingRow("Transcription", seconds: timings.transcription)
            timingRow("Nettoyage — \(timings.cleanupEngine.title)", seconds: timings.cleanup)
            timingRow("Injection", seconds: timings.injection)
            Divider()
            timingRow("Total relâchement → collage", seconds: timings.total, emphasized: true)
        }
    }

    private func timingRow(_ title: String, seconds: TimeInterval, emphasized: Bool = false) -> some View {
        GridRow {
            Text(title).fontWeight(emphasized ? .semibold : .regular)
            Spacer()
            (Text(seconds, format: .number.precision(
                .fractionLength(Theme.Settings.timingFractionDigits)
            )) + Text(" s"))
                .fontWeight(emphasized ? .semibold : .regular)
                .monospacedDigit()
        }
    }

    private func wordCountTable(_ diagnostics: TextWordDiagnostics) -> some View {
        Grid(alignment: .leading, horizontalSpacing: Theme.Spacing.xLarge, verticalSpacing: Theme.Spacing.small) {
            ForEach(Array(diagnostics.entries.enumerated()), id: \.offset) { _, entry in
                GridRow {
                    Text(wordCountTitle(entry))
                    Spacer()
                    Text("\(entry.wordCount) mots")
                        .monospacedDigit()
                }
            }
        }
    }

    private func wordCountTitle(_ entry: TextWordDiagnosticEntry) -> String {
        guard let segmentIndex = entry.segmentIndex else { return entry.stage.title }
        return "\(entry.stage.title) \(segmentIndex + 1)"
    }

    #if DEBUG
    private var benchmarkCard: some View {
        SettingsCard(
            title: "Benchmark Whisper",
            footer: "Disponible uniquement dans les versions de développement."
        ) {
            HStack(spacing: Theme.Spacing.medium) {
                Text(viewModel.benchmarkStatus)
                    .font(Theme.Typography.description)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Choisir un WAV…", action: viewModel.chooseWAVAndRunBenchmark)
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(viewModel.benchmarkIsRunning)
            }
            ForEach(viewModel.benchmarkResults, id: \WhisperBenchmarkResult.id) { result in
                benchmarkResult(result)
            }
        }
    }

    private func benchmarkResult(_ result: WhisperBenchmarkResult) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xSmall) {
            HStack {
                Text(result.model).fontWeight(.semibold)
                Spacer()
                (Text(result.duration, format: .number.precision(
                    .fractionLength(Theme.Settings.timingFractionDigits)
                )) + Text(" s"))
            }
            Text(result.error ?? result.text)
                .font(Theme.Typography.caption)
                .foregroundStyle(result.error == nil ? Color.secondary : Color.red)
                .textSelection(.enabled)
        }
        .padding(Theme.Spacing.medium)
        .background(.quaternary.opacity(Theme.Border.standardOpacity), in: RoundedRectangle(
            cornerRadius: Theme.Radius.control
        ))
    }
    #endif
}

#Preview {
    #if DEBUG
    DiagnosticSettingsView(viewModel: DiagnosticSettingsViewModel(
        diagnostics: PreviewDiagnostics(store: InMemorySettingsStore(), lastTimings: .preview),
        logOpener: PreviewDiagnosticLogOpener(),
        benchmark: PreviewBenchmarkManager()
    ))
    .frame(width: Theme.Settings.windowWidth, height: Theme.Settings.windowHeight)
    #else
    DiagnosticSettingsView(viewModel: DiagnosticSettingsViewModel(
        diagnostics: PreviewDiagnostics(store: InMemorySettingsStore(), lastTimings: .preview),
        logOpener: PreviewDiagnosticLogOpener()
    ))
    .frame(width: Theme.Settings.windowWidth, height: Theme.Settings.windowHeight)
    #endif
}
