import Foundation

enum TimerState: Equatable {
    case ready
    case running(deadline: Date)
    case finished

    var isRunning: Bool {
        if case .running = self {
            true
        } else {
            false
        }
    }

}
