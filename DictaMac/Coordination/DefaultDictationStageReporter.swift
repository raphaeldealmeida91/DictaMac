import Foundation
import OSLog

@MainActor
final class DefaultDictationStageReporter: DictationStageReporting {
    private let persistentLog: PersistentDiagnosticLog
    private let emergencyRuntime: EmergencyRuntime
    private var intervals: [UUID: OSSignpostIntervalState] = [:]

    init(
        persistentLog: PersistentDiagnosticLog,
        emergencyRuntime: EmergencyRuntime
    ) {
        self.persistentLog = persistentLog
        self.emergencyRuntime = emergencyRuntime
    }

    func begin(_ stage: DiagnosticStage, context: StageContext) -> DictationStageHandle {
        persistentLog.stage(
            stage,
            phase: "begin",
            audioDuration: context.audioDuration,
            segmentCount: context.segmentCount
        )
        beginEmergencyStage(for: stage)
        let handle = DictationStageHandle(id: UUID(), stage: stage)
        intervals[handle.id] = beginSignpost(for: stage, detail: context.detail)
        return handle
    }

    func end(_ handle: DictationStageHandle, context: StageContext, duration: TimeInterval) {
        if let interval = intervals.removeValue(forKey: handle.id) {
            endSignpost(for: handle.stage, interval: interval)
        }
        endEmergencyStage(for: handle.stage)
        persistentLog.stage(
            handle.stage,
            phase: "end",
            duration: duration,
            audioDuration: context.audioDuration,
            segmentCount: context.segmentCount
        )
    }

    func report(_ stage: DiagnosticStage, phase: String, context: StageContext) {
        persistentLog.stage(
            stage,
            phase: phase,
            audioDuration: context.audioDuration,
            segmentCount: context.segmentCount
        )
    }

    func reportInputLost() {
        persistentLog.inputLost()
    }

    func setRuntimeIdle(_ isIdle: Bool) {
        emergencyRuntime.setIdle(isIdle)
    }

    private func beginEmergencyStage(for stage: DiagnosticStage) {
        guard let emergencyStage = emergencyStage(for: stage) else { return }
        emergencyRuntime.begin(emergencyStage)
    }

    private func endEmergencyStage(for stage: DiagnosticStage) {
        guard let emergencyStage = emergencyStage(for: stage) else { return }
        emergencyRuntime.end(emergencyStage)
    }

    private func emergencyStage(for stage: DiagnosticStage) -> EmergencyStage? {
        switch stage {
        case .transcription: .finalTranscription
        case .cleanup: .cleanup
        case .injection: .injection
        case .modelLoad, .recording: nil
        }
    }

    private func beginSignpost(
        for stage: DiagnosticStage,
        detail: String?
    ) -> OSSignpostIntervalState {
        switch stage {
        case .transcription:
            PerformanceSignposts.signposter.beginInterval("Transcription")
        case .cleanup:
            PerformanceSignposts.signposter.beginInterval(
                "Cleanup",
                "engine=\(detail ?? "unknown", privacy: .public)"
            )
        case .injection:
            PerformanceSignposts.signposter.beginInterval("Injection")
        case .modelLoad:
            PerformanceSignposts.signposter.beginInterval("ModelLoad")
        case .recording:
            PerformanceSignposts.signposter.beginInterval("Recording")
        }
    }

    private func endSignpost(
        for stage: DiagnosticStage,
        interval: OSSignpostIntervalState
    ) {
        switch stage {
        case .transcription:
            PerformanceSignposts.signposter.endInterval("Transcription", interval)
        case .cleanup:
            PerformanceSignposts.signposter.endInterval("Cleanup", interval)
        case .injection:
            PerformanceSignposts.signposter.endInterval("Injection", interval)
        case .modelLoad:
            PerformanceSignposts.signposter.endInterval("ModelLoad", interval)
        case .recording:
            PerformanceSignposts.signposter.endInterval("Recording", interval)
        }
    }
}
