import Foundation

enum TimerState: Equatable {
    case ready
    case running(deadline: Date)
    case paused(remaining: Duration)
    case finished

    var title: String {
        switch self {
        case .ready:
            "Ready"
        case .running:
            "Running"
        case .paused:
            "Paused"
        case .finished:
            "Finished"
        }
    }

    var isRunning: Bool {
        if case .running = self {
            true
        } else {
            false
        }
    }

    var isPaused: Bool {
        if case .paused = self {
            true
        } else {
            false
        }
    }
}
