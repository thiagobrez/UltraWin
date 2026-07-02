import AppKit

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private unowned let app: AppController

    init(app: AppController) {
        self.app = app
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        statusItem.button?.image = NSImage(
            systemSymbolName: "rectangle.dashed.badge.record",
            accessibilityDescription: "UltraWin"
        )
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if let session = app.session {
            let status = NSMenuItem(
                title: "Sharing \(Int(session.region.width)) × \(Int(session.region.height))",
                action: nil,
                keyEquivalent: ""
            )
            status.isEnabled = false
            menu.addItem(status)
            menu.addItem(makeItem(title: "Re-select Region…", action: #selector(selectRegion)))
            menu.addItem(makeItem(title: "Stop Sharing", action: #selector(stopSharing)))
        } else {
            menu.addItem(makeItem(title: "Select Region to Share…", action: #selector(selectRegion)))
        }

        menu.addItem(.separator())

        let aspectItem = makeItem(title: "Snap to 16:9 (1080p output)", action: #selector(toggleAspectLock))
        aspectItem.state = app.aspectLocked ? .on : .off
        menu.addItem(aspectItem)

        let dimMenu = NSMenu()
        for level in AppController.DimLevel.allCases {
            let item = NSMenuItem(title: level.title, action: #selector(setDimLevel(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = level.rawValue
            item.state = app.dimLevel == level ? .on : .off
            dimMenu.addItem(item)
        }
        let dimItem = NSMenuItem(title: "Dim Outside Region", action: nil, keyEquivalent: "")
        dimItem.submenu = dimMenu
        menu.addItem(dimItem)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit UltraWin", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
    }

    private func makeItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func selectRegion() {
        app.selectRegion()
    }

    @objc private func stopSharing() {
        app.stopSharing()
    }

    @objc private func toggleAspectLock() {
        app.aspectLocked.toggle()
    }

    @objc private func setDimLevel(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let level = AppController.DimLevel(rawValue: raw) else { return }
        app.dimLevel = level
    }
}
