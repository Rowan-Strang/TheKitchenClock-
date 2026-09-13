import Foundation

struct PersistedLoopAlarmEntry: Codable, Equatable, Sendable {
    let id: UUID
    let cycleIndex: Int
    let fireDate: Date
}
