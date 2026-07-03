import ActivityKit
import Foundation

// Used by RestTimerManager (Athlynk target) to start/update the Live Activity.
// AthlynkRestTimerExtension/RestTimerLiveActivity.swift defines the custom
// lock-screen/Dynamic Island UI for it, but that widget extension target
// isn't currently part of the Xcode project — until it's added, the system
// falls back to its default minimal Live Activity presentation.
struct RestTimerAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var endDate: Date
        var exerciseName: String
    }
}
