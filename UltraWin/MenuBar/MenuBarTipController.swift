import AppKit

/// One-shot floating tooltip anchored under the status item, shown right after
/// onboarding so the user knows UltraWin lives in the menu bar.
@MainActor
final class MenuBarTipController {
    private var window: NSWindow?
    private var monitors: [Any] = []
    private var onDismiss: (() -> Void)?

    /// `anchor` is the status item button's frame in screen coordinates.
    func show(anchoredTo anchor: CGRect, onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss

        let view = MenuBarTipView(text: "UltraWin lives here!")
        let size = view.tipSize
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.contentView = view
        self.window = window

        // Arrow tip just below the status item, horizontally centered on it but
        // kept on the item's screen.
        var origin = CGPoint(
            x: anchor.midX - size.width / 2,
            y: anchor.minY - 2 - size.height
        )
        if let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor) }) {
            let visible = screen.visibleFrame
            origin.x = min(max(origin.x, visible.minX + 4), visible.maxX - size.width - 4)
        }
        view.arrowMidX = anchor.midX - origin.x

        // Slide down into place while fading in. (NSWindow only animates
        // whole-frame changes, not origin alone.)
        let finalFrame = CGRect(origin: origin, size: size)
        window.alphaValue = 0
        window.setFrame(finalFrame.offsetBy(dx: 0, dy: 4), display: false)
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            window.animator().alphaValue = 1
            window.animator().setFrame(finalFrame, display: true)
        }

        // The tip window is click-through, so any click means the user moved
        // on — the status item click itself is covered by menuNeedsUpdate.
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: clicks, handler: { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: clicks, handler: { [weak self] event in
            Task { @MainActor in self?.dismiss() }
            return event
        }) {
            monitors.append(local)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            guard let self, self.window === window else { return }
            self.dismiss()
        }
    }

    func dismiss() {
        for monitor in monitors {
            NSEvent.removeMonitor(monitor)
        }
        monitors = []

        if let window {
            self.window = nil
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.3
                window.animator().alphaValue = 0
            }, completionHandler: {
                window.close()
            })
        }

        let completion = onDismiss
        onDismiss = nil
        completion?()
    }
}

/// Dark rounded bubble with an up-pointing arrow along the top edge.
private final class MenuBarTipView: NSView {
    private let text: String
    private let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 13, weight: .medium),
        .foregroundColor: NSColor.white.withAlphaComponent(0.95),
    ]
    private let padding = CGSize(width: 14, height: 8)
    private let arrowSize = CGSize(width: 14, height: 7)

    /// Where the arrow points, in this view's coordinates — usually the
    /// center, but not when the bubble was clamped to the screen edge.
    var arrowMidX: CGFloat = 0

    init(text: String) {
        self.text = text
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    var tipSize: CGSize {
        let textSize = text.size(withAttributes: attributes)
        return CGSize(
            width: textSize.width + padding.width * 2,
            height: textSize.height + padding.height * 2 + arrowSize.height
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        let bubble = CGRect(
            x: 0, y: 0,
            width: bounds.width,
            height: bounds.height - arrowSize.height
        )
        let path = NSBezierPath(roundedRect: bubble, xRadius: 8, yRadius: 8)

        let arrowMidX = min(max(self.arrowMidX, 8 + arrowSize.width / 2), bounds.maxX - 8 - arrowSize.width / 2)
        path.move(to: CGPoint(x: arrowMidX - arrowSize.width / 2, y: bubble.maxY))
        path.line(to: CGPoint(x: arrowMidX, y: bounds.maxY))
        path.line(to: CGPoint(x: arrowMidX + arrowSize.width / 2, y: bubble.maxY))
        path.close()

        NSColor.black.withAlphaComponent(0.75).setFill()
        path.fill()

        let textSize = text.size(withAttributes: attributes)
        text.draw(
            at: CGPoint(x: bubble.midX - textSize.width / 2, y: bubble.midY - textSize.height / 2),
            withAttributes: attributes
        )
    }
}
