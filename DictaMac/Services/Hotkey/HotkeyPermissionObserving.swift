protocol HotkeyPermissionObserving: Sendable {
    func start(_ handler: @escaping @Sendable (Bool) -> Void)
    func stop()
}
