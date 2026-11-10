import Foundation

struct StageContext: Sendable {
    let audioDuration: TimeInterval?
    let segmentCount: Int?
    let detail: String?

    init(
        audioDuration: TimeInterval? = nil,
        segmentCount: Int? = nil,
        detail: String? = nil
    ) {
        self.audioDuration = audioDuration
        self.segmentCount = segmentCount
        self.detail = detail
    }
}

struct DictationStageHandle: Sendable {
    let id: UUID
    let stage: DiagnosticStage
}

@MainActor
protocol DictationStageReporting: AnyObject {
    func begin(_ stage: DiagnosticStage, context: StageContext) -> DictationStageHandle
    func end(_ handle: DictationStageHandle, context: StageContext, duration: TimeInterval)
    func report(_ stage: DiagnosticStage, phase: String, context: StageContext)
    func reportInputLost()
    func setRuntimeIdle(_ isIdle: Bool)
}
