import AppKit
import SwiftUI

@main
struct MyInvestApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = PortfolioStore()
    @StateObject private var softwareUpdates = SoftwareUpdateController()

    var body: some Scene {
        WindowGroup("Vestor") {
            ContentView()
                .environmentObject(store)
                .environmentObject(softwareUpdates)
                .frame(minWidth: 1080, minHeight: 760)
                .task {
                    await store.refreshAll()
                }
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Проверить обновления...") {
                    softwareUpdates.checkForUpdates()
                }
                .disabled(!softwareUpdates.canCheckForUpdates)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(store)
                .environmentObject(softwareUpdates)
                .frame(width: 520)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
