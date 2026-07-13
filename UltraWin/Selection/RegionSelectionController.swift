import AppKit

/// Cmd-Shift-4 style drag-to-select. Shows one overlay panel per physical
/// screen; completes with the selected rect (global coordinates) and the
/// screen it belongs to, or nil if cancelled (Esc).
@MainActor
final class RegionSelectionController {
    private var panels: [SelectionPanel] = []
    private var completion: (((rect: CGRect, screen: NSScreen)?) -> Void)?

    var isActive: Bool { !panels.isEmpty }

    func begin(
        aspectRatio: CGFloat?,
        excludingDisplayIDs: Set<CGDirectDisplayID> = [],
        completion: @escaping ((rect: CGRect, screen: NSScreen)?) -> Void
    ) {
        guard !isActive else {
            completion(nil)
            return
        }
        self.completion = completion
        for screen in NSScreen.screens {
            if let id = screen.displayID, excludingDisplayIDs.contains(id) { continue }
            let panel = SelectionPanel(screen: screen, aspectRatio: aspectRatio, controller: self)
            panels.append(panel)
            panel.orderFrontRegardless()
        }
        guard !panels.isEmpty else {
            self.completion = nil
            completion(nil)
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        let mouse = NSEvent.mouseLocation
        let keyPanel = panels.first { $0.hostScreen.frame.contains(mouse) } ?? panels[0]
        keyPanel.makeKeyAndOrderFront(nil)
    }

    /// Reports the selected region but leaves the overlay on screen. The caller
    /// puts the replacement overlay up and then calls `dismiss()`, so the screen
    /// stays dimmed across the whole handoff and never flashes undimmed.
    func finish(rect: CGRect, on screen: NSScreen) {
        for panel in panels { panel.stopInteraction() }
        let callback = completion
        completion = nil
        callback?((rect, screen))
    }

    func cancel() {
        dismiss()
        let callback = completion
        completion = nil
        callback?(nil)
    }

    /// Tears down the selection overlay. Safe to call more than once.
    /// A non-zero `fadeDuration` fades the panels out instead of dropping them:
    /// the old dim stays composited on top of the session's own overlay for the
    /// whole fade, so the handoff can never show an undimmed frame even if
    /// window ordering isn't atomic across the two windows.
    func dismiss(fadeDuration: TimeInterval = 0) {
        let closing = panels
        panels = []
        guard fadeDuration > 0 else {
            for panel in closing {
                panel.orderOut(nil)
                panel.close()
            }
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = fadeDuration
            for panel in closing {
                panel.animator().alphaValue = 0
            }
        }, completionHandler: {
            for panel in closing {
                panel.close()
            }
        })
    }
}

private final class SelectionPanel: NSPanel {
    let hostScreen: NSScreen

    init(screen: NSScreen, aspectRatio: CGFloat?, controller: RegionSelectionController) {
        hostScreen = screen
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        let view = SelectionView(
            frame: NSRect(origin: .zero, size: screen.frame.size),
            aspectRatio: aspectRatio,
            screen: screen,
            controller: controller
        )
        contentView = view
        makeFirstResponder(view)
    }

    /// Freezes the panel once a selection is committed: it keeps dimming the
    /// screen during the handoff but no longer reacts to the mouse or Esc, so
    /// the bridge overlay can't be torn down early.
    func stopInteraction() {
        ignoresMouseEvents = true
        (contentView as? SelectionView)?.isFrozen = true
    }

    override var canBecomeKey: Bool { true }
}

private final class SelectionView: NSView {
    private let aspectRatio: CGFloat?
    private let screen: NSScreen
    private unowned let controller: RegionSelectionController
    private var dragStart: CGPoint?
    private var selectionRect: CGRect = .zero
    /// Set once the selection is committed; the view then only dims and ignores input.
    var isFrozen = false

    init(frame: NSRect, aspectRatio: CGFloat?, screen: NSScreen, controller: RegionSelectionController) {
        self.aspectRatio = aspectRatio
        self.screen = screen
        self.controller = controller
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func keyDown(with event: NSEvent) {
        if !isFrozen, event.keyCode == 53 { // Esc
            controller.cancel()
        } else {
            super.keyDown(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard !isFrozen else { return }
        window?.makeKey()
        dragStart = convert(event.locationInWindow, from: nil)
        selectionRect = .zero
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        let current = convert(event.locationInWindow, from: nil)
        selectionRect = Self.rect(from: start, to: current, aspectRatio: aspectRatio, in: bounds)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard dragStart != nil else { return }
        dragStart = nil
        if selectionRect.width >= 100, selectionRect.height >= 60 {
            let windowRect = convert(selectionRect, to: nil)
            guard let globalRect = window?.convertToScreen(windowRect) else { return }
            controller.finish(rect: globalRect.integral, on: screen)
        } else {
            // Too small — treat as a misclick and keep selecting.
            selectionRect = .zero
            needsDisplay = true
        }
    }

    private static func rect(from start: CGPoint, to current: CGPoint, aspectRatio: CGFloat?, in bounds: CGRect) -> CGRect {
        let clamped = CGPoint(
            x: min(max(current.x, bounds.minX), bounds.maxX),
            y: min(max(current.y, bounds.minY), bounds.maxY)
        )
        let signX: CGFloat = clamped.x >= start.x ? 1 : -1
        let signY: CGFloat = clamped.y >= start.y ? 1 : -1
        var width = abs(clamped.x - start.x)
        var height = abs(clamped.y - start.y)
        if let ratio = aspectRatio {
            let availableW = signX > 0 ? bounds.maxX - start.x : start.x - bounds.minX
            let availableH = signY > 0 ? bounds.maxY - start.y : start.y - bounds.minY
            width = min(width, availableW, availableH * ratio)
            height = width / ratio
        }
        return CGRect(
            x: signX > 0 ? start.x : start.x - width,
            y: signY > 0 ? start.y : start.y - height,
            width: width,
            height: height
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        let dim = NSBezierPath(rect: bounds)
        if selectionRect.width > 1 {
            dim.appendRect(selectionRect)
            dim.windingRule = .evenOdd
        }
        NSColor.black.withAlphaComponent(0.35).setFill()
        dim.fill()

        if selectionRect.width > 1 {
            NSColor.controlAccentColor.setStroke()
            let border = NSBezierPath(rect: selectionRect)
            border.lineWidth = 2
            border.stroke()
            drawSizeLabel()
        } else {
            drawHint()
        }
    }

    private func drawSizeLabel() {
        let text = "\(Int(selectionRect.width)) × \(Int(selectionRect.height))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = text.size(withAttributes: attributes)
        let padding: CGFloat = 6
        var origin = CGPoint(x: selectionRect.minX, y: selectionRect.maxY + padding)
        if origin.y + size.height > bounds.maxY {
            origin.y = selectionRect.maxY - size.height - padding
        }
        let background = CGRect(
            x: origin.x - padding, y: origin.y - 2,
            width: size.width + padding * 2, height: size.height + 4
        )
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: background, xRadius: 4, yRadius: 4).fill()
        text.draw(at: origin, withAttributes: attributes)
    }

    private func drawHint() {
        let text = aspectRatio == nil
            ? "Drag to select the area to share — Esc to cancel"
            : "Drag to select (16:9) — Esc to cancel"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.9),
        ]
        let size = text.size(withAttributes: attributes)
        let origin = CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2)
        let background = CGRect(
            x: origin.x - 16, y: origin.y - 10,
            width: size.width + 32, height: size.height + 20
        )
        NSColor.black.withAlphaComponent(0.6).setFill()
        NSBezierPath(roundedRect: background, xRadius: 10, yRadius: 10).fill()
        text.draw(at: origin, withAttributes: attributes)
    }
}
