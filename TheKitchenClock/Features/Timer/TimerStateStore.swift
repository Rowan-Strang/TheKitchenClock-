import Foundation

@MainActor
protocol TimerStateStore {
    func load() -> PersistedTimerSnapshot?
    func save(_ snapshot: PersistedTimerSnapshot)
}
