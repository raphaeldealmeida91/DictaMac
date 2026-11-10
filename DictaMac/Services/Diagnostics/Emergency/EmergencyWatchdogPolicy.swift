import Foundation

struct EmergencyWatchdogPolicy: Sendable {
    struct Configuration: Sendable {
        var mainThreadTimeout: TimeInterval = 5
        var finalTranscriptionBudget: TimeInterval = 8
        var cleanupBudget: TimeInterval = 10
        var injectionBudget: TimeInterval = 2
        var recoveryGracePeriod: TimeInterval = 3
        var absoluteMemoryLimit: UInt64 = 6 * 1_024 * 1_024 * 1_024
        var physicalMemory: UInt64

        var memoryLimit: UInt64 { min(absoluteMemoryLimit, physicalMemory / 2) }

        func budget(for stage: EmergencyStage) -> TimeInterval {
            switch stage {
            case .finalTranscription: finalTranscriptionBudget
            case .cleanup: cleanupBudget
            case .injection: injectionBudget
            }
        }
    }

    struct Snapshot: Sendable {
        var now: TimeInterval
        var mainHeartbeat: TimeInterval
        var stage: EmergencyStage?
        var stageStartedAt: TimeInterval?
        var physicalFootprint: UInt64?
    }

    enum Decision: Equatable, Sendable {
        case none
        case recover(reason: String)
        case exit(reason: String)
    }

    let configuration: Configuration
    private(set) var recoveryStartedAt: TimeInterval?
    private(set) var recoveryReason: String?

    mutating func evaluate(_ snapshot: Snapshot) -> Decision {
        guard let reason = breachReason(snapshot) else {
            recoveryStartedAt = nil
            recoveryReason = nil
            return .none
        }
        if recoveryStartedAt == nil || recoveryReason != reason {
            recoveryStartedAt = snapshot.now
            recoveryReason = reason
            return .recover(reason: reason)
        }
        guard let recoveryStartedAt,
              snapshot.now - recoveryStartedAt >= configuration.recoveryGracePeriod else {
            return .none
        }
        return .exit(reason: reason)
    }

    private func breachReason(_ snapshot: Snapshot) -> String? {
        if snapshot.now - snapshot.mainHeartbeat > configuration.mainThreadTimeout {
            return "main_thread_stall"
        }
        if let stage = snapshot.stage,
           let startedAt = snapshot.stageStartedAt,
           snapshot.now - startedAt > configuration.budget(for: stage) {
            return "stage_timeout_\(stage.rawValue)"
        }
        if let footprint = snapshot.physicalFootprint,
           footprint > configuration.memoryLimit {
            return "memory_limit"
        }
        return nil
    }
}
