import Foundation

struct SystemTimerClock: TimerClock {
    func now() -> Date {
        .now
    }
}
