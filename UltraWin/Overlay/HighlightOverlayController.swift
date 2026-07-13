import AppKit

/// On-screen indication of the shared region: a click-through window dims
/// everything outside the region, and small interactive windows form a frame —
/// edge strips move the region, corner handles resize it. Everything inside
/// the region stays fully interactive because the interior window ignores
/// mouse events — except while ⌘ is held, when it captures drags so the
/// whole region can be moved from anywhere inside it.
@MainActor
final class HighlightOverlayController {
    enum Phase { case dragging, ended }

    enum Corner: CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight

        var opposite: Corner {
            switch self {
            case .topLeft: return .bottomRight
            case .topRight: return .bottomLeft
            case .bottomLeft: return .topRight
            case .bottomRight: return .topLeft
            }
        }

        func point(in rect: CGRect) -> CGPoint {
            switch self {
            case .topLeft: return CGPoint(x: rect.minX, y: rect.maxY)
            case .topRight: return CGPoint(x: rect.maxX, y: rect.maxY)
            case .bottomLeft: return CGPoint(x: rect.minX, y: rect.minY)
            case .bottomRight: return CGPoint(x: rect.maxX, y: rect.minY)
            }
        }
    }

    enum Edge: CaseIterable {
        case top, bottom, left, right
    }

    enum HandleKind {
        case move(Edge)
        case resize(Corner)
        case interior
    }

    var onRegionChange: ((CGRect, Phase) -> Void)?

    private(set) var region: CGRect
    private(set) var screen: NSScreen
    private var aspectRatio: CGFloat?
    private let stopHint: String?
    private let dimWindow: NSWindow
    private let dimView: DimView
    private var handleWindows: [HandleWindow] = []
    private var interiorWindow: HandleWindow?
    private var hintWindow: NSWindow?
    private var commandPollTimer: Timer?
    private var dragStartRegion: CGRect = .zero
    private static let minSize = CGSize(width: 160, height: 90)
    private static let edgeThickness: CGFloat = 12
    private static let cornerSize: CGFloat = 20

    init(region: CGRect, screen: NSScreen, dimAlpha: CGFloat, aspectRatio: CGFloat?, stopHint: String?) {
        self.region = region
        self.screen = screen
        self.aspectRatio = aspectRatio
        self.stopHint = stopHint

        dimView = DimView(frame: NSRect(origin: .zero, size: screen.frame.size))
        dimView.dimAlpha = dimAlpha
        dimWindow = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        dimWindow.isReleasedWhenClosed = false
        dimWindow.isOpaque = false
        dimWindow.backgroundColor = .clear
        dimWindow.hasShadow = false
        dimWindow.ignoresMouseEvents = true
        dimWindow.level = .floating
        dimWindow.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        dimWindow.contentView = dimView
        dimWindow.orderFrontRegardless()

        let kinds: [HandleKind] = [.interior] + Edge.allCases.map { .move($0) } + Corner.allCases.map { .resize($0) }
        for kind in kinds {
            let window = HandleWindow(kind: kind, controller: self)
            if case .interior = kind { interiorWindow = window }
            handleWindows.append(window)
            window.orderFrontRegardless()
        }
        layout()

        // The interior only becomes draggable while ⌘ is held. There is no
        // permission-free global key monitor, so poll the hardware state.
        commandPollTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateInteriorDraggability() }
        }
        showMoveHint()
    }

    func setDimAlpha(_ alpha: CGFloat) {
        dimView.dimAlpha = alpha
        dimView.needsDisplay = true
    }

    func move(to newScreen: NSScreen, region newRegion: CGRect) {
        screen = newScreen
        region = newRegion
        dimWindow.setFrame(newScreen.frame, display: true)
        dimView.frame = NSRect(origin: .zero, size: newScreen.frame.size)
        layout()
        showMoveHint()
    }

    func setRegion(_ newRegion: CGRect) {
        region = newRegion
        layout()
    }

    /// Switches the snapping behavior of subsequent edge/corner drags. The
    /// current region isn't reshaped here — the caller re-clamps it and calls
    /// `setRegion` — so this only affects future resizes.
    func setAspectRatio(_ ratio: CGFloat?) {
        aspectRatio = ratio
    }

    func close() {
        commandPollTimer?.invalidate()
        commandPollTimer = nil
        hintWindow?.close()
        hintWindow = nil
        dimWindow.close()
        for window in handleWindows {
            window.close()
        }
        handleWindows = []
        interiorWindow = nil
    }

    // MARK: - Dragging (called by HandleView)

    func beginDrag() {
        dragStartRegion = region
        fadeOutHint()
    }

    func dragUpdated(kind: HandleKind, delta: CGVector, phase: Phase) {
        region = proposedRegion(for: kind, delta: delta)
        layout()
        onRegionChange?(region, phase)
    }

    /// Handles sit fully inside the region, so the region itself can reach
    /// the screen edges — except the top: the system refuses to place windows
    /// over the menu bar, and a handle shoved off the border misaligns with
    /// the region (the line appears to run past the knobs).
    private static func interactionBounds(for screen: NSScreen) -> CGRect {
        var bounds = screen.frame
        let menuBarTop = screen.visibleFrame.maxY
        if menuBarTop < bounds.maxY {
            bounds.size.height = menuBarTop - bounds.minY
        }
        return bounds
    }

    static func clampRegion(_ region: CGRect, to screen: NSScreen, aspectRatio: CGFloat? = nil) -> CGRect {
        let bounds = interactionBounds(for: screen)
        var size = CGSize(
            width: min(region.width, bounds.width),
            height: min(region.height, bounds.height)
        )
        if let ratio = aspectRatio {
            size.width = min(size.width, size.height * ratio)
            size.height = size.width / ratio
        }
        return CGRect(
            x: min(max(region.minX, bounds.minX), bounds.maxX - size.width),
            y: min(max(region.minY, bounds.minY), bounds.maxY - size.height),
            width: size.width,
            height: size.height
        ).integral
    }

    private func proposedRegion(for kind: HandleKind, delta: CGVector) -> CGRect {
        let bounds = Self.interactionBounds(for: screen)
        switch kind {
        case .move, .interior:
            var origin = CGPoint(x: dragStartRegion.minX + delta.dx, y: dragStartRegion.minY + delta.dy)
            origin.x = min(max(origin.x, bounds.minX), bounds.maxX - dragStartRegion.width)
            origin.y = min(max(origin.y, bounds.minY), bounds.maxY - dragStartRegion.height)
            return CGRect(origin: origin, size: dragStartRegion.size).integral

        case .resize(let corner):
            let anchor = corner.opposite.point(in: dragStartRegion)
            let moving = CGPoint(
                x: corner.point(in: dragStartRegion).x + delta.dx,
                y: corner.point(in: dragStartRegion).y + delta.dy
            )
            // Keep orientation: the moving corner stays on its original side
            // of the anchor, so the rect never flips.
            let signX: CGFloat = corner.point(in: dragStartRegion).x >= anchor.x ? 1 : -1
            let signY: CGFloat = corner.point(in: dragStartRegion).y >= anchor.y ? 1 : -1
            let availableW = signX > 0 ? bounds.maxX - anchor.x : anchor.x - bounds.minX
            let availableH = signY > 0 ? bounds.maxY - anchor.y : anchor.y - bounds.minY
            var width = max(Self.minSize.width, signX * (moving.x - anchor.x))
            var height = max(Self.minSize.height, signY * (moving.y - anchor.y))
            if let ratio = aspectRatio {
                width = min(width, availableW, availableH * ratio)
                height = width / ratio
            } else {
                width = min(width, availableW)
                height = min(height, availableH)
            }
            return CGRect(
                x: signX > 0 ? anchor.x : anchor.x - width,
                y: signY > 0 ? anchor.y : anchor.y - height,
                width: width,
                height: height
            ).integral
        }
    }

    // MARK: - ⌘ drag from inside

    private func updateInteriorDraggability() {
        guard let interior = interiorWindow else { return }
        let shouldIgnore = !NSEvent.modifierFlags.contains(.command)
        guard interior.ignoresMouseEvents != shouldIgnore else { return }
        interior.ignoresMouseEvents = shouldIgnore
        if let view = interior.contentView {
            interior.invalidateCursorRects(for: view)
        }
        if interior.frame.contains(NSEvent.mouseLocation) {
            (shouldIgnore ? NSCursor.arrow : NSCursor.openHand).set()
        }
    }

    // MARK: - Move hint

    private func showMoveHint() {
        hintWindow?.close()
        hintWindow = nil
        let view = MoveHintView(stopHint: stopHint)
        let size = view.hintSize
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
        window.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.contentView = view
        hintWindow = window
        layoutHint()
        window.orderFrontRegardless()

        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, self.hintWindow === window else { return }
            self.fadeOutHint()
        }
    }

    private func fadeOutHint() {
        guard let window = hintWindow else { return }
        hintWindow = nil
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.5
            window.animator().alphaValue = 0
        }, completionHandler: {
            window.close()
        })
    }

    private func layoutHint() {
        guard let window = hintWindow else { return }
        let size = window.frame.size
        window.setFrameOrigin(CGPoint(
            x: region.midX - size.width / 2,
            y: region.midY - size.height / 2
        ))
    }

    // MARK: - Layout

    private func layout() {
        dimView.holeRect = region.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
        dimView.needsDisplay = true
        for window in handleWindows {
            window.setFrame(frame(for: window.kind), display: true)
        }
        layoutHint()
    }

    // Handles live just inside the region so they never have to be placed
    // past the screen edge (which would get them shoved off the border).
    private func frame(for kind: HandleKind) -> CGRect {
        let t = Self.edgeThickness
        let c = Self.cornerSize
        let r = region
        switch kind {
        case .move(.top):
            return CGRect(x: r.minX + c, y: r.maxY - t, width: max(1, r.width - 2 * c), height: t)
        case .move(.bottom):
            return CGRect(x: r.minX + c, y: r.minY, width: max(1, r.width - 2 * c), height: t)
        case .move(.left):
            return CGRect(x: r.minX, y: r.minY + c, width: t, height: max(1, r.height - 2 * c))
        case .move(.right):
            return CGRect(x: r.maxX - t, y: r.minY + c, width: t, height: max(1, r.height - 2 * c))
        case .resize(let corner):
            let p = corner.point(in: r)
            return CGRect(
                x: p.x == r.minX ? r.minX : r.maxX - c,
                y: p.y == r.minY ? r.minY : r.maxY - c,
                width: c, height: c
            )
        case .interior:
            return r.insetBy(dx: t, dy: t)
        }
    }
}

// MARK: - Windows and views

private final class HandleWindow: NSPanel {
    let kind: HighlightOverlayController.HandleKind

    init(kind: HighlightOverlayController.HandleKind, controller: HighlightOverlayController) {
        self.kind = kind
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        if case .interior = kind {
            // Click-through until ⌘ is held (toggled by the controller), and
            // below the frame so edges and corners keep priority.
            ignoresMouseEvents = true
            level = .floating
        } else {
            level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        }
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        contentView = HandleView(kind: kind, controller: controller)
    }
}

private final class HandleView: NSView {
    private let kind: HighlightOverlayController.HandleKind
    private unowned let controller: HighlightOverlayController
    private var dragStartMouse: CGPoint = .zero

    init(kind: HighlightOverlayController.HandleKind, controller: HighlightOverlayController) {
        self.kind = kind
        self.controller = controller
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        switch kind {
        case .move, .interior: addCursorRect(bounds, cursor: .openHand)
        case .resize: addCursorRect(bounds, cursor: .crosshair)
        }
    }

    override func mouseDown(with event: NSEvent) {
        dragStartMouse = NSEvent.mouseLocation
        controller.beginDrag()
    }

    override func mouseDragged(with event: NSEvent) {
        controller.dragUpdated(kind: kind, delta: currentDelta(), phase: .dragging)
    }

    override func mouseUp(with event: NSEvent) {
        controller.dragUpdated(kind: kind, delta: currentDelta(), phase: .ended)
    }

    private func currentDelta() -> CGVector {
        let location = NSEvent.mouseLocation
        return CGVector(dx: location.x - dragStartMouse.x, dy: location.y - dragStartMouse.y)
    }

    override func draw(_ dirtyRect: NSRect) {
        let lineWidth: CGFloat = 2
        // The window sits just inside the region, so the border line runs
        // along its outer side(s).
        func borderLine(_ edge: HighlightOverlayController.Edge) -> CGRect {
            switch edge {
            case .top: return CGRect(x: 0, y: bounds.maxY - lineWidth, width: bounds.width, height: lineWidth)
            case .bottom: return CGRect(x: 0, y: 0, width: bounds.width, height: lineWidth)
            case .left: return CGRect(x: 0, y: 0, width: lineWidth, height: bounds.height)
            case .right: return CGRect(x: bounds.maxX - lineWidth, y: 0, width: lineWidth, height: bounds.height)
            }
        }

        NSColor.controlAccentColor.setFill()
        switch kind {
        case .move(let edge):
            borderLine(edge).fill()
        case .resize(let corner):
            let outerEdges: (HighlightOverlayController.Edge, HighlightOverlayController.Edge)
            switch corner {
            case .topLeft: outerEdges = (.top, .left)
            case .topRight: outerEdges = (.top, .right)
            case .bottomLeft: outerEdges = (.bottom, .left)
            case .bottomRight: outerEdges = (.bottom, .right)
            }
            borderLine(outerEdges.0).fill()
            borderLine(outerEdges.1).fill()
            // Centered in the corner window so the knob's white border keeps a
            // clean gap from the border lines instead of being clipped by them.
            let knobSize: CGFloat = 12
            let knob = bounds.insetBy(
                dx: (bounds.width - knobSize) / 2,
                dy: (bounds.height - knobSize) / 2
            )
            let path = NSBezierPath(roundedRect: knob, xRadius: 3, yRadius: 3)
            path.fill()
            NSColor.white.setStroke()
            path.lineWidth = 1.5
            path.stroke()
        case .interior:
            break
        }
    }
}

private final class MoveHintView: NSView {
    private let lines: [String]
    private let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 15, weight: .medium),
        .foregroundColor: NSColor.white.withAlphaComponent(0.95),
    ]
    private let padding = CGSize(width: 16, height: 9)
    private let lineSpacing: CGFloat = 4

    init(stopHint: String?) {
        var lines = ["Hold ⌘ and drag to move"]
        if let stopHint {
            lines.append("\(stopHint) to stop sharing")
        }
        self.lines = lines
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private var lineSize: CGSize { (lines.first ?? "").size(withAttributes: attributes) }

    var hintSize: CGSize {
        let width = lines.map { $0.size(withAttributes: attributes).width }.max() ?? 0
        let height = lineSize.height * CGFloat(lines.count) + lineSpacing * CGFloat(lines.count - 1)
        return CGSize(width: width + padding.width * 2, height: height + padding.height * 2)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.65).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
        let lineHeight = lineSize.height
        // Top line first: NSView is flipped-less, so start from the top edge.
        var y = bounds.maxY - padding.height - lineHeight
        for line in lines {
            let size = line.size(withAttributes: attributes)
            line.draw(at: CGPoint(x: bounds.midX - size.width / 2, y: y), withAttributes: attributes)
            y -= lineHeight + lineSpacing
        }
    }
}

private final class DimView: NSView {
    var holeRect: CGRect = .zero
    var dimAlpha: CGFloat = 0.3

    override func draw(_ dirtyRect: NSRect) {
        guard dimAlpha > 0 else { return }
        let path = NSBezierPath(rect: bounds)
        path.appendRect(holeRect.intersection(bounds))
        path.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(dimAlpha).setFill()
        path.fill()
    }
}
