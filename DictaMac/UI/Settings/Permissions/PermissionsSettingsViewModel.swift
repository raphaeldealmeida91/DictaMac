import Combine
import Foundation

@MainActor
final class PermissionsSettingsViewModel: ObservableObject {
    @Published private(set) var statuses: [AppPermission: PermissionStatus] = [:]
    let permissions = AppPermission.allCases
    private let manager: any PermissionManaging
    private var cancellable: AnyCancellable?

    init<Manager: PermissionManaging>(manager: Manager) {
        self.manager = manager
        cancellable = manager.objectWillChange.sink { [weak self] in
            Task { @MainActor in
                await Task.yield()
                self?.refreshStatuses()
            }
        }
        refreshStatuses()
    }

    func appear() {
        manager.startPeriodicRefresh()
        refreshStatuses()
    }

    func disappear() {
        manager.stopPeriodicRefresh()
    }

    func status(for permission: AppPermission) -> PermissionStatus {
        statuses[permission] ?? .notDetermined
    }

    func request(_ permission: AppPermission) {
        Task {
            statuses[permission] = await manager.request(permission)
        }
    }

    func openSystemSettings(for permission: AppPermission) {
        manager.openSystemSettings(for: permission)
    }

    private func refreshStatuses() {
        statuses = Dictionary(uniqueKeysWithValues: permissions.map { ($0, manager.status(for: $0)) })
    }
}
