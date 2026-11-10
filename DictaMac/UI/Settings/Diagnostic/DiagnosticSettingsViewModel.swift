import Combine
import Foundation

@MainActor
final class DiagnosticSettingsViewModel: ObservableObject {
    @Published private(set) var timings: DictationTimings?
    #if DEBUG
    @Published private(set) var benchmarkIsRunning = false
    @Published private(set) var benchmarkStatus = ""
    @Published private(set) var benchmarkResults: [WhisperBenchmarkResult] = []
    #endif

    private let openLogs: () -> Void
    private let readTimings: () -> DictationTimings?
    #if DEBUG
    private let runBenchmark: () -> Void
    private let readBenchmark: () -> (Bool, String, [WhisperBenchmarkResult])
    #endif
    private var cancellables = Set<AnyCancellable>()

    #if DEBUG
    init<Diagnostics: DictationDiagnosticsProviding, Benchmark: BenchmarkManaging>(
        diagnostics: Diagnostics,
        logOpener: any DiagnosticLogOpening,
        benchmark: Benchmark
    ) {
        openLogs = logOpener.openLogsDirectory
        readTimings = { diagnostics.lastTimings }
        runBenchmark = benchmark.chooseWAVAndRun
        readBenchmark = { (benchmark.isRunning, benchmark.status, benchmark.results) }
        observe(benchmark.objectWillChange)
        observe(diagnostics.objectWillChange)
        synchronize()
    }
    #else
    init<Diagnostics: DictationDiagnosticsProviding>(
        diagnostics: Diagnostics,
        logOpener: any DiagnosticLogOpening
    ) {
        openLogs = logOpener.openLogsDirectory
        readTimings = { diagnostics.lastTimings }
        observe(diagnostics.objectWillChange)
        synchronize()
    }
    #endif

    func openLogsDirectory() {
        openLogs()
    }

    #if DEBUG
    func chooseWAVAndRunBenchmark() {
        runBenchmark()
    }
    #endif

    private func observe<PublisherType: Publisher>(_ publisher: PublisherType)
    where PublisherType.Output == Void, PublisherType.Failure == Never {
        publisher.sink { [weak self] in
            Task { @MainActor in
                await Task.yield()
                self?.synchronize()
            }
        }
        .store(in: &cancellables)
    }

    private func synchronize() {
        timings = readTimings()
        #if DEBUG
        let benchmark = readBenchmark()
        benchmarkIsRunning = benchmark.0
        benchmarkStatus = benchmark.1
        benchmarkResults = benchmark.2
        #endif
    }
}
