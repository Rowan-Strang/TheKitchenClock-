import Foundation
@testable import TheKitchenClock

@MainActor
final class TestTimerLiveActivityManager: TimerLiveActivityManaging {
    private(set) var currentState: TimerLiveActivityState = .inactive
    private(set) var updates: [TimerLiveActivityState] = []
    var canStart = true

    func synchronize(_ state: TimerLiveActivityState, allowStart: Bool) async {
        if state == .inactive {
            currentState = .inactive
        } else if currentState != .inactive || (allowStart && canStart) {
            currentState = state
        }

        updates.append(currentState)
    }
}
