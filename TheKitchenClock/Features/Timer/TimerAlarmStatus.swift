import Foundation

struct TimerAlarmStatus: Equatable, Sendable {
    let activeIDs: Set<UUID>
    let alertingIDs: Set<UUID>
}
