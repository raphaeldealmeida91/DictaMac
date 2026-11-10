protocol HotkeyEventTapControlling: AnyObject, Sendable {
    func setEventHandler(_ handler: @escaping @Sendable (HotkeyEventSnapshot) -> Void)
    func start()
    func stop()
    func permissionDidChange(isAuthorized: Bool)
    func reenable()
}
