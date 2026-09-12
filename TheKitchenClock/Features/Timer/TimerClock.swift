import Foundation

@MainActor
protocol TimerClock {
    func now() -> Date
}
