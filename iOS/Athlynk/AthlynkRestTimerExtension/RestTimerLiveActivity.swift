import ActivityKit
import WidgetKit
import SwiftUI

@main
struct AthlynkRestTimerExtensionBundle: WidgetBundle {
    var body: some Widget {
        RestTimerLiveActivity()
    }
}

struct RestTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestTimerAttributes.self) { context in
            LockScreenLiveActivityView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        Image(systemName: "timer")
                            .foregroundStyle(.teal)
                            .font(.title3.bold())
                        VStack(alignment: .leading, spacing: 2) {
                            Text("RECUPERO")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .tracking(1.5)
                                .foregroundStyle(.secondary)
                            Text(context.state.exerciseName)
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: Date.now...context.state.endDate, countsDown: true)
                        .monospacedDigit()
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .foregroundStyle(.teal)
                        .frame(minWidth: 64, alignment: .trailing)
                        .padding(.trailing, 6)
                }
            } compactLeading: {
                Image(systemName: "timer")
                    .foregroundStyle(.teal)
                    .font(.callout.bold())
            } compactTrailing: {
                Text(timerInterval: Date.now...context.state.endDate, countsDown: true)
                    .monospacedDigit()
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(.teal)
                    .frame(width: 44)
            } minimal: {
                Image(systemName: "timer")
                    .foregroundStyle(.teal)
            }
        }
    }
}

private struct LockScreenLiveActivityView: View {
    let context: ActivityViewContext<RestTimerAttributes>

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "timer")
                .font(.title.bold())
                .foregroundStyle(.teal)

            VStack(alignment: .leading, spacing: 3) {
                Text("RECUPERO")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(.secondary)
                Text(context.state.exerciseName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }

            Spacer()

            Text(timerInterval: Date.now...context.state.endDate, countsDown: true)
                .monospacedDigit()
                .font(.system(size: 38, weight: .bold, design: .monospaced))
                .foregroundStyle(.teal)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .activityBackgroundTint(Color.black.opacity(0.78))
        .activitySystemActionForegroundColor(.white)
    }
}
