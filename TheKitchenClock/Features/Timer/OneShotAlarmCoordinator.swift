import Foundation

@MainActor
enum OneShotAlarmCoordinator {
    static func handleSystemDismissal(
        alarmID: UUID,
        store: any TimerStateStore = UserDefaultsTimerStateStore(),
        liveActivityManager: any TimerLiveActivityManaging = SystemTimerLiveActivityManager()
    ) async {
        guard let snapshot = store.load(), snapshot.oneShotAlarmID == alarmID else {
            return
        }

        store.save(
            PersistedTimerSnapshot(
                selectedDurationSeconds: snapshot.selectedDurationSeconds,
                state: .ready,
                presets: snapshot.presets
            )
        )
        await liveActivityManager.synchronize(.inactive, allowStart: false)
    }
}
