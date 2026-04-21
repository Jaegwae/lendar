import SwiftUI
import AppKit
import Foundation

@main
struct NaverCalDAVViewerApp: App {
    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        DispatchQueue.main.async {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 1512, height: 920)
        .windowResizability(.automatic)
        .commands {
            CommandMenu("Setting") {
                Button("Sync Settings") {
                    NotificationCenter.default.post(name: .openSyncSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: [.command, .option])
            }
        }
    }
}
