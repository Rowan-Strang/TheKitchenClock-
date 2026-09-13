import Foundation

struct PersistedLoopAlarmSession: Codable, Equatable, Sendable {
    let id: UUID
    let anchorDeadline: Date
    let durationSeconds: Int64
    var nextCycleIndex: Int
    var lastAcknowledgedCycleIndex: Int
    var entries: [PersistedLoopAlarmEntry]

    func fireDate(for cycleIndex: Int) -> Date {
        anchorDeadline.addingTimeInterval(Double(cycleIndex - 1) * Double(durationSeconds))
    }
}
