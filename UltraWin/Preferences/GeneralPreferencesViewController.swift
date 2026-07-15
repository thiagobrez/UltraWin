import AppKit
import ServiceManagement

/// The "General" tab in Preferences: the region-selection shortcut plus the
/// sharing options that also live in the menu bar menu (both read the same
/// UserDefaults-backed AppController properties, so they can't drift — this
/// view re-reads state in viewWillAppear to cover changes made in the menu).
@MainActor
final class GeneralPreferencesViewController: NSViewController {
    private unowned let app: AppController

    private var launchAtLoginCheckbox: NSButton!
    private var aspectLockCheckbox: NSButton!
    private var dimLevelPopup: NSPopUpButton!

    init(app: AppController) {
        self.app = app
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let container = NSView()

        // MARK: Shortcut

        let shortcutHeading = NSTextField(labelWithString: "Region selection shortcut")
        shortcutHeading.font = .boldSystemFont(ofSize: 13)

        let recorder = ShortcutRecorderButton(combo: app.hotKeyCombo)
        recorder.onChange = { [weak self] combo in
            self?.app.hotKeyCombo = combo
        }
        recorder.onRecordingChange = { [weak self] recording in
            self?.app.setHotKeySuspended(recording)
        }

        let shortcutHelp = NSTextField(wrappingLabelWithString:
            "Press this shortcut from any app to start selecting a region to share. "
            + "While recording, press ⌫ to clear the shortcut or ⎋ to cancel.")
        shortcutHelp.font = .systemFont(ofSize: 11)
        shortcutHelp.textColor = .secondaryLabelColor

        // MARK: Sharing options

        let sharingHeading = NSTextField(labelWithString: "Sharing")
        sharingHeading.font = .boldSystemFont(ofSize: 13)

        aspectLockCheckbox = NSButton(
            checkboxWithTitle: "Snap to 16:9 (1080p output)",
            target: self,
            action: #selector(toggleAspectLock)
        )

        let dimLabel = NSTextField(labelWithString: "Dim outside region:")
        dimLevelPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        for level in AppController.DimLevel.allCases {
            dimLevelPopup.addItem(withTitle: level.title)
            dimLevelPopup.lastItem?.representedObject = level.rawValue
        }
        dimLevelPopup.target = self
        dimLevelPopup.action = #selector(dimLevelChanged)
        let dimRow = NSStackView(views: [dimLabel, dimLevelPopup])
        dimRow.orientation = .horizontal
        dimRow.spacing = 8

        // MARK: General

        let generalHeading = NSTextField(labelWithString: "General")
        generalHeading.font = .boldSystemFont(ofSize: 13)

        launchAtLoginCheckbox = NSButton(
            checkboxWithTitle: "Launch UltraWin at login",
            target: self,
            action: #selector(toggleLaunchAtLogin)
        )

        let stack = NSStackView(views: [
            shortcutHeading, recorder, shortcutHelp,
            sharingHeading, aspectLockCheckbox, dimRow,
            generalHeading, launchAtLoginCheckbox,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.setCustomSpacing(16, after: shortcutHelp)
        stack.setCustomSpacing(16, after: dimRow)
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -24),
            container.widthAnchor.constraint(equalToConstant: 460),
        ])

        view = container
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        refreshState()
    }

    /// The same settings are reachable from the menu bar menu, so re-read
    /// everything whenever the tab comes on screen.
    private func refreshState() {
        aspectLockCheckbox.state = app.aspectLocked ? .on : .off
        let dimIndex = AppController.DimLevel.allCases.firstIndex(of: app.dimLevel) ?? 0
        dimLevelPopup.selectItem(at: dimIndex)
        launchAtLoginCheckbox.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    // MARK: - Actions

    @objc private func toggleAspectLock() {
        app.aspectLocked = aspectLockCheckbox.state == .on
    }

    @objc private func dimLevelChanged() {
        guard let raw = dimLevelPopup.selectedItem?.representedObject as? String,
              let level = AppController.DimLevel(rawValue: raw) else { return }
        app.dimLevel = level
    }

    @objc private func toggleLaunchAtLogin() {
        let enable = launchAtLoginCheckbox.state == .on
        do {
            if enable {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("UltraWin: failed to \(enable ? "register" : "unregister") login item: \(error)")
            // Revert the checkbox so it reflects reality.
            launchAtLoginCheckbox.state = SMAppService.mainApp.status == .enabled ? .on : .off
        }
    }
}
