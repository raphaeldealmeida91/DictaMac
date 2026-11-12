import Foundation

struct TextWordDiagnosticEntry: Equatable, Sendable {
    let stage: TextWordDiagnosticStage
    let segmentIndex: Int?
    let wordCount: Int
}

struct TextWordDiagnostics: Equatable, Sendable {
    let date: Date
    let entries: [TextWordDiagnosticEntry]
}

@MainActor
protocol TextWordDiagnosticsRecording: Sendable {
    func beginWordDiagnostics()
    func recordWordCount(_ count: Int, stage: TextWordDiagnosticStage, segmentIndex: Int?)
}

extension TextWordDiagnosticsRecording {
    func recordWordCount(_ text: String, stage: TextWordDiagnosticStage, segmentIndex: Int? = nil) {
        recordWordCount(Self.wordCount(text), stage: stage, segmentIndex: segmentIndex)
    }

    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }
}
