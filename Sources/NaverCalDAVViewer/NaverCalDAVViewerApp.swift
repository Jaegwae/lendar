import AppKit
import Foundation
import SwiftUI

/// App entry point. Configures the SwiftUI scene and the underlying NSWindow minimum
/// size so the calendar cannot be resized into an unusable layout.
@main
struct NaverCalDAVViewerApp: App {
    private static let minimumWindowSize = NSSize(width: 570, height: 710)

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        DispatchQueue.main.async {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(
                    minWidth: Self.minimumWindowSize.width,
                    minHeight: Self.minimumWindowSize.height
                )
                .background(WindowSizeConfigurator(minimumSize: Self.minimumWindowSize))
        }
        .defaultSize(width: 1512, height: 920)
        .windowResizability(.contentMinSize)
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
    let minimumSize: NSSize

    func makeNSView(context _: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configure(view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context _: Context) {
        DispatchQueue.main.async {
            configure(nsView.window)
        }
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.minSize = minimumSize
        window.contentMinSize = minimumSize
    }
}
