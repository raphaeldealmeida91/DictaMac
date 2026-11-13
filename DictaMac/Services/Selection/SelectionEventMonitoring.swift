import Foundation

@MainActor
protocol SelectionEventMonitoring: AnyObject {
    func events() -> AsyncStream<Void>
    func stop()
}
