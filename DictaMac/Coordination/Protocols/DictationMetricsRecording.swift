@MainActor
protocol DictationMetricsRecording: AnyObject {
    func record(_ timings: DictationTimings)
}
