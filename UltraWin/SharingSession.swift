import AppKit
import CoreMedia

/// One active "share this region" session: owns the virtual display, the
/// capture stream, the render window on the virtual screen, and the on-screen
/// highlight overlay.
@MainActor
final class SharingSession {
    private(set) var region: CGRect
    private(set) var screen: NSScreen
    let aspectLocked: Bool
    private let pixelScale: CGFloat
    private let virtualDisplay = VirtualDisplayController()
    private let capture = RegionCaptureEngine()
    private var renderWindow: VirtualScreenWindow?
    private var overlay: HighlightOverlayController?

    /// Called on the main queue when the capture stops on its own
    /// (e.g. permission revoked, display unplugged).
    var onStopped: ((Error?) -> Void)?

    var virtualDisplayID: CGDirectDisplayID { virtualDisplay.displayID }

    var outputPointSize: CGSize {
        aspectLocked
            ? CGSize(width: 1920, height: 1080)
            : CGSize(width: region.width.rounded(), height: region.height.rounded())
    }

    init(region: CGRect, screen: NSScreen, aspectLocked: Bool, dimAlpha: CGFloat) async throws {
        self.region = HighlightOverlayController.clampRegion(
            region, to: screen, aspectRatio: aspectLocked ? 16.0 / 9.0 : nil
        )
        self.screen = screen
        self.aspectLocked = aspectLocked
        // Match the source screen: HiDPI virtual display for Retina sources,
        // 1x for regular ultrawides (avoids pointless upscaling).
        self.pixelScale = screen.backingScaleFactor > 1.5 ? 2 : 1

        // The overlay must exist before the capture filter is built so our app
        // is present in the shareable content and gets excluded.
        let overlay = HighlightOverlayController(
            region: self.region,
            screen: screen,
            dimAlpha: dimAlpha,
            aspectRatio: aspectLocked ? 16.0 / 9.0 : nil
        )
        self.overlay = overlay

        guard virtualDisplay.create(name: "UltraWin Display", pointSize: outputPointSize, hiDPI: pixelScale == 2),
              let virtualScreen = await NSScreen.waitForScreen(displayID: virtualDisplay.displayID)
        else {
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
            self?.virtualDisplay.destroy()
            self?.onStopped?(error)
        }

        do {
            try await capture.start(geometry: currentGeometry())
        } catch {
            teardownUI()
            virtualDisplay.destroy()
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

    func setDimAlpha(_ alpha: CGFloat) {
        overlay?.setDimAlpha(alpha)
    }

    func stop() async {
        capture.onStopped = nil
        teardownUI()
        await capture.stop()
        virtualDisplay.destroy()
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

    /// In free-form mode a resize changes the virtual display's resolution;
    /// apply the new mode and follow the (possibly re-framed) virtual screen.
    private func applyOutputSizeIfChanged() async {
        guard !aspectLocked, virtualDisplay.currentModePointSize != outputPointSize else { return }
        virtualDisplay.applyMode(pointSize: outputPointSize, hiDPI: pixelScale == 2)
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
