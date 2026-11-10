protocol AudioEnvironmentObserving: Sendable {
    func start(
        permissionChanged: @escaping @Sendable () -> Void,
        configurationChanged: @escaping @Sendable () -> Void
    )
    func stop()
}
