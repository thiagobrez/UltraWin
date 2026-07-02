import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: AppController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        controller = AppController()

        if CommandLine.arguments.contains("--test-region") {
            controller.startTestSession()
        }
    }
}
