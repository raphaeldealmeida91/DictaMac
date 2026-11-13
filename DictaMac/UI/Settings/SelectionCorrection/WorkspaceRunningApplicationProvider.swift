import AppKit

@MainActor
struct WorkspaceRunningApplicationProvider: RunningApplicationProviding {
    func applications() -> [RunningApplicationInfo] {
        NSWorkspace.shared.runningApplications.compactMap { application in
            guard let bundleID = application.bundleIdentifier,
                  let name = application.localizedName,
                  application.activationPolicy == .regular else { return nil }
            return RunningApplicationInfo(name: name, bundleID: bundleID)
        }
    }
}
