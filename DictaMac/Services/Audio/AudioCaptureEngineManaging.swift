import Foundation

protocol AudioCaptureEngineManaging: Sendable {
    func start() throws
    func stop()
    func prepareWhenIdle()
    func handleConfigurationChange(
        shouldPrepare: Bool,
        completion: @escaping @Sendable (Bool) -> Void
    )
    func handlePermissionRevocation(
        completion: @escaping @Sendable (Bool) -> Void
    )
    func emergencyStop(timeout: TimeInterval) -> Bool
}
