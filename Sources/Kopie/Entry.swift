import AppKit

@main
enum Main {
    static func main() {
        if SelfTest.run(Array(CommandLine.arguments.dropFirst())) { return }
        // Plain AppKit lifecycle: the app is menu-bar-only (accessory) and all
        // windows are built by AppDelegate. A SwiftUI App scene is deliberately
        // avoided — an App with a Settings scene presented that scene's window
        // at every launch (blank "Kopie Settings" window).
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
