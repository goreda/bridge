import AppKit

// Minimal test host lifecycle only. Xcode owns loading/running hosted tests.
final class SupportedAcceptanceApplication: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
    }
}
let app = NSApplication.shared
let delegate = SupportedAcceptanceApplication()
app.delegate = delegate
_ = app.setActivationPolicy(.regular)
app.run()
