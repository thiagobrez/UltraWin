import AppKit

@MainActor
final class PreferencesWindowController: NSWindowController {
    private unowned let app: AppController

    init(app: AppController) {
        self.app = app
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 190),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "UltraWin Preferences"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentView = makeContentView()
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func makeContentView() -> NSView {
        let container = NSView()

        let heading = NSTextField(labelWithString: "Region selection shortcut")
        heading.font = .boldSystemFont(ofSize: 13)

        let recorder = ShortcutRecorderButton(combo: app.hotKeyCombo)
        recorder.onChange = { [weak self] combo in
            self?.app.hotKeyCombo = combo
        }
        recorder.onRecordingChange = { [weak self] recording in
            self?.app.setHotKeySuspended(recording)
        }

        let help = NSTextField(wrappingLabelWithString:
            "Press this shortcut from any app to start selecting a region to share. "
            + "While recording, press ⌫ to clear the shortcut or ⎋ to cancel.")
        help.font = .systemFont(ofSize: 11)
        help.textColor = .secondaryLabelColor

        for view in [heading, recorder, help] {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
        }

        NSLayoutConstraint.activate([
            heading.topAnchor.constraint(equalTo: container.topAnchor, constant: 24),
            heading.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),

            recorder.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 12),
            recorder.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),

            help.topAnchor.constraint(equalTo: recorder.bottomAnchor, constant: 18),
            help.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            help.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
        ])
        return container
    }
}
