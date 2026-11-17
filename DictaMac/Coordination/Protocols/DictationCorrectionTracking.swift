@MainActor
protocol DictationCorrectionTracking: AnyObject {
    func recordInjectedText(_ text: String, targetBundleID: String?)
}
