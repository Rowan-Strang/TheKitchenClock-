import Foundation

@MainActor
enum LoopAlarmQueueCoordinator {
    static let targetAlarmCount = 4

    static func replenish(
        session: inout PersistedLoopAlarmSession,
        now: Date,
        scheduler: any TimerAlarmScheduling,
        isSessionValid: () -> Bool = { true }
    ) async -> LoopAlarmQueueReplenishmentResult {
        var hasFailure = false
        var createdAlarmIDs: Set<UUID> = []

        while session.entries.count < targetAlarmCount {
            guard isSessionValid() else {
                invalidate(
                    session: &session,
                    createdAlarmIDs: createdAlarmIDs,
                    scheduler: scheduler
                )
                return .invalidated
            }

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

                guard isSessionValid() else {
                    createdAlarmIDs.insert(alarmID)
                    invalidate(
                        session: &session,
                        createdAlarmIDs: createdAlarmIDs,
                        scheduler: scheduler
                    )
                    return .invalidated
                }

                createdAlarmIDs.insert(alarmID)
                session.entries.append(
                    PersistedLoopAlarmEntry(id: alarmID, cycleIndex: cycleIndex, fireDate: fireDate)
                )
                session.entries.sort { $0.cycleIndex < $1.cycleIndex }
                session.nextCycleIndex = cycleIndex + 1
            } catch {
                guard isSessionValid() else {
                    createdAlarmIDs.insert(alarmID)
                    invalidate(
                        session: &session,
                        createdAlarmIDs: createdAlarmIDs,
                        scheduler: scheduler
                    )
                    return .invalidated
                }

                hasFailure = true
                break
            }
        }

        return .completed(hasFailure: hasFailure)
    }

    static func handleSystemDismissal(
        alarmID: UUID,
        sessionID: UUID,
        cycleIndex: Int,
        now: Date = .now,
        scheduler: any TimerAlarmScheduling = SystemTimerAlarmScheduler(),
        store: any TimerStateStore = UserDefaultsTimerStateStore(),
        liveActivityManager: any TimerLiveActivityManaging = SystemTimerLiveActivityManager()
    ) async {
        guard let originalSnapshot = store.load(),
              originalSnapshot.isRepeatEnabled,
              let originalSession = originalSnapshot.loopAlarmSession,
              var session = originalSnapshot.loopAlarmSession,
              session.id == sessionID,
              session.entries.contains(where: { $0.id == alarmID && $0.cycleIndex == cycleIndex }) else {
            return
        }

        session.entries.removeAll { $0.id == alarmID }
        session.lastAcknowledgedCycleIndex = max(session.lastAcknowledgedCycleIndex, cycleIndex)
        let isSessionValid = {
            guard let latestSnapshot = store.load() else {
                return false
            }

            return latestSnapshot.isRepeatEnabled
                && latestSnapshot.loopAlarmSession == originalSession
        }
        let replenishmentResult = await replenish(
            session: &session,
            now: now,
            scheduler: scheduler,
            isSessionValid: isSessionValid
        )

        guard case .completed = replenishmentResult,
              isSessionValid(),
              let latestSnapshot = store.load() else {
            return
        }

        store.save(
            latestSnapshot.replacingAlarmState(
                oneShotAlarmID: nil,
                loopAlarmSession: session,
                isAwaitingRepeatCycleAcknowledgement: false
            )
        )

        let nextCycleIndex = max(
            cycleIndex + 1,
            Int(floor(now.timeIntervalSince(session.anchorDeadline) / Double(session.durationSeconds))) + 2
        )
        let deadline = session.fireDate(for: nextCycleIndex)
        await liveActivityManager.synchronize(
            .countdown(
                sessionID: session.id,
                startDate: deadline.addingTimeInterval(-Double(session.durationSeconds)),
                deadline: deadline
            ),
            allowStart: false
        )

        if let latestSnapshot = store.load(),
           latestSnapshot.state == .ready,
           latestSnapshot.oneShotAlarmID == nil,
           latestSnapshot.loopAlarmSession == nil {
            await liveActivityManager.synchronize(.inactive, allowStart: false)
        }
    }

    private static func invalidate(
        session: inout PersistedLoopAlarmSession,
        createdAlarmIDs: Set<UUID>,
        scheduler: any TimerAlarmScheduling
    ) {
        scheduler.tearDown(ids: createdAlarmIDs)
        session.entries.removeAll { createdAlarmIDs.contains($0.id) }
    }
}
