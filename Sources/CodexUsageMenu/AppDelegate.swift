import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: FloatingWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = FloatingWindowController()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.shutdown()
    }
}
