import SwiftUI

@main
struct ExileRouteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(appDelegate.model)
                .frame(width: 560, height: 620)
        }
    }
}
