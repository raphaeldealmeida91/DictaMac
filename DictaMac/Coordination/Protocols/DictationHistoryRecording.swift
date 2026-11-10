import Foundation

@MainActor
protocol DictationHistoryRecording: AnyObject {
    func record(rawText: String, text: String, targetApplication: String) throws
}
