import Foundation
import TelemetryDeck

/// Thin wrapper over our analytics provider (TelemetryDeck) so call sites stay
/// provider-agnostic and every event name lives in one place.
///
/// Privacy: TelemetryDeck collects no personal data. It derives an anonymous,
/// salted per-install identifier, which is what lets us count *users* without
/// ever identifying anyone. Nothing about the shared screen content — pixels,
/// coordinates, window titles — is ever sent.
enum Analytics {
    /// TelemetryDeck app identifier, injected at build time from the
    /// `TELEMETRYDECK_APP_ID` xcconfig value via UltraWin/Info.plist — so the
    /// real ID lives in the gitignored Config/Analytics.local.xcconfig and
    /// never hits the public repo. When unset, analytics is a silent no-op and
    /// the app builds and runs fine. See Config/Analytics.local.xcconfig.example.
    private static let appID: String = {
        let value = Bundle.main.object(forInfoDictionaryKey: "TelemetryDeckAppID") as? String
        return value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }()

    private static var isEnabled: Bool { !appID.isEmpty }

    /// Call once at launch, before any signals are sent.
    static func start() {
        guard isEnabled else { return }
        TelemetryDeck.initialize(config: .init(appID: appID))
    }

    /// How a share was started. Lets us tell hotkey users apart from
    /// menu-bar users.
    enum ShareSource: String {
        case hotkey
        case menu
    }

    /// A sharing session went live (capture running, virtual display fed).
    /// `aspectLocked` tells us how popular the 16:9 snap is in practice.
    static func sharingStarted(source: ShareSource, aspectLocked: Bool) {
        send("sharingStarted", [
            "source": source.rawValue,
            "aspectLocked": String(aspectLocked),
        ])
    }

    /// The user stopped sharing (hotkey, menu, or capture ended).
    static func sharingStopped() {
        send("sharingStopped")
    }

    /// The user finished (or skipped out of) the first-run onboarding.
    static func onboardingCompleted() {
        send("onboardingCompleted")
    }

    private static func send(_ name: String, _ parameters: [String: String] = [:]) {
        guard isEnabled else { return }
        TelemetryDeck.signal(name, parameters: parameters)
    }
}
