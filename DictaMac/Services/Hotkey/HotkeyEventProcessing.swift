protocol HotkeyEventProcessing: AnyObject, Sendable {
    func enqueue(_ snapshot: HotkeyEventSnapshot)
    func reset(publishRelease: Bool)
}
