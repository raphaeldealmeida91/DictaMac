protocol CorrectionLearningSettings: AnyObject, Sendable {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool)
}
