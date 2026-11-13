protocol SelectionCorrectionService: Sendable {
    func correct(_ text: String, dictionary: [String]) async throws -> SelectionCorrection
    func engineStatus() async -> SelectionCorrectionEngine
    func engineUnavailableMessage() async -> String?
    func prepare() async
}

extension SelectionCorrectionService {
    func engineStatus() async -> SelectionCorrectionEngine { .rulesOnly }
    func engineUnavailableMessage() async -> String? { nil }
    func prepare() async {}
}

enum SelectionCorrectionEngine: String, Equatable, Sendable {
    case cloud
    case local
    case rulesOnly
}
