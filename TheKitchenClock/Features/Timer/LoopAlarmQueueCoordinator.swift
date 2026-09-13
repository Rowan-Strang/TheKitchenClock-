import Foundation

@MainActor
enum LoopAlarmQueueCoordinator {
    static let targetAlarmCount = 4

    static func replenish(
        session: inout PersistedLoopAlarmSession,
        now: Date,
        scheduler: any TimerAlarmScheduling
    ) async -> Bool {
        var hasFailure = false

        while session.entries.count < targetAlarmCount {
            var cycleIndex = session.nextCycleIndex
            var fireDate = session.fireDate(for: cycleIndex)

            while fireDate <= now {
                cycleIndex += 1
                fireDate = session.fireDate(for: cycleIndex)
            }

            let alarmID = UUID()

            do {
                try await scheduler.schedule(
                    id: alarmID,
                    deadline: fireDate,
                    loopContext: TimerAlarmLoopContext(sessionID: session.id, cycleIndex: cycleIndex)
                )
                session.entries.append(
                    PersistedLoopAlarmEntry(id: alarmID, cycleIndex: cycleIndex, fireDate: fireDate)
                )
                session.entries.sort { $0.cycleIndex < $1.cycleIndex }
                session.nextCycleIndex = cycleIndex + 1
            } catch {
                hasFailure = true
                break
            }
        }

        return hasFailure
    }

    static func handleSystemDismissal(
        alarmID: UUID,
        sessionID: UUID,
        cycleIndex: Int,
        now: Date = .now,
        scheduler: any TimerAlarmScheduling = SystemTimerAlarmScheduler(),
        store: any TimerStateStore = UserDefaultsTimerStateStore()
    ) async {
        guard let snapshot = store.load(),
              snapshot.isRepeatEnabled,
              var session = snapshot.loopAlarmSession,
              session.id == sessionID,
              session.entries.contains(where: { $0.id == alarmID && $0.cycleIndex == cycleIndex }) else {
            return
        }

        session.entries.removeAll { $0.id == alarmID }
        session.lastAcknowledgedCycleIndex = max(session.lastAcknowledgedCycleIndex, cycleIndex)
        _ = await replenish(session: &session, now: now, scheduler: scheduler)

        store.save(
            snapshot.replacingAlarmState(
                oneShotAlarmID: nil,
                loopAlarmSession: session,
                isAwaitingRepeatCycleAcknowledgement: false
            )
        )
    }
}
