import SwiftUI

@main
struct OtterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // A menu-bar agent opens no windows at launch. Settings (T10) lives here.
        Settings {
            EmptyView()
        }
    }
}
