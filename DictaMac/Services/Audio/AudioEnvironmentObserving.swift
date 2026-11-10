protocol AudioEnvironmentObserving: Sendable {
    func start(
        permissionChanged: @escaping @Sendable () -> Void,
        configurationChanged: @escaping @Sendable () -> Void,
        systemWillSleep: @escaping @Sendable () -> Void,
        systemDidWake: @escaping @Sendable () -> Void
    )
    func stop()
}
