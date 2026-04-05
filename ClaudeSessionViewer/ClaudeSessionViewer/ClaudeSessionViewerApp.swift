import SwiftUI
import AppKit

@main
struct ClaudeSessionViewerApp: App {
    @StateObject private var viewModel = SessionViewModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .frame(minWidth: 800, minHeight: 500)
        }
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(after: .sidebar) {
                Button("Refresh Sessions") {
                    viewModel.refresh()
                }
                .keyboardShortcut("r", modifiers: .command)
            }
            CommandGroup(after: .textEditing) {
                Button("Find in Session") {
                    NotificationCenter.default.post(name: .focusSessionSearch, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)
            }
        }
    }
}

extension Notification.Name {
    static let focusSessionSearch = Notification.Name("focusSessionSearch")
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
