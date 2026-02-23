import SwiftUI

@main
struct NotesToMarkdownBackupApp: App {
    @StateObject private var appModel = AppViewModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appModel)
        }
        .commands {
            CommandGroup(after: .help) {
                Button("Permissions…") {
                    appModel.presentPermissionsSheet()
                }
            }
        }
        Settings {
            SettingsView()
                .environmentObject(appModel)
        }
    }
}

