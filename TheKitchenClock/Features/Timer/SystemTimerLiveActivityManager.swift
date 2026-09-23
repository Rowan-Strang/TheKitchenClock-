import ActivityKit
import Foundation

@MainActor
struct SystemTimerLiveActivityManager: TimerLiveActivityManaging {
    func synchronize(_ state: TimerLiveActivityState, allowStart: Bool) async {
        let requestedSessionID: UUID?
        let contentState: TimerLiveActivityAttributes.ContentState?

        switch state {
        case .inactive:
            requestedSessionID = nil
            contentState = nil
        case let .countdown(sessionID, startDate, deadline):
            requestedSessionID = sessionID
            contentState = .init(startDate: startDate, deadline: deadline, isFinished: false)
        case let .finished(sessionID, startDate, deadline):
            requestedSessionID = sessionID
            contentState = .init(startDate: startDate, deadline: deadline, isFinished: true)
        }

        var matchingActivity: Activity<TimerLiveActivityAttributes>?

        for activity in Activity<TimerLiveActivityAttributes>.activities {
            if activity.attributes.sessionID == requestedSessionID,
               activity.activityState == .active,
               matchingActivity == nil {
                matchingActivity = activity
            } else {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }

        guard let requestedSessionID, let contentState else {
            return
        }

        let content = ActivityContent(state: contentState, staleDate: nil)

        if let matchingActivity {
            if matchingActivity.content.state != contentState {
                await matchingActivity.update(content)
            }
        } else if allowStart, ActivityAuthorizationInfo().areActivitiesEnabled {
            // A disabled or unavailable Live Activity must never prevent the alarm from running.
            _ = try? Activity.request(
                attributes: TimerLiveActivityAttributes(sessionID: requestedSessionID),
                content: content,
                pushType: nil
            )
        }
    }
}
