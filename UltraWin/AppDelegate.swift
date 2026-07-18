import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: AppController!
    private var onboarding: OnboardingWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Analytics.start()
        // Read Screen Recording before anything can grant it, so onboarding
        // can tell "this process can capture" from "the permission is on now,
        // but only a fresh process can use it".
        _ = ScreenRecordingAccess.atLaunch
        controller = AppController()

        if !UserDefaults.standard.bool(forKey: OnboardingWindowController.hasSeenOnboardingKey) {
            let onboarding = OnboardingWindowController(app: controller)
            self.onboarding = onboarding
            onboarding.present { [weak self] in
                self?.onboarding = nil
            }
        }

        if CommandLine.arguments.contains("--test-region") {
            controller.startTestSession()
        }
        if CommandLine.arguments.contains("--open-preferences") {
            controller.showPreferences()
        }
    }
}
