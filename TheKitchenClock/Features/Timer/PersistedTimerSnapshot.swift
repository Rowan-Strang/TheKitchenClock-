import Foundation

struct PersistedTimerSnapshot: Codable, Equatable {
    let selectedDurationSeconds: Int64
    let state: PersistedTimerState
}
