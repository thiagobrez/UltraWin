import AppKit

@MainActor
final class AppController: NSObject {
    enum DimLevel: String, CaseIterable {
        case off, light, strong

        var alpha: CGFloat {
            switch self {
            case .off: return 0
            case .light: return 0.25
            case .strong: return 0.5
            }
        }

        var title: String {
            switch self {
            case .off: return "Off"
            case .light: return "Light"
            case .strong: return "Strong"
            }
        }
    }

    private var statusItem: StatusItemController!
    private let selection = RegionSelectionController()
    /// One persistent virtual display, attached at launch and reused by every
    /// session: plugging/unplugging a display makes macOS reconfigure all
    /// screens (a visible flicker), so pay that cost once instead of per share.
    private let virtualDisplay = VirtualDisplayController()
    private(set) var session: SharingSession?
    private var preferencesWindowController: PreferencesWindowController?
    private let hotKeyID: UInt32 = 1

    var aspectLocked: Bool {
        get { UserDefaults.standard.bool(forKey: "aspectLocked") }
        set {
            UserDefaults.standard.set(newValue, forKey: "aspectLocked")
            if let session {
                Task { @MainActor in await session.setAspectLocked(newValue) }
            }
        }
    }

    var dimLevel: DimLevel {
        get { DimLevel(rawValue: UserDefaults.standard.string(forKey: "dimLevel") ?? "") ?? .light }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "dimLevel")
            session?.setDimAlpha(newValue.alpha)
        }
    }

    /// The global hotkey that triggers region selection. `nil` means the user
    /// cleared it (no hotkey). Defaults to ⌘⇧U on first run.
    var hotKeyCombo: KeyCombo? {
        get {
            let defaults = UserDefaults.standard
            guard defaults.bool(forKey: "hotKeyConfigured") else { return .default }
            guard let dictionary = defaults.dictionary(forKey: "hotKeyCombo") as? [String: Int] else { return nil }
            return KeyCombo(dictionary: dictionary)
        }
        set {
            let defaults = UserDefaults.standard
            defaults.set(true, forKey: "hotKeyConfigured")
            if let newValue {
                defaults.set(newValue.persistentDictionary, forKey: "hotKeyCombo")
            } else {
                defaults.removeObject(forKey: "hotKeyCombo")
            }
            registerHotKey()
        }
    }

    override init() {
        super.init()
        statusItem = StatusItemController(app: self)
        registerHotKey()
        // Kick off Sparkle so scheduled update checks start with the app.
        _ = UpdaterManager.shared
        Task { @MainActor [virtualDisplay] in
            await VirtualDisplayController.suppressingReconfigurationFade {
                _ = virtualDisplay.ensureReady(
                    pointSize: CGSize(width: 1920, height: 1080),
                    hiDPI: (NSScreen.main?.backingScaleFactor ?? 2) > 1.5
                )
                // Idle displays stay mirrored so the cursor can't reach them.
                virtualDisplay.setMirroring(true)
            }
        }
    }

    // MARK: - Actions

    /// Hotkey behavior: when a region is being shared, pressing the hotkey stops
    /// it; otherwise it starts region selection. Effectively a toggle.
    func toggleRegion() {
        if session != nil {
            stopSharing()
        } else {
            selectRegion(source: .hotkey)
        }
    }

    func selectRegion(source: Analytics.ShareSource = .menu) {
        guard !selection.isActive else { return }
        guard ensureScreenRecordingAccess() else { return }
        // Never offer the (invisible) virtual display as a selection target.
        var excluded: Set<CGDirectDisplayID> = []
        if virtualDisplay.isCreated {
            excluded.insert(virtualDisplay.displayID)
        }
        selection.begin(aspectRatio: aspectLocked ? 16.0 / 9.0 : nil, excludingDisplayIDs: excluded) { [weak self] result in
            guard let self, let result else { return }
            Task { @MainActor in
                await self.startOrUpdateSession(rect: result.rect, screen: result.screen, source: source)
            }
        }
    }

    func stopSharing() {
        guard let session else { return }
        self.session = nil
        Analytics.sharingStopped()
        Task { @MainActor in
            await session.stop()
            await parkVirtualDisplayMirrored()
        }
    }

    /// Puts the idle virtual display back into mirror mode so the cursor can't
    /// wander onto it between sessions.
    private func parkVirtualDisplayMirrored() async {
        await VirtualDisplayController.suppressingReconfigurationFade {
            virtualDisplay.setMirroring(true)
        }
    }

    func showPreferences() {
        if preferencesWindowController == nil {
            preferencesWindowController = PreferencesWindowController(app: self)
        }
        NSApp.activate(ignoringOtherApps: true)
        preferencesWindowController?.showWindow(nil)
        preferencesWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Global hotkey

    private func registerHotKey() {
        HotKeyCenter.shared.unregister(id: hotKeyID)
        guard let combo = hotKeyCombo else { return }
        let registered = HotKeyCenter.shared.register(id: hotKeyID, combo: combo) { [weak self] in
            self?.toggleRegion()
        }
        if !registered {
            NSLog("UltraWin: failed to register hotkey \(combo.displayString)")
        }
    }

    /// Temporarily drops the live hotkey while a new one is being recorded, so
    /// pressing the old combination doesn't fire mid-recording.
    func setHotKeySuspended(_ suspended: Bool) {
        if suspended {
            HotKeyCenter.shared.unregister(id: hotKeyID)
        } else {
            registerHotKey()
        }
    }

    func startTestSession() {
        guard let screen = NSScreen.main else { return }
        let size = CGSize(width: 1280, height: 720)
        let rect = CGRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        Task { @MainActor in
            await startOrUpdateSession(rect: rect, screen: screen)
        }
    }

    // MARK: - Session lifecycle

    private func startOrUpdateSession(
        rect: CGRect,
        screen: NSScreen,
        source: Analytics.ShareSource = .menu
    ) async {
        // The (frozen) selection overlay keeps dimming the screen through the
        // whole session startup — display mode changes, capture spin-up — and
        // only fades out once the share is live, so nothing underneath is ever
        // exposed mid-setup. On failure it's dropped immediately instead.
        do {
            if let session, session.aspectLocked == aspectLocked {
                try await session.updateRegion(rect, on: screen)
            } else {
                if let session {
                    self.session = nil
                    await session.stop()
                }
                let ratio: CGFloat? = aspectLocked ? 16.0 / 9.0 : nil
                let overlay = HighlightOverlayController(
                    region: HighlightOverlayController.clampRegion(rect, to: screen, aspectRatio: ratio),
                    screen: screen,
                    dimAlpha: dimLevel.alpha,
                    aspectRatio: ratio,
                    stopHint: hotKeyCombo?.spacedDisplayString
                )
                let session = try await SharingSession(
                    screen: screen,
                    aspectLocked: aspectLocked,
                    overlay: overlay,
                    virtualDisplay: virtualDisplay
                )
                session.onStopped = { [weak self] error in
                    guard let self else { return }
                    self.session = nil
                    Task { @MainActor in
                        await self.parkVirtualDisplayMirrored()
                    }
                    if let error {
                        self.showAlert(
                            title: "Sharing stopped",
                            message: "The screen capture stopped unexpectedly: \(error.localizedDescription)"
                        )
                    }
                }
                self.session = session
                Analytics.sharingStarted(source: source, aspectLocked: aspectLocked)
            }
            selection.dismiss(fadeDuration: 0.25)
        } catch {
            session = nil
            selection.dismiss()
            await parkVirtualDisplayMirrored()
            showAlert(title: "Could not start sharing", message: error.localizedDescription)
        }
    }

    // MARK: - Permissions

    private func ensureScreenRecordingAccess() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        if CGRequestScreenCaptureAccess() { return true }
        showAlert(
            title: "Screen Recording permission needed",
            message: "UltraWin captures the selected part of your screen, which requires Screen Recording permission. Enable UltraWin in System Settings → Privacy & Security → Screen Recording, then relaunch the app."
        )
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
        return false
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
