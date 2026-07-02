import Foundation

enum UltraWinError: LocalizedError {
    case screenRecordingDenied
    case physicalDisplayNotFound
    case virtualDisplayFailed

    var errorDescription: String? {
        switch self {
        case .screenRecordingDenied:
            return "UltraWin needs Screen Recording permission. Grant it in System Settings → Privacy & Security → Screen Recording, then relaunch UltraWin."
        case .physicalDisplayNotFound:
            return "Could not find the selected display in the list of shareable displays."
        case .virtualDisplayFailed:
            return "The virtual display could not be created. This can happen if macOS changed the private CGVirtualDisplay API."
        }
    }
}
