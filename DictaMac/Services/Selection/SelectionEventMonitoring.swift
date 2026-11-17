import Foundation

@MainActor
protocol SelectionEventMonitoring: AnyObject {
    func events() -> AsyncStream<SelectionMonitorEvent>
    func stop()
}
