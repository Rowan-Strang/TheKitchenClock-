import Foundation

enum TimerAlarmIssue: String, Identifiable {
    case authorizationDenied
    case schedulingFailed
    case limitedRepeatCoverage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .authorizationDenied:
            "Alarms Not Allowed"
        case .schedulingFailed:
            "Alarm Not Scheduled"
        case .limitedRepeatCoverage:
            "Limited Alarm Coverage"
        }
    }

    var message: String {
        switch self {
        case .authorizationDenied:
            "Allow alarms for The Kitchen Clock in Settings before starting this timer."
        case .schedulingFailed:
            "The alarm couldn’t be scheduled, so the timer hasn’t started. Please try again."
        case .limitedRepeatCoverage:
            "The repeating timer started, but fewer than four future alarms could be scheduled. The app will keep trying to refill the queue."
        }
    }
}
