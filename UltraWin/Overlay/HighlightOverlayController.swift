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
    private let aspectRatio: CGFloat?
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

    init(region: CGRect, screen: NSScreen, dimAlpha: CGFloat, aspectRatio: CGFloat?) {
        self.region = region
        self.screen = screen
        self.aspectRatio = aspectRatio

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

    private func proposedRegion(for kind: HandleKind, delta: CGVector) -> CGRect {
        let bounds = screen.frame
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
        let view = MoveHintView()
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

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
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

    private func frame(for kind: HandleKind) -> CGRect {
        let t = Self.edgeThickness
        let c = Self.cornerSize
        let r = region
        switch kind {
        case .move(.top):
            return CGRect(x: r.minX + c / 2, y: r.maxY - t / 2, width: max(1, r.width - c), height: t)
        case .move(.bottom):
            return CGRect(x: r.minX + c / 2, y: r.minY - t / 2, width: max(1, r.width - c), height: t)
        case .move(.left):
            return CGRect(x: r.minX - t / 2, y: r.minY + c / 2, width: t, height: max(1, r.height - c))
        case .move(.right):
            return CGRect(x: r.maxX - t / 2, y: r.minY + c / 2, width: t, height: max(1, r.height - c))
        case .resize(let corner):
            let p = corner.point(in: r)
            return CGRect(x: p.x - c / 2, y: p.y - c / 2, width: c, height: c)
        case .interior:
            return r.insetBy(dx: t / 2, dy: t / 2)
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
        NSColor.controlAccentColor.setFill()
        switch kind {
        case .move(let edge):
            let lineWidth: CGFloat = 2
            let line: CGRect
            switch edge {
            case .top, .bottom:
                line = CGRect(x: 0, y: bounds.midY - lineWidth / 2, width: bounds.width, height: lineWidth)
            case .left, .right:
                line = CGRect(x: bounds.midX - lineWidth / 2, y: 0, width: lineWidth, height: bounds.height)
            }
            line.fill()
        case .resize:
            let knob = bounds.insetBy(dx: 4, dy: 4)
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
    private let text = "Hold ⌘ and drag to move"
    private let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 15, weight: .medium),
        .foregroundColor: NSColor.white.withAlphaComponent(0.95),
    ]
    private let padding = CGSize(width: 16, height: 9)

    var hintSize: CGSize {
        let size = text.size(withAttributes: attributes)
        return CGSize(width: size.width + padding.width * 2, height: size.height + padding.height * 2)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.65).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
        let size = text.size(withAttributes: attributes)
        let origin = CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2)
        text.draw(at: origin, withAttributes: attributes)
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
