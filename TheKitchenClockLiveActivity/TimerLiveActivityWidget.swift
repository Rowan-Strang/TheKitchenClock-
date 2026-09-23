import ActivityKit
import SwiftUI
import WidgetKit

struct TimerLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimerLiveActivityAttributes.self) { context in
            TimerLiveActivityCountdown(state: context.state, font: .title)
                .frame(maxWidth: .infinity)
                .padding()
                .activityBackgroundTint(.black.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    TimerLiveActivityCountdown(state: context.state, font: .title)
                        .frame(maxWidth: .infinity)
                }
            } compactLeading: {
                Image(systemName: "timer")
                    .foregroundStyle(.white)
                    .accessibilityHidden(true)
            } compactTrailing: {
                TimerLiveActivityCountdown(state: context.state, font: .caption)
            } minimal: {
                TimerLiveActivityCountdown(state: context.state, font: .caption2)
            }
        }
    }
}
