import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = StatusBarController()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.shutdown()
    }
}
