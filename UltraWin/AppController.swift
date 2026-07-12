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
    private(set) var session: SharingSession?
    private var preferencesWindowController: PreferencesWindowController?
    private let hotKeyID: UInt32 = 1

    var aspectLocked: Bool {
        get { UserDefaults.standard.bool(forKey: "aspectLocked") }
        set { UserDefaults.standard.set(newValue, forKey: "aspectLocked") }
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
    }

    // MARK: - Actions

    func selectRegion() {
        guard !selection.isActive else { return }
        guard ensureScreenRecordingAccess() else { return }
        // Never offer the (invisible) virtual display as a selection target.
        var excluded: Set<CGDirectDisplayID> = []
        if let session {
            excluded.insert(session.virtualDisplayID)
        }
        selection.begin(aspectRatio: aspectLocked ? 16.0 / 9.0 : nil, excludingDisplayIDs: excluded) { [weak self] result in
            guard let self, let result else { return }
            Task { @MainActor in
                await self.startOrUpdateSession(rect: result.rect, screen: result.screen)
            }
        }
    }

    func stopSharing() {
        guard let session else { return }
        self.session = nil
        Task { @MainActor in
            await session.stop()
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
            self?.selectRegion()
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

    private func startOrUpdateSession(rect: CGRect, screen: NSScreen) async {
        do {
            if let session, session.aspectLocked == aspectLocked {
                try await session.updateRegion(rect, on: screen)
            } else {
                if let session {
                    self.session = nil
                    await session.stop()
                }
                let session = try await SharingSession(
                    region: rect,
                    screen: screen,
                    aspectLocked: aspectLocked,
                    dimAlpha: dimLevel.alpha
                )
                session.onStopped = { [weak self] error in
                    self?.session = nil
                    if let error {
                        self?.showAlert(
                            title: "Sharing stopped",
                            message: "The screen capture stopped unexpectedly: \(error.localizedDescription)"
                        )
                    }
                }
                self.session = session
            }
        } catch {
            session = nil
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
