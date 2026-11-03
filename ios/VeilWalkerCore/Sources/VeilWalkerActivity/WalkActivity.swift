#if os(iOS)
import ActivityKit
import Foundation

/// The live walk on the lock screen and in the Dynamic Island: iOS's stand-in for Android's ongoing walk
/// notification. Shared by the app (which starts and updates it) and the LiveWalk widget extension (which draws it).
/// Holds nothing private: a step count, a phase and the tier, never a location.
public struct WalkActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public enum Phase: String, Codable, Hashable, Sendable {
            case walking, paused, redLight
        }

        /// Tier of the latest window, as the user sees it: "onion", "gps" or "sensor".
        public var tier: String
        public var steps: Int64
        public var phase: Phase
        /// When the stillness began (paused / red light), so the card can count down to the 4.5 min end.
        public var stillSince: Date?

        public init(tier: String, steps: Int64, phase: Phase, stillSince: Date? = nil) {
            self.tier = tier
            self.steps = steps
            self.phase = phase
            self.stillSince = stillSince
        }
    }

    /// "ONION" or "ACTIVE", as WalkMode.
    public var mode: String
    public var startedAt: Date

    public init(mode: String, startedAt: Date) {
        self.mode = mode
        self.startedAt = startedAt
    }
}
#endif
