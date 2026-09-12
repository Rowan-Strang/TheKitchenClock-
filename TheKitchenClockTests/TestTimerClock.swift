import Foundation
@testable import TheKitchenClock

@MainActor
final class TestTimerClock: TimerClock {
    private(set) var currentDate: Date

    init(_ currentDate: Date) {
        self.currentDate = currentDate
    }

    func now() -> Date {
        currentDate
    }

    func advance(by duration: Duration) {
        currentDate = currentDate.addingTimeInterval(duration.timerTimeInterval)
    }
}
