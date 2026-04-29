import SwiftUI
import AppKit

@main
struct LumenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store = LumenStore()
    @StateObject private var auth = AuthManager()

    var body: some Scene {
        WindowGroup {
            Group {
                if auth.isAuthenticated {
                    MainView()
                        .environmentObject(store)
                        .environmentObject(auth)
                } else {
                    AuthGate()
                        .environmentObject(auth)
                }
            }
            .frame(minWidth: 1200, minHeight: 800)
            .task { await store.startup() }
            .onChange(of: auth.isAuthenticated) { _, authenticated in
                if authenticated {
                    Task { await store.fetchDashboard() }
                }
            }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if let window = NSApp.windows.first {
                window.toggleFullScreen(nil)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
