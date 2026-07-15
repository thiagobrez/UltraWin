import SwiftUI
import AppKit

/// First-launch onboarding: a small paged tour that welcomes the user and
/// explains the ideas behind UltraWin — the invisible virtual display, picking
/// "UltraWin Display" in the meeting app, and the controls. Hosted in a plain
/// `NSWindow` by `OnboardingWindowController`; `onFinish` is called when the
/// user reaches the end (or taps Skip).
struct OnboardingView: View {
    /// Called when onboarding is completed or skipped. The window controller
    /// uses this to persist the "seen" flag and close the window.
    let onFinish: () -> Void

    @State private var page = 0
    /// Drives the direction of the slide transition between pages.
    @State private var forward = true

    private let pageCount = 5
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
        case 2: MeetingPage()
        case 3: ControlsPage()
        default: GetStartedPage()
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

/// One keycap of the hotkey hint (⌘ ⇧ U).
private struct Keycap: View {
    let label: String
    var body: some View {
        Text(label)
            .font(.system(size: 18, weight: .semibold, design: .rounded))
            .frame(width: 40, height: 40)
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
            PageText("Share only part of your ultrawide screen in video calls — your apps stay exactly where they are.")
                .frame(maxWidth: 380)
        }
    }

    private var appIcon: NSImage {
        NSApp.applicationIconImage ?? NSImage(named: "AppIcon") ?? NSImage()
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
                PageText("Drag-select any region of your screen. UltraWin creates an invisible virtual display — “UltraWin Display” — that continuously mirrors it.")
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
                PageText("In Zoom, Meet, or Teams, share the screen named “UltraWin Display”. Everyone sees just your selected region — never the rest of your screen.")
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
    var body: some View {
        PageScaffold(title: "Select and control") {
            HStack(spacing: 8) {
                Keycap(label: "⌘")
                Keycap(label: "⇧")
                Keycap(label: "U")
            }
        } content: {
            VStack(spacing: 10) {
                PageText("Press the hotkey from any app to select a region — press it again to stop sharing. You can change it in Preferences.")
                    .frame(maxWidth: 400)
                PageText("While sharing, drag the frame's edges to move it and corners to resize — live. The menu bar icon has dim levels and a 16:9 snap for a clean 1080p output.", secondary: true)
                    .frame(maxWidth: 400)
            }
        }
    }
}

private struct GetStartedPage: View {
    var body: some View {
        PageScaffold(title: "Ready when you are") {
            Image(systemName: "rectangle.dashed.badge.record")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(.blue)
                .frame(width: 88, height: 88)
                .background(Color.blue.opacity(0.12), in: Circle())
        } content: {
            VStack(spacing: 10) {
                PageText("UltraWin lives in your menu bar. Select a region to share whenever you're ready.")
                    .frame(maxWidth: 380)
                PageText("The first time, macOS will ask for Screen Recording permission — that's what lets UltraWin mirror your selection. Nothing ever leaves your Mac.", secondary: true)
                    .frame(maxWidth: 380)
            }
        }
    }
}
