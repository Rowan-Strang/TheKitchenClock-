enum TimerState: Equatable {
    case ready

    var title: String {
        switch self {
        case .ready:
            "Ready"
        }
    }
}
