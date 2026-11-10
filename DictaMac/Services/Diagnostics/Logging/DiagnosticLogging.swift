import Foundation

protocol DiagnosticLogging: Sendable {
    func stage(
        _ diagnosticStage: DiagnosticStage,
        phase: String,
        duration: TimeInterval?,
        audioDuration: TimeInterval?,
        segmentCount: Int?
    )
    func inputLost()
    func emergencyRecovery(reason: String)
    func emergencyExitAndFlush(reason: String)
    func modelLoadCompleted(duration: TimeInterval, reusedCompiledCache: Bool)
    func modelLoadEnded(
        duration: TimeInterval,
        reusedCompiledCache: Bool?,
        outcome: String
    )
    func memory(context: DiagnosticMemoryContext, bytes: UInt64?)
    func memoryPressure(critical: Bool)
    func mainThreadStall(duration: TimeInterval)
    func eventTapDisabled(reason: String)
}

extension DiagnosticLogging {
    func modelLoadEnded(
        duration: TimeInterval,
        reusedCompiledCache: Bool?,
        outcome: String
    ) {
        modelLoadCompleted(
            duration: duration,
            reusedCompiledCache: reusedCompiledCache ?? false
        )
    }

    func stage(
        _ diagnosticStage: DiagnosticStage,
        phase: String,
        duration: TimeInterval? = nil,
        audioDuration: TimeInterval? = nil,
        segmentCount: Int? = nil
    ) {
        self.stage(
            diagnosticStage,
            phase: phase,
            duration: duration,
            audioDuration: audioDuration,
            segmentCount: segmentCount
        )
    }
}
