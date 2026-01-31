import SwiftUI

@main
struct TestMenuBarApp: App {
    var body: some Scene {
        MenuBarExtra("Test", systemImage: "star.fill") {
            Text("Hello World")
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
