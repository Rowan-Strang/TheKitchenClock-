import Foundation

struct TimerAlarmLoopContext: Equatable, Sendable {
    let sessionID: UUID
    let cycleIndex: Int
}
