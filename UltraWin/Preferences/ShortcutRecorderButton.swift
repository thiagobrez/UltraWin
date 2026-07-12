import AppKit

/// A button that records a keyboard shortcut. Click to start recording, then
/// press the desired combination. ⎋ cancels, ⌫ clears. While recording it
/// swallows key events (via a local monitor) so they don't leak to the app.
final class ShortcutRecorderButton: NSButton {
    /// Fired when the shortcut changes (nil = cleared).
    var onChange: ((KeyCombo?) -> Void)?
    /// Fired when recording starts (true) and ends (false), so the owner can
    /// suspend the live global hotkey while a new one is being captured.
    var onRecordingChange: ((Bool) -> Void)?

    private(set) var combo: KeyCombo?
    private var isRecording = false
    private var liveModifiers: NSEvent.ModifierFlags = []
    private var monitor: Any?
    private var resignObserver: Any?

    init(combo: KeyCombo?) {
        self.combo = combo
        super.init(frame: .zero)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(didClick)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
        updateTitle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    @objc private func didClick() {
        if isRecording {
            endRecording()
        } else {
            beginRecording()
        }
    }

    private func beginRecording() {
        isRecording = true
        liveModifiers = []
        onRecordingChange?(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            return self.process(event)
        }
        if let window {
            resignObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.endRecording()
            }
        }
        updateTitle()
    }

    private func process(_ event: NSEvent) -> NSEvent? {
        guard isRecording else { return event }

        if event.type == .flagsChanged {
            liveModifiers = event.modifierFlags.intersection(KeyCombo.relevantModifiers)
            updateTitle()
            return nil
        }

        let modifiers = event.modifierFlags.intersection(KeyCombo.relevantModifiers)
        if modifiers.isEmpty {
            switch event.keyCode {
            case 0x35: // Escape cancels
                endRecording()
                return nil
            case 0x33, 0x75: // Delete / Forward Delete clears
                commit(nil)
                return nil
            default:
                break
            }
        }

        let candidate = KeyCombo(keyCode: event.keyCode, modifiers: modifiers)
        guard candidate.hasRequiredModifier else {
            NSSound.beep()
            return nil
        }
        commit(candidate)
        return nil
    }

    private func commit(_ newCombo: KeyCombo?) {
        combo = newCombo
        onChange?(newCombo)
        endRecording()
    }

    private func endRecording() {
        guard isRecording else { return }
        isRecording = false
        liveModifiers = []
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
            self.resignObserver = nil
        }
        onRecordingChange?(false)
        updateTitle()
    }

    private func updateTitle() {
        if isRecording {
            let symbols = KeyCombo.symbols(for: liveModifiers)
            title = symbols.isEmpty ? "Type shortcut…" : symbols + "…"
        } else if let combo {
            title = combo.displayString
        } else {
            title = "Click to Record Shortcut"
        }
    }
}
