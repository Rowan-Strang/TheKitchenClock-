import Foundation
import Observation

@MainActor
@Observable
final class TimerViewModel {
    static let defaultDuration: Duration = .seconds(30)

    private(set) var selectedDuration: Duration
    private(set) var state: TimerState

    init(
        selectedDuration: Duration = .seconds(30),
        state: TimerState = .ready
    ) {
        self.selectedDuration = selectedDuration
        self.state = state
    }

    var displayText: String {
        let totalSeconds = selectedDuration.components.seconds
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60

        return "\(minutes.formatted(.number.precision(.integerLength(2)))):\(seconds.formatted(.number.precision(.integerLength(2))))"
    }
}
