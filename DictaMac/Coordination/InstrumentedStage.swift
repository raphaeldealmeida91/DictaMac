import Foundation

@MainActor
final class InstrumentedStage {
    private let reporter: any DictationStageReporting

    init(reporter: any DictationStageReporting) {
        self.reporter = reporter
    }

    func run<T>(
        _ stage: DiagnosticStage,
        context: StageContext,
        _ work: () async throws -> T
    ) async throws -> T {
        let startedAt = ContinuousClock.now
        let handle = reporter.begin(stage, context: context)
        do {
            let value = try await work()
            finish(handle, context: context, startedAt: startedAt)
            return value
        } catch {
            finish(handle, context: context, startedAt: startedAt)
            throw error
        }
    }

    private func finish(
        _ handle: DictationStageHandle,
        context: StageContext,
        startedAt: ContinuousClock.Instant
    ) {
        reporter.end(
            handle,
            context: context,
            duration: Self.seconds(startedAt.duration(to: .now))
        )
    }

    private static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
}
