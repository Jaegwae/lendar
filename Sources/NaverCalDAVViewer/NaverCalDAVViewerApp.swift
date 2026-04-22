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
                .background(WindowSizeConfigurator())
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

private struct WindowSizeConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configure(view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(nsView.window)
        }
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.minSize = NSSize(width: 760, height: 900)
    }
}
