#if DEBUG
import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

@MainActor
final class WhisperBenchmarkState: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var status = "Aucun benchmark lancé"
    @Published private(set) var results: [WhisperBenchmarkResult] = []

    private let runner: WhisperBenchmarkRunner

    init(runner: WhisperBenchmarkRunner) {
        self.runner = runner
    }

    func chooseWAVAndRun() {
        let panel = NSOpenPanel()
        panel.title = "Choisir le WAV de benchmark"
        panel.allowedContentTypes = [.wav]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        isRunning = true
        results = []
        status = "Recherche des variantes WhisperKit…"
        Task { [self] in
            let output = await runner.run(wavURL: url) { status in
                Task { @MainActor in self.status = status }
            }
            results = output
            isRunning = false
            status = "Benchmark terminé — \(output.count) modèle(s)"
        }
    }
}
#endif
