import AppKit
import CoreMedia

/// Borderless window covering the virtual display; captured frames are set as
/// its layer contents. The user never sees it — the display isn't physical —
/// but meeting apps capture it when the virtual display is shared.
@MainActor
final class VirtualScreenWindow {
    private let window: NSWindow
    /// Keeps the currently displayed frame's backing alive so ScreenCaptureKit
    /// doesn't recycle the IOSurface while it's on screen.
    private var retainedFrame: CMSampleBuffer?

    init(screen: NSScreen) {
        window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.backgroundColor = .black
        window.isOpaque = true
        window.hasShadow = false
        window.ignoresMouseEvents = true
        // High level so stray windows wandering onto the virtual display never
        // cover the shared content.
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        view.layer?.contentsGravity = .resizeAspect
        window.contentView = view
        window.orderFrontRegardless()
    }

    func display(surface: IOSurfaceRef, retaining sample: CMSampleBuffer) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        window.contentView?.layer?.contents = surface
        CATransaction.commit()
        retainedFrame = sample
    }

    func updateFrame(to screen: NSScreen) {
        window.setFrame(screen.frame, display: true)
    }

    func close() {
        retainedFrame = nil
        window.close()
    }
}
