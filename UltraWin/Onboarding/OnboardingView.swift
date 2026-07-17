import SwiftUI
import AppKit

/// First-launch onboarding: a small paged tour that welcomes the user and
/// explains the ideas behind UltraWin — the invisible virtual display, picking
/// "UltraWin Display" in the meeting app, and the controls. Hosted in a plain
/// `NSWindow` by `OnboardingWindowController`; `onFinish` is called when the
/// user reaches the end (or taps Skip).
struct OnboardingView: View {
    /// Drives the interactive hotkey recorder on the controls page.
    let app: AppController
    /// Called when onboarding is completed or skipped. The window controller
    /// uses this to persist the "seen" flag and close the window.
    let onFinish: () -> Void

    @State private var page = 0
    /// Drives the direction of the slide transition between pages.
    @State private var forward = true

    private let pageCount = 6
    private var isLastPage: Bool { page == pageCount - 1 }

    var body: some View {
        VStack(spacing: 0) {
            topBar

            ZStack {
                pageContent
                    .id(page)
                    .transition(pageTransition)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 40)

            bottomBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(.blue)
    }

    // MARK: - Pages

    @ViewBuilder
    private var pageContent: some View {
        switch page {
        case 0: WelcomePage()
        case 1: HowItWorksPage()
        case 2: GetStartedPage()
        case 3: ControlsPage(app: app)
        case 4: MeetingPage()
        default: PermissionPage()
        }
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack {
            Spacer()
            Button("Skip") { onFinish() }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .opacity(isLastPage ? 0 : 1)
                .disabled(isLastPage)
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .frame(height: 40)
    }

    private var bottomBar: some View {
        ZStack {
            // Page dots: centered in the window, independent of the button
            // widths — so "Next" growing to "Get Started" doesn't shift them.
            HStack(spacing: 7) {
                ForEach(0..<pageCount, id: \.self) { index in
                    Circle()
                        .fill(index == page ? Color.blue : Color.secondary.opacity(0.3))
                        .frame(width: 7, height: 7)
                }
            }
            .animation(.snappy(duration: 0.3), value: page)

            HStack {
                Button("Back") { go(to: page - 1) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .opacity(page > 0 ? 1 : 0)
                    .disabled(page == 0)

                Spacer()

                Button(isLastPage ? "Get Started" : "Next") {
                    if isLastPage { onFinish() } else { go(to: page + 1) }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    // MARK: - Navigation

    private func go(to target: Int) {
        guard target >= 0, target < pageCount else { return }
        forward = target > page
        withAnimation(.snappy(duration: 0.3)) {
            page = target
        }
    }

    private var pageTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)
        )
    }
}

// MARK: - Shared page scaffold

/// Common vertical layout for a page: a hero area (icon/illustration) that
/// springs in on appear, a title, and free-form content below.
private struct PageScaffold<Hero: View, Content: View>: View {
    let title: String
    @ViewBuilder var hero: Hero
    @ViewBuilder var content: Content

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)

            hero
                .frame(minHeight: 120)
                .scaleEffect(appeared ? 1 : 0.85)
                .opacity(appeared ? 1 : 0)

            Text(title)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            content
                .multilineTextAlignment(.center)
                .opacity(appeared ? 1 : 0)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            withAnimation(.snappy(duration: 0.4)) { appeared = true }
        }
    }
}

/// A body paragraph styled consistently across pages.
private struct PageText: View {
    let text: String
    var secondary = false
    init(_ text: String, secondary: Bool = false) {
        self.text = text
        self.secondary = secondary
    }
    var body: some View {
        Text(text)
            .font(.system(size: secondary ? 12 : 14))
            .foregroundStyle(secondary ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary))
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// One keycap of the hotkey hint. Flexes to fit multi-character labels
/// (e.g. "Space", "F12") rather than clipping.
private struct Keycap: View {
    let label: String
    var body: some View {
        Text(label)
            .font(.system(size: 18, weight: .semibold, design: .rounded))
            .frame(minWidth: 40, minHeight: 40)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(.separator, lineWidth: 1)
                    )
            )
    }
}

// MARK: - Pages

private struct WelcomePage: View {
    var body: some View {
        PageScaffold(title: "Welcome to UltraWin") {
            Image(nsImage: appIcon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 124, height: 124)
        } content: {
            PageText("Sharing your screen shouldn't be this hard.")
                .frame(maxWidth: 380)
        }
    }

    /// Read straight from the bundle. `NSApp.applicationIconImage` resolves the
    /// icon through the running app's Dock tile, which UltraWin doesn't have
    /// while it's still an `.accessory` when this page first renders — it then
    /// answers with a generic placeholder rather than nil, so it can't be
    /// `??`-chained past either.
    private var appIcon: NSImage {
        NSImage(named: "AppIcon")
            ?? Bundle.main.url(forResource: "AppIcon", withExtension: "icns").flatMap(NSImage.init(contentsOf:))
            ?? NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
    }
}

/// Looping demo: a dashed region draws on a wide screen, the outside dims,
/// and a small "UltraWin Display" output mirrors just the region.
private struct HowItWorksPage: View {
    @State private var showRegion = false

    var body: some View {
        PageScaffold(title: "An invisible second display") {
            demo
        } content: {
            VStack(spacing: 8) {
                PageText("Drag-select any region of your screen.")
                    .frame(maxWidth: 400)
                PageText("UltraWin creates an invisible virtual display that continuously mirrors it.")
                    .frame(maxWidth: 400)
            }
        }
        .task { await runLoop() }
    }

    private var demo: some View {
        HStack(spacing: 16) {
            // The ultrawide screen
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(.separator, lineWidth: 1)
                    )
                    .frame(width: 240, height: 90)

                // Dim outside + highlighted region
                if showRegion {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.black.opacity(0.25))
                        .frame(width: 240, height: 90)
                        .transition(.opacity)

                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.blue.opacity(0.85))
                        .frame(width: 96, height: 54)
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                                .foregroundStyle(.white)
                        )
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }

            Image(systemName: "arrow.right")
                .foregroundStyle(.tertiary)

            // The virtual display output
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(showRegion ? Color.blue.opacity(0.85) : Color.primary.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(.separator, lineWidth: 1)
                    )
                    .frame(width: 96, height: 54)
                    .animation(.snappy(duration: 0.4), value: showRegion)
                Text("UltraWin Display")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func runLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(0.8))
            withAnimation(.snappy(duration: 0.5)) { showRegion = true }
            try? await Task.sleep(for: .seconds(2.6))
            withAnimation(.easeOut(duration: 0.4)) { showRegion = false }
            try? await Task.sleep(for: .seconds(0.6))
        }
    }
}

/// Mock of a meeting app's screen picker with "UltraWin Display" selected.
private struct MeetingPage: View {
    @State private var selected = false

    var body: some View {
        PageScaffold(title: "Share it in your meeting") {
            picker
        } content: {
            VStack(spacing: 8) {
                PageText("In Zoom, Meet, or Teams, share the screen named “UltraWin Display”.")
                    .frame(maxWidth: 400)
                PageText("Everyone sees just your selected region, never the rest of your screen.")
                    .frame(maxWidth: 400)
            }
        }
        .task { await runLoop() }
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Choose what to share")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                screenTile(name: "Built-in Display", highlighted: false)
                screenTile(name: "UltraWin Display", highlighted: selected)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.separator, lineWidth: 1)
                )
        )
    }

    private func screenTile(name: String, highlighted: Bool) -> some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(highlighted ? Color.blue.opacity(0.85) : Color.primary.opacity(0.08))
                .frame(width: 110, height: 62)
                .overlay {
                    if highlighted {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.white)
                    }
                }
            Text(name)
                .font(.system(size: 10, weight: highlighted ? .semibold : .regular))
                .foregroundStyle(highlighted ? .primary : .secondary)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(highlighted ? Color.blue : Color.clear, lineWidth: 2)
        )
        .animation(.snappy(duration: 0.35), value: highlighted)
    }

    private func runLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1.2))
            selected = true
            try? await Task.sleep(for: .seconds(2.4))
            selected = false
        }
    }
}

private struct ControlsPage: View {
    let app: AppController

    /// Shared between the live keycaps and the recorder below: the recorder
    /// pushes the current shortcut and recording state here so the caps can
    /// track modifiers as they're held.
    @StateObject private var model: HotkeyModel

    init(app: AppController) {
        self.app = app
        _model = StateObject(wrappedValue: HotkeyModel(combo: app.hotKeyCombo))
    }

    var body: some View {
        PageScaffold(title: "Or just use the shortcut") {
            HotkeyKeysView(model: model)
        } content: {
            VStack(spacing: 16) {
                PageText("Press your shortcut from any app to select a region — press it again to stop sharing.")
                    .frame(maxWidth: 400)

                HotkeyRecorder(
                    combo: model.combo,
                    onChange: { combo in
                        model.combo = combo
                        app.hotKeyCombo = combo
                    },
                    onRecordingChange: { recording in
                        model.recording = recording
                        app.setHotKeySuspended(recording)
                    }
                )
                .fixedSize()

                PageText("Change it anytime in Preferences.", secondary: true)
            }
        }
    }
}

/// Holds the hotkey state the controls page's keycaps and recorder share.
@MainActor
private final class HotkeyModel: ObservableObject {
    @Published var combo: KeyCombo?
    @Published var recording = false

    init(combo: KeyCombo?) {
        self.combo = combo
    }
}

/// SwiftUI wrapper around the AppKit `ShortcutRecorderButton` used in
/// Preferences, so onboarding records the hotkey with the exact same control.
private struct HotkeyRecorder: NSViewRepresentable {
    let combo: KeyCombo?
    let onChange: (KeyCombo?) -> Void
    let onRecordingChange: (Bool) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton(combo: combo)
        button.onChange = onChange
        button.onRecordingChange = onRecordingChange
        return button
    }

    func updateNSView(_ nsView: ShortcutRecorderButton, context: Context) {}
}

/// The hero for the controls page: keycaps showing the current shortcut. While
/// the recorder below is recording, the caps track the modifiers being held
/// live; otherwise they show the saved shortcut. Mirrors Signal's onboarding.
private struct HotkeyKeysView: View {
    @ObservedObject var model: HotkeyModel

    @State private var live: [String] = []

    // Lightweight poll (reads current modifier flags), running only while this
    // page is on screen and only used while recording.
    private let ticker = Timer.publish(every: 0.08, on: .main, in: .common).autoconnect()

    private var display: [String] {
        model.recording ? live : Self.symbols(for: model.combo)
    }

    var body: some View {
        HStack(spacing: 10) {
            if display.isEmpty {
                Keycap(label: model.recording ? "…" : "·")
            } else {
                ForEach(Array(display.enumerated()), id: \.offset) { _, symbol in
                    Keycap(label: symbol)
                }
            }
        }
        .animation(.snappy(duration: 0.15), value: display)
        .animation(.snappy(duration: 0.15), value: model.recording)
        .onReceive(ticker) { _ in
            guard model.recording else { return }
            live = Self.modifierSymbols(NSEvent.modifierFlags)
        }
    }

    private static func symbols(for combo: KeyCombo?) -> [String] {
        guard let combo else { return [] }
        return modifierSymbols(combo.modifiers) + [KeyCodeMap.string(for: combo.keyCode)]
    }

    /// Modifier symbols in canonical display order (⌃⌥⇧⌘).
    private static func modifierSymbols(_ modifiers: NSEvent.ModifierFlags) -> [String] {
        var out: [String] = []
        if modifiers.contains(.control) { out.append("⌃") }
        if modifiers.contains(.option) { out.append("⌥") }
        if modifiers.contains(.shift) { out.append("⇧") }
        if modifiers.contains(.command) { out.append("⌘") }
        return out
    }
}

private struct GetStartedPage: View {
    var body: some View {
        PageScaffold(title: "UltraWin lives in your menu bar") {
            MenuBarDemo()
        } content: {
            PageText("Always at hand, one click away.")
                .frame(maxWidth: 380)
        }
    }
}

/// Looping demo: the top of a Mac screen, where the UltraWin status item
/// highlights and drops its menu open. The menu mirrors the real one built by
/// `StatusItemController`, minus the session-dependent items.
private struct MenuBarDemo: View {
    @State private var open = false

    private let barHeight: CGFloat = 22
    /// The status item is vertically centered in the bar, so its menu has to
    /// drop by the remaining bar height to hang off the bottom edge.
    private var menuDrop: CGFloat { barHeight - 3 }

    private var screenShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 12,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: 12,
            style: .continuous
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            menuBar
            Spacer(minLength: 0)
        }
        .frame(width: 300, height: 128, alignment: .top)
        .background(
            LinearGradient(
                colors: [Color.blue.opacity(0.28), Color.blue.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(screenShape)
        .overlay(screenShape.strokeBorder(.separator, lineWidth: 1))
        .task { await runLoop() }
    }

    private var menuBar: some View {
        HStack(spacing: 9) {
            Image(systemName: "apple.logo")
            Text("Finder").font(.system(size: 9, weight: .semibold))
            Text("File")
            Text("Edit")

            Spacer(minLength: 0)

            statusItem
            Image(systemName: "wifi")
            Image(systemName: "battery.75")
            Text("9:41")
        }
        .font(.system(size: 9))
        .foregroundStyle(.primary.opacity(0.75))
        .padding(.horizontal, 8)
        .frame(height: barHeight)
        .background(Color.primary.opacity(0.08))
    }

    private var statusItem: some View {
        Image(systemName: "rectangle.dashed.badge.record")
            .font(.system(size: 10))
            .foregroundStyle(open ? AnyShapeStyle(.white) : AnyShapeStyle(.primary.opacity(0.75)))
            .frame(width: 18, height: 16)
            .background(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(open ? Color.blue : Color.clear)
            )
            .overlay(alignment: .topTrailing) {
                if open {
                    menu
                        .offset(x: 6, y: menuDrop)
                        .transition(.scale(scale: 0.92, anchor: .topTrailing).combined(with: .opacity))
                }
            }
    }

    private var menu: some View {
        VStack(alignment: .leading, spacing: 0) {
            menuRow("Select Region to Share…")
            menuSeparator
            menuRow("Snap to 16:9")
            menuRow("Dim Outside Region")
            menuSeparator
            menuRow("Preferences…")
        }
        .padding(.vertical, 4)
        .frame(width: 132, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(.separator, lineWidth: 1)
        )
    }

    private func menuRow(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 9))
            .foregroundStyle(.primary.opacity(0.8))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var menuSeparator: some View {
        Rectangle()
            .fill(.separator)
            .frame(height: 1)
            .padding(.vertical, 3)
    }

    private func runLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(0.9))
            withAnimation(.snappy(duration: 0.4)) { open = true }
            try? await Task.sleep(for: .seconds(2.8))
            withAnimation(.easeOut(duration: 0.3)) { open = false }
            try? await Task.sleep(for: .seconds(0.6))
        }
    }
}

/// Final page: asks for Screen Recording up front, so the first share isn't
/// interrupted by the system prompt. macOS only shows that prompt once — after
/// that the request is a no-op, so the button falls back to System Settings.
private struct PermissionPage: View {
    @State private var granted = Self.hasAccess()
    @State private var asked = false

    /// Every read of the permission goes through here so the DEBUG override
    /// below holds for the whole page, not just its initial state.
    private static func hasAccess() -> Bool {
        #if DEBUG
        // Launch with `-UWFakeMissingPermission YES` to exercise this page's
        // ungranted flow on a Mac that has already granted Screen Recording.
        if UserDefaults.standard.bool(forKey: "UWFakeMissingPermission") { return false }
        #endif
        return CGPreflightScreenCaptureAccess()
    }

    var body: some View {
        PageScaffold(title: granted ? "You're all set" : "One last thing") {
            Image(systemName: granted ? "checkmark.shield.fill" : "lock.shield")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(granted ? Color.green : Color.blue)
                .frame(width: 88, height: 88)
                .background((granted ? Color.green : Color.blue).opacity(0.12), in: Circle())
                .animation(.snappy(duration: 0.35), value: granted)
        } content: {
            VStack(spacing: 16) {
                PageText("UltraWin needs Screen Recording permission — that's what lets it mirror your selection. Nothing ever leaves your Mac.")
                    .frame(maxWidth: 400)

                if granted {
                    PageText("Screen Recording is enabled.", secondary: true)
                } else {
                    Button(asked ? "Open System Settings" : "Grant Permission") { request() }
                        .buttonStyle(.bordered)

                    if asked {
                        PageText("Enable UltraWin under Privacy & Security → Screen Recording, then relaunch the app.", secondary: true)
                            .frame(maxWidth: 400)
                    }
                }
            }
        }
        .task { await pollUntilGranted() }
    }

    private func request() {
        if asked {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
            return
        }
        asked = true
        _ = CGRequestScreenCaptureAccess()
        if Self.hasAccess() {
            withAnimation(.snappy(duration: 0.35)) { granted = true }
        }
    }

    /// Access is granted out-of-band in the system prompt, so watch for it
    /// while the page is on screen rather than trusting the request's result.
    private func pollUntilGranted() async {
        while !granted, !Task.isCancelled {
            try? await Task.sleep(for: .seconds(0.5))
            if Self.hasAccess() {
                withAnimation(.snappy(duration: 0.35)) { granted = true }
            }
        }
    }
}
