// PLACEHOLDER(F3) — contract: ARCHITECTURE.md §7.1
// Minimal bootstrap so the AA executable target compiles and launches an empty window. F3 replaces this file
// (same path) with the real `@main` App, AppDelegate, launch phases and scenes.
import SwiftUI
import AACore

@main
struct AAMain: App {
    var body: some Scene {
        WindowGroup("AA") {
            // PLACEHOLDER(F3)
            Color.clear
                .frame(minWidth: 480, minHeight: 320)
        }
    }
}
