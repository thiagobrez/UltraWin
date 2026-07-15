import AppKit
import ScreenCaptureKit
import CoreMedia

struct CaptureGeometry: Equatable {
    var displayID: CGDirectDisplayID
    /// Region to capture in points, display-local, top-left origin
    /// (ScreenCaptureKit's coordinate space for display capture).
    var sourceRect: CGRect
    var outputPixelSize: CGSize
}

/// Captures a region of a physical display with ScreenCaptureKit, excluding
/// UltraWin's own windows (overlay, frame handles) from the content.
final class RegionCaptureEngine: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    private let sampleQueue = DispatchQueue(label: "ski.brezin.ultrawin.capture")
    private(set) var geometry: CaptureGeometry?
    private var pendingGeometry: CaptureGeometry?
    private var updateInFlight = false

    /// Called on `sampleQueue` with each complete frame.
    var onFrame: ((IOSurfaceRef, CMSampleBuffer) -> Void)?
    /// Called on the main queue if the stream stops on its own.
    var onStopped: ((Error?) -> Void)?

    @MainActor
    func start(geometry: CaptureGeometry) async throws {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        } catch {
            throw UltraWinError.screenRecordingDenied
        }
        guard let display = content.displays.first(where: { $0.displayID == geometry.displayID }) else {
            throw UltraWinError.physicalDisplayNotFound
        }
        // Exclude our whole app so the dim/frame overlays never appear in the
        // shared image (covers windows created later in the session too).
        let ownApps = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])

        let stream = SCStream(filter: filter, configuration: Self.configuration(for: geometry), delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        try await stream.startCapture()
        self.stream = stream
        self.geometry = geometry
    }

    /// Live geometry updates (drag/resize). Coalesced so a fast drag doesn't
    /// queue up stale configurations.
    @MainActor
    func update(geometry: CaptureGeometry) {
        guard geometry != self.geometry else { return }
        pendingGeometry = geometry
        pumpUpdate()
    }

    @MainActor
    private func pumpUpdate() {
        guard !updateInFlight, let next = pendingGeometry, let stream else { return }
        pendingGeometry = nil
        updateInFlight = true
        geometry = next
        stream.updateConfiguration(Self.configuration(for: next)) { [weak self] error in
            DispatchQueue.main.async {
                if let error {
                    NSLog("UltraWin: updateConfiguration failed: \(error)")
                }
                self?.updateInFlight = false
                self?.pumpUpdate()
            }
        }
    }

    @MainActor
    func stop() async {
        pendingGeometry = nil
        guard let stream else { return }
        self.stream = nil
        try? await stream.stopCapture()
    }

    private static func configuration(for geometry: CaptureGeometry) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        config.sourceRect = geometry.sourceRect
        config.width = Int(geometry.outputPixelSize.width)
        config.height = Int(geometry.outputPixelSize.height)
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.colorSpaceName = CGColorSpace.sRGB
        config.showsCursor = true
        config.queueDepth = 5
        return config
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let statusRaw = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: statusRaw) == .complete,
              let pixelBuffer = sampleBuffer.imageBuffer,
              let surface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue()
        else { return }
        onFrame?(surface, sampleBuffer)
    }

    // MARK: - SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.stream != nil else { return }
            self.stream = nil
            self.onStopped?(error)
        }
    }
}
