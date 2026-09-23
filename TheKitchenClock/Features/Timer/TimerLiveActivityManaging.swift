import Foundation

@MainActor
protocol TimerLiveActivityManaging {
    func synchronize(_ state: TimerLiveActivityState, allowStart: Bool) async
}
