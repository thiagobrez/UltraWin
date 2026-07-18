import AppKit
import SwiftUI

/// Owns the one-time first-launch onboarding window. UltraWin is an
/// `.accessory` app with no normal windows, so this creates and activates an
/// AppKit window directly rather than relying on a SwiftUI scene.
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    static let hasSeenOnboardingKey = "hasSeenOnboarding"
    /// Page to reopen onboarding on after the Screen Recording relaunch.
    static let resumePageKey = "onboardingResumePage"

    private unowned let app: AppController
    private var window: NSWindow?
    /// Run once when onboarding is finished or dismissed.
    private var onComplete: (() -> Void)?

    init(app: AppController) {
        self.app = app
        super.init()
    }

    /// Builds (if needed), centers, and brings the onboarding window to the
    /// front. Because the app is `.accessory`, we activate it explicitly so the
    /// window takes focus above other apps. `onComplete` fires once the window
    /// is finished/closed.
    func present(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
        let window = window ?? makeWindow()
        self.window = window

        // Onboarding is a real window, so show a Dock icon while it's open (the
        // app is otherwise a menu-bar `.accessory`). Reverted in `finish()`.
        NSApp.setActivationPolicy(.regular)
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        // Onboarding is only ever over once the user says so, so an unfinished
        // run resumes where it left off — after our own relaunch, after macOS's
        // "Quit & Reopen", or after the user quits the app outright.
        let startPage = UserDefaults.standard.integer(forKey: Self.resumePageKey)

        // Pin the SwiftUI content to a fixed size: with an unbounded
        // (maxHeight: .infinity) root view, NSHostingView would otherwise
        // resize the window to the screen height.
        window.contentView = NSHostingView(rootView: OnboardingView(
            app: app,
            startPage: startPage,
            onFinish: { [weak self] in
                self?.finish()
            },
            onRelaunch: { [weak self] in
                self?.relaunch()
            },
            onPageChange: { page in
                UserDefaults.standard.set(page, forKey: Self.resumePageKey)
            }
        ).frame(width: 560, height: 520))
        return window
    }

    /// Restarts the app into a fresh process, reopening onboarding where it
    /// stands. Screen Recording is resolved once per process, so a permission
    /// granted during onboarding doesn't apply to the instance that asked.
    private func relaunch() {
        // Terminating closes the window, and the delegate would tear onboarding
        // down as if it were over — it isn't, we're coming right back.
        window?.delegate = nil

        // Wait for this instance to exit before reopening: `open` on a bundle
        // that's still running would just reactivate the process on its way
        // out instead of starting the fresh one we need.
        let relauncher = Process()
        relauncher.executableURL = URL(fileURLWithPath: "/bin/sh")
        relauncher.arguments = [
            "-c",
            "while /bin/kill -0 $1 2>/dev/null; do /bin/sleep 0.1; done; /usr/bin/open \"$2\"",
            "sh",
            String(ProcessInfo.processInfo.processIdentifier),
            Bundle.main.bundlePath,
        ]

        do {
            try relauncher.run()
        } catch {
            // Couldn't spawn the relauncher, so stay running rather than
            // quitting into nothing — the page keeps offering the restart.
            window?.delegate = self
            return
        }

        NSApp.terminate(nil)
    }

    /// The user is done with onboarding: don't show it again.
    private func finish() {
        markSeen()
        dismiss()
    }

    private func markSeen() {
        UserDefaults.standard.set(true, forKey: Self.hasSeenOnboardingKey)
        UserDefaults.standard.removeObject(forKey: Self.resumePageKey)
        Analytics.onboardingCompleted()
    }

    /// Tears the window down *without* recording onboarding as seen — the
    /// window also goes away when the app restarts mid-onboarding, and that
    /// has to bring it back.
    private func dismiss() {
        // Back to a menu-bar-only agent: drop the Dock icon.
        NSApp.setActivationPolicy(.accessory)

        if let window {
            self.window = nil
            window.delegate = nil
            window.close()
        }

        // Fire (and clear) the completion exactly once, whether the user
        // finished, skipped, or closed the window.
        let completion = onComplete
        onComplete = nil
        completion?()
    }

    // MARK: - NSWindowDelegate

    /// Only reached when the user closes the window themselves (the red X):
    /// windows closed programmatically or by the app terminating never ask.
    /// That's the distinction onboarding needs — a restart isn't a dismissal.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        markSeen()
        return true
    }

    func windowWillClose(_ notification: Notification) {
        dismiss()
    }
}
