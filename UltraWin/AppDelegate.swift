import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: AppController!
    private var onboarding: OnboardingWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Analytics.start()
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
