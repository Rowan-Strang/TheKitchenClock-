import Foundation
@testable import TheKitchenClock

@MainActor
final class InMemoryTimerStateStore: TimerStateStore {
    private(set) var snapshot: PersistedTimerSnapshot?

    init(snapshot: PersistedTimerSnapshot? = nil) {
        self.snapshot = snapshot
    }

    func load() -> PersistedTimerSnapshot? {
        snapshot
    }

    func save(_ snapshot: PersistedTimerSnapshot) {
        self.snapshot = snapshot
    }
}
