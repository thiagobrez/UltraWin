import AppKit
import SwiftUI

/// The Preferences window: an NSTabViewController with a toolbar-style tab bar
/// hosting the AppKit General tab and the SwiftUI About tab.
@MainActor
final class PreferencesWindowController: NSWindowController {
    init(app: AppController) {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        // Keep the fixed window title instead of adopting the (empty) title
        // of whichever child view controller is selected.
        tabs.canPropagateSelectedChildViewControllerTitle = false

        let general = NSTabViewItem(viewController: GeneralPreferencesViewController(app: app))
        general.label = "General"
        general.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "General")
        tabs.addTabViewItem(general)

        let about = NSTabViewItem(viewController: NSHostingController(rootView: AboutView()))
        about.label = "About"
        about.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: "About")
        tabs.addTabViewItem(about)

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.title = "UltraWin Preferences"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}
