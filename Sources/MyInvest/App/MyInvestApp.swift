import AppKit
import SwiftUI

@main
struct MyInvestApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = PortfolioStore()

    var body: some Scene {
        WindowGroup("Vestor") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 1080, minHeight: 760)
                .task {
                    await store.refreshAll()
                }
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1280, height: 820)

        Settings {
            SettingsView()
                .environmentObject(store)
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
