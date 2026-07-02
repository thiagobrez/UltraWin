import AppKit

/// Owns the CGVirtualDisplay. Creating it is equivalent to plugging in a
/// monitor; releasing the object unplugs it.
@MainActor
final class VirtualDisplayController {
    private var display: CGVirtualDisplay?
    private(set) var displayID: CGDirectDisplayID = 0
    private(set) var currentModePointSize: CGSize = .zero

    func create(name: String, pointSize: CGSize, hiDPI: Bool) -> Bool {
        let descriptor = CGVirtualDisplayDescriptor()
        descriptor.setDispatchQueue(DispatchQueue.main)
        descriptor.name = name
        descriptor.maxPixelsWide = 10240
        descriptor.maxPixelsHigh = 10240
        // Physical size scaled for a plausible ~110 ppi so macOS reports a sane DPI.
        descriptor.sizeInMillimeters = CGSize(
            width: pointSize.width * 25.4 / 110,
            height: pointSize.height * 25.4 / 110
        )
        descriptor.productID = 0x5557
        descriptor.vendorID = 0x1234
        descriptor.serialNum = 0x0001

        let display = CGVirtualDisplay(descriptor: descriptor)
        self.display = display
        displayID = display.displayID
        return applyMode(pointSize: pointSize, hiDPI: hiDPI)
    }

    @discardableResult
    func applyMode(pointSize: CGSize, hiDPI: Bool) -> Bool {
        guard let display else { return false }
        let width = UInt(max(64, pointSize.width.rounded()))
        let height = UInt(max(64, pointSize.height.rounded()))
        let settings = CGVirtualDisplaySettings()
        settings.hiDPI = hiDPI ? 1 : 0
        settings.modes = [CGVirtualDisplayMode(width: width, height: height, refreshRate: 60)]
        let applied = display.apply(settings)
        if applied {
            currentModePointSize = CGSize(width: CGFloat(width), height: CGFloat(height))
        } else {
            NSLog("UltraWin: applySettings failed for mode \(width)x\(height)")
        }
        return applied
    }

    func destroy() {
        display = nil
        displayID = 0
        currentModePointSize = .zero
    }
}
