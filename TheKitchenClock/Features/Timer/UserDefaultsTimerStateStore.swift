import Foundation

@MainActor
struct UserDefaultsTimerStateStore: TimerStateStore {
    static let storageKey = "com.rowan.TheKitchenClock.timerSnapshot"

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func load() -> PersistedTimerSnapshot? {
        guard let data = userDefaults.data(forKey: Self.storageKey) else {
            return nil
        }

        guard let snapshot = try? JSONDecoder().decode(PersistedTimerSnapshot.self, from: data) else {
            userDefaults.removeObject(forKey: Self.storageKey)
            return nil
        }

        return snapshot
    }

    func save(_ snapshot: PersistedTimerSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else {
            return
        }

        userDefaults.set(data, forKey: Self.storageKey)
    }
}
