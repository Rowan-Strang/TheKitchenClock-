import Foundation

enum TimerLiveActivityState: Equatable, Sendable {
    case inactive
    case countdown(sessionID: UUID, startDate: Date, deadline: Date)
    case finished(sessionID: UUID, startDate: Date, deadline: Date)
}
