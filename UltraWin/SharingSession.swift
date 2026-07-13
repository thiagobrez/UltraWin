import AppKit
import CoreMedia

/// One active "share this region" session: owns the virtual display, the
/// capture stream, the render window on the virtual screen, and the on-screen
/// highlight overlay.
@MainActor
final class SharingSession {
    private(set) var region: CGRect
    private(set) var screen: NSScreen
    private(set) var aspectLocked: Bool
    private let pixelScale: CGFloat
    /// Shared with AppController: the display stays attached across sessions so
    /// starting a share never triggers the display-reconfiguration flicker.
    private let virtualDisplay: VirtualDisplayController
    private let capture = RegionCaptureEngine()
    private var renderWindow: VirtualScreenWindow?
    private var overlay: HighlightOverlayController?

    /// Called on the main queue when the capture stops on its own
    /// (e.g. permission revoked, display unplugged).
    var onStopped: ((Error?) -> Void)?

    var outputPointSize: CGSize {
        aspectLocked
            ? CGSize(width: 1920, height: 1080)
            : CGSize(width: region.width.rounded(), height: region.height.rounded())
    }

    /// `overlay` is created by the caller (already dimming the region) so the
    /// on-screen dim can hand off from the selection overlay without the screen
    /// flashing undimmed. It must exist before the capture filter is built, so
    /// our app is present in the shareable content and gets excluded.
    init(
        screen: NSScreen,
        aspectLocked: Bool,
        overlay: HighlightOverlayController,
        virtualDisplay: VirtualDisplayController
    ) async throws {
        self.region = overlay.region
        self.screen = screen
        self.aspectLocked = aspectLocked
        // Match the source screen: HiDPI virtual display for Retina sources,
        // 1x for regular ultrawides (avoids pointless upscaling).
        self.pixelScale = screen.backingScaleFactor > 1.5 ? 2 : 1
        self.overlay = overlay
        self.virtualDisplay = virtualDisplay

        let virtualScreen = await VirtualDisplayController.suppressingReconfigurationFade { () -> NSScreen? in
            // Extend the idle (mirrored) display so it can show its own content;
            // this also parks it at the bottom-right corner of the arrangement.
            virtualDisplay.setMirroring(false)
            guard virtualDisplay.ensureReady(pointSize: outputPointSize, hiDPI: pixelScale == 2)
            else { return nil }
            return await NSScreen.waitForScreen(
                displayID: virtualDisplay.displayID,
                pointSize: outputPointSize,
                timeout: 3
            )
        }
        guard let virtualScreen else {
            teardownUI()
            throw UltraWinError.virtualDisplayFailed
        }
        renderWindow = VirtualScreenWindow(screen: virtualScreen)

        capture.onFrame = { [weak self] surface, sample in
            DispatchQueue.main.async {
                self?.renderWindow?.display(surface: surface, retaining: sample)
            }
        }
        capture.onStopped = { [weak self] error in
            self?.teardownUI()
            self?.onStopped?(error)
        }

        do {
            try await capture.start(geometry: currentGeometry())
        } catch {
            teardownUI()
            throw error
        }

        overlay.onRegionChange = { [weak self] rect, phase in
            Task { @MainActor in
                await self?.regionChanged(rect, phase: phase)
            }
        }
    }

    /// Applies a new region (from re-selection), possibly on another screen.
    func updateRegion(_ rect: CGRect, on newScreen: NSScreen) async throws {
        let screenChanged = newScreen != screen
        screen = newScreen
        region = HighlightOverlayController.clampRegion(
            rect, to: newScreen, aspectRatio: aspectLocked ? 16.0 / 9.0 : nil
        )
        overlay?.move(to: newScreen, region: region)
        await applyOutputSizeIfChanged()
        if screenChanged {
            await capture.stop()
            try await capture.start(geometry: currentGeometry())
        } else {
            capture.update(geometry: currentGeometry())
        }
    }

    /// Toggles 16:9 snapping on the live session: re-snaps the current region,
    /// updates the overlay so future edge drags follow the new mode, and swaps
    /// the virtual display between a fixed 1080p and the region's own size.
    func setAspectLocked(_ locked: Bool) async {
        guard locked != aspectLocked else { return }
        aspectLocked = locked
        let ratio: CGFloat? = locked ? 16.0 / 9.0 : nil
        region = HighlightOverlayController.clampRegion(region, to: screen, aspectRatio: ratio)
        overlay?.setAspectRatio(ratio)
        overlay?.setRegion(region)
        await applyOutputSizeIfChanged()
        capture.update(geometry: currentGeometry())
    }

    func setDimAlpha(_ alpha: CGFloat) {
        overlay?.setDimAlpha(alpha)
    }

    /// The virtual display intentionally stays attached (owned by AppController)
    /// so the next session can reuse it without a reconfiguration flicker.
    func stop() async {
        capture.onStopped = nil
        teardownUI()
        await capture.stop()
    }

    // MARK: - Private

    private func regionChanged(_ rect: CGRect, phase: HighlightOverlayController.Phase) async {
        region = rect.integral
        capture.update(geometry: currentGeometry())
        if phase == .ended {
            await applyOutputSizeIfChanged()
            capture.update(geometry: currentGeometry())
        }
    }

    /// Applies the current output size to the virtual display when it changed,
    /// then follows the (possibly re-framed) virtual screen. Driven by free-form
    /// resizes and by toggling the aspect lock, which flips the output between
    /// the region's own size and a fixed 1080p.
    private func applyOutputSizeIfChanged() async {
        guard virtualDisplay.currentModePointSize != outputPointSize else { return }
        await VirtualDisplayController.suppressingReconfigurationFade {
            _ = virtualDisplay.applyMode(pointSize: outputPointSize, hiDPI: pixelScale == 2)
        }
        if let virtualScreen = await NSScreen.waitForScreen(
            displayID: virtualDisplay.displayID,
            pointSize: outputPointSize,
            timeout: 3
        ) {
            renderWindow?.updateFrame(to: virtualScreen)
        }
    }

    private func currentGeometry() -> CaptureGeometry {
        CaptureGeometry(
            displayID: screen.displayID ?? CGMainDisplayID(),
            sourceRect: CGRect(
                x: region.minX - screen.frame.minX,
                y: screen.frame.maxY - region.maxY,
                width: region.width,
                height: region.height
            ),
            outputPixelSize: CGSize(
                width: outputPointSize.width * pixelScale,
                height: outputPointSize.height * pixelScale
            )
        )
    }

    private func teardownUI() {
        overlay?.close()
        overlay = nil
        renderWindow?.close()
        renderWindow = nil
    }
}
