import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private let hasLaunchedKey = "hasLaunchedBefore"

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !AudioMatorTestHost.isEnabled else { return }
        let launchedBefore = UserDefaults.standard.bool(forKey: hasLaunchedKey)

        if !launchedBefore {
            if let window = NSApplication.shared.windows.first {
                window.setContentSize(NSSize(width: 900, height: 600))
                window.center()
            }
            UserDefaults.standard.set(true, forKey: hasLaunchedKey)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
