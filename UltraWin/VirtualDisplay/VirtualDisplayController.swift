import AppKit

/// Owns the CGVirtualDisplay. Creating it is equivalent to plugging in a
/// monitor; releasing the object unplugs it. The display stays attached for
/// the app's whole lifetime: mirrored while idle (a mirrored display occupies
/// no space in the arrangement, so the cursor can't wander onto it) and
/// extended + corner-parked only while a session needs it to show content.
/// The mirror/extend switches are display reconfigurations, so they blip the
/// screen — an accepted cost, paid only at session start and stop.
@MainActor
final class VirtualDisplayController {
    private var display: CGVirtualDisplay?
    private(set) var displayID: CGDirectDisplayID = 0
    private(set) var currentModePointSize: CGSize = .zero
    private(set) var currentHiDPI = false
    private(set) var isMirrored = false
    private var screenChangeObserver: NSObjectProtocol?

    var isCreated: Bool { display != nil }

    /// Mirrors (idle) or extends (sharing) the virtual display. Un-mirroring
    /// restores whatever arrangement macOS last remembered, so it re-parks the
    /// display at the corner immediately afterwards.
    func setMirroring(_ mirrored: Bool) {
        guard displayID != 0, mirrored != isMirrored else { return }
        let master = CGMainDisplayID()
        guard !mirrored || master != displayID else { return }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else { return }
        guard CGConfigureDisplayMirrorOfDisplay(config, displayID, mirrored ? master : kCGNullDirectDisplay) == .success else {
            CGCancelDisplayConfiguration(config)
            NSLog("UltraWin: failed to \(mirrored ? "enable" : "disable") mirroring for virtual display")
            return
        }
        guard CGCompleteDisplayConfiguration(config, .forSession) == .success else {
            NSLog("UltraWin: mirroring configuration did not apply")
            return
        }
        isMirrored = mirrored
        if !mirrored {
            moveToCornerAdjacentPosition()
        }
    }

    /// Creates the display if it doesn't exist yet, otherwise switches the
    /// existing one to the requested mode. Reusing the attached display avoids
    /// the systemwide reconfiguration flicker that plugging a display causes.
    func ensureReady(pointSize: CGSize, hiDPI: Bool) -> Bool {
        guard isCreated else {
            return create(name: "UltraWin Display", pointSize: pointSize, hiDPI: hiDPI)
        }
        guard currentModePointSize != pointSize || currentHiDPI != hiDPI else { return true }
        return applyMode(pointSize: pointSize, hiDPI: hiDPI)
    }

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
        guard applyMode(pointSize: pointSize, hiDPI: hiDPI) else { return false }
        if screenChangeObserver == nil {
            // Plugging/unplugging real monitors can re-snap the arrangement and
            // put the virtual display edge-adjacent again; re-park when it does.
            screenChangeObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { _ in
                MainActor.assumeIsolated { [weak self] in
                    self?.moveToCornerAdjacentPosition()
                }
            }
        }
        return true
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
            currentHiDPI = hiDPI
            moveToCornerAdjacentPosition()
        } else {
            NSLog("UltraWin: applySettings failed for mode \(width)x\(height)")
        }
        return applied
    }

    func destroy() {
        if let screenChangeObserver {
            NotificationCenter.default.removeObserver(screenChangeObserver)
            self.screenChangeObserver = nil
        }
        display = nil
        displayID = 0
        currentModePointSize = .zero
        currentHiDPI = false
        isMirrored = false
    }

    /// Runs `body` while holding a display-fade reservation. Attaching a display
    /// changes the display topology, which makes the window server fade every
    /// screen to black and back — a visible flicker right as a session starts.
    /// Holding the reservation (and not fading) blocks that automatic fade, so
    /// the virtual display attaches without disturbing the physical screens.
    static func suppressingReconfigurationFade<T>(_ body: () async -> T) async -> T {
        var token = CGDisplayFadeReservationToken()
        // 15s is the documented maximum reservation interval; the reservation is
        // released as soon as the display settles, well before then.
        guard CGAcquireDisplayFadeReservation(15, &token) == .success else {
            return await body()
        }
        defer { CGReleaseDisplayFadeReservation(token) }
        // Pin brightness to normal; the held reservation is what suppresses the fade.
        CGDisplayFade(
            token, 0,
            CGDisplayBlendFraction(kCGDisplayBlendNormal),
            CGDisplayBlendFraction(kCGDisplayBlendNormal),
            0, 0, 0, boolean_t(0)
        )
        return await body()
    }

    // MARK: - Cursor containment

    /// Parks the virtual display diagonally off the bottom-right corner of the
    /// physical displays. macOS forces displays to stay adjacent, but a
    /// corner-only touch has no shared edge, so the cursor can barely travel
    /// onto the (invisible) display.
    private func moveToCornerAdjacentPosition() {
        // A mirrored display has no position of its own to park.
        guard displayID != 0, !isMirrored else { return }
        var physicalBounds = CGRect.null
        for id in Self.onlineDisplayIDs() where id != displayID {
            physicalBounds = physicalBounds.union(CGDisplayBounds(id))
        }
        guard !physicalBounds.isNull else { return }
        let target = CGPoint(x: physicalBounds.maxX.rounded(), y: physicalBounds.maxY.rounded())
        // Already parked — don't kick off a redundant reconfiguration (which
        // would also re-fire the screen-parameters notification).
        guard CGDisplayBounds(displayID).origin != target else { return }

        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else { return }
        guard CGConfigureDisplayOrigin(config, displayID, Int32(target.x), Int32(target.y)) == .success else {
            CGCancelDisplayConfiguration(config)
            return
        }
        CGCompleteDisplayConfiguration(config, .forSession)
    }

    private static func onlineDisplayIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        guard CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }
}
