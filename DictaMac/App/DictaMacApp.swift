import SwiftUI

@main
struct DictaMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(environment: appDelegate.environment)
        } label: {
            MenuBarIcon(activity: appDelegate.environment.activity)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(environment: appDelegate.environment)
        }
    }
}
