import AppKit

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    static func screen(withDisplayID id: CGDirectDisplayID) -> NSScreen? {
        screens.first { $0.displayID == id }
    }

    /// Polls until the screen for `displayID` appears (and optionally reaches
    /// `pointSize`), since display reconfiguration is asynchronous.
    @MainActor
    static func waitForScreen(
        displayID: CGDirectDisplayID,
        pointSize: CGSize? = nil,
        timeout: TimeInterval = 5
    ) async -> NSScreen? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let screen = screen(withDisplayID: displayID),
               pointSize == nil || screen.frame.size == pointSize {
                return screen
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return screen(withDisplayID: displayID)
    }
}
