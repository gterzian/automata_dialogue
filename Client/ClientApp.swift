import AppKit
import Core
import SwiftUI

@main
struct RaterApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 760)
        .commands {
            // Single window: the panel is the whole app.
            CommandGroup(replacing: .newItem) {}
        }
    }
}
