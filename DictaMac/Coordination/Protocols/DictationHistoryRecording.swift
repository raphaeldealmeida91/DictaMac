import Foundation

@MainActor
protocol DictationHistoryRecording: AnyObject {
    func record(text: String, targetApplication: String) throws
}
