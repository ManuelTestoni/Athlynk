import ActivityKit
import SwiftUI

@MainActor
final class RestTimerManager: ObservableObject {
    static let shared = RestTimerManager()
    private init() {}

    @Published var secondsLeft: Int = 0
    @Published var totalSeconds: Int = 0
    @Published var isRunning = false
    @Published var exerciseName: String = ""

    private var timerTask: Task<Void, Never>?
    private var liveActivity: Activity<RestTimerAttributes>?

    func start(seconds: Int, exerciseName: String) {
        timerTask?.cancel()
        timerTask = nil
        Task { await endLiveActivity() }

        self.exerciseName = exerciseName
        self.totalSeconds = seconds
        self.secondsLeft = seconds
        self.isRunning = true

        startLiveActivity(seconds: seconds, exerciseName: exerciseName)

        timerTask = Task {
            for remaining in stride(from: seconds - 1, through: 0, by: -1) {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                self.secondsLeft = remaining
            }
            self.isRunning = false
            Haptics.soft()
            await self.endLiveActivity()
        }
    }

    func cancel() {
        timerTask?.cancel()
        timerTask = nil
        isRunning = false
        secondsLeft = 0
        Task { await endLiveActivity() }
    }

    private func startLiveActivity(seconds: Int, exerciseName: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = RestTimerAttributes.ContentState(
            endDate: Date().addingTimeInterval(Double(seconds)),
            exerciseName: exerciseName
        )
        liveActivity = try? Activity.request(
            attributes: RestTimerAttributes(),
            content: .init(state: state, staleDate: nil),
            pushType: nil
        )
    }

    private func endLiveActivity() async {
        guard let activity = liveActivity else { return }
        liveActivity = nil
        let state = RestTimerAttributes.ContentState(endDate: .now, exerciseName: exerciseName)
        await activity.end(.init(state: state, staleDate: nil), dismissalPolicy: .immediate)
    }
}
