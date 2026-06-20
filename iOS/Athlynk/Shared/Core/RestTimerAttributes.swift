import ActivityKit
import Foundation

// Shared between the main app target and the AthlynkRestTimerExtension target.
// Add this file to both targets in Xcode (File Inspector → Target Membership).
struct RestTimerAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var endDate: Date
        var exerciseName: String
    }
}
