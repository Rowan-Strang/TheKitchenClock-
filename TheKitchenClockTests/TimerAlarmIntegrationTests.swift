import Foundation
import Testing
@testable import TheKitchenClock

@MainActor
struct TimerAlarmIntegrationTests {
    @Test func oneShotTimerSchedulesItsExactDeadline() async throws {
        let clock = TestTimerClock(Date(timeIntervalSinceReferenceDate: 100))
        let scheduler = TestTimerAlarmScheduler()
        let store = InMemoryTimerStateStore()
        let viewModel = TimerViewModel(
            selectedDuration: .seconds(30),
            clock: clock,
            timerStateStore: store,
            alarmScheduler: scheduler,
            liveActivityManager: TestTimerLiveActivityManager()
        )

        await viewModel.start()

        let alarm = try #require(scheduler.scheduledAlarms.values.first)
        #expect(alarm.deadline == Date(timeIntervalSinceReferenceDate: 130))
        #expect(alarm.loopContext == nil)
        #expect(viewModel.state == .running(deadline: alarm.deadline))
        #expect(store.snapshot?.oneShotAlarmID == alarm.id)
    }

    @Test func deniedAuthorizationLeavesOneShotTimerReady() async {
        let scheduler = TestTimerAlarmScheduler()
        scheduler.authorization = .denied
        let viewModel = TimerViewModel(
            timerStateStore: InMemoryTimerStateStore(),
            alarmScheduler: scheduler,
            liveActivityManager: TestTimerLiveActivityManager()
        )

        await viewModel.start()

        #expect(viewModel.state == .ready)
        #expect(viewModel.alarmIssue == .authorizationDenied)
        #expect(scheduler.scheduledAlarms.isEmpty)
    }

    @Test func schedulingFailureLeavesOneShotTimerReady() async {
        let scheduler = TestTimerAlarmScheduler()
        scheduler.failingScheduleAttempts = [1]
        let viewModel = TimerViewModel(
            timerStateStore: InMemoryTimerStateStore(),
            alarmScheduler: scheduler,
            liveActivityManager: TestTimerLiveActivityManager()
        )

        await viewModel.start()

        #expect(viewModel.state == .ready)
        #expect(viewModel.alarmIssue == .schedulingFailed)
    }

    @Test func repeatingTimerSchedulesFourCadenceAlarms() async throws {
        let clock = TestTimerClock(Date(timeIntervalSinceReferenceDate: 0))
        let scheduler = TestTimerAlarmScheduler()
        let store = InMemoryTimerStateStore()
        let viewModel = TimerViewModel(
            selectedDuration: .seconds(30),
            clock: clock,
            timerStateStore: store,
            alarmScheduler: scheduler,
            liveActivityManager: TestTimerLiveActivityManager()
        )

        await viewModel.toggleRepeat()
        await viewModel.start()

        let session = try #require(store.snapshot?.loopAlarmSession)
        #expect(session.entries.map(\.cycleIndex) == [1, 2, 3, 4])
        #expect(session.entries.map(\.fireDate) == [
            Date(timeIntervalSinceReferenceDate: 30),
            Date(timeIntervalSinceReferenceDate: 60),
            Date(timeIntervalSinceReferenceDate: 90),
            Date(timeIntervalSinceReferenceDate: 120)
        ])
        #expect(Set(session.entries.map(\.id)).count == 4)
        #expect(scheduler.scheduledAlarms.values.allSatisfy { $0.loopContext?.sessionID == session.id })
    }

    @Test func repeatingTimerStartsWithPartialQueueAfterLaterFailure() async throws {
        let scheduler = TestTimerAlarmScheduler()
        scheduler.failingScheduleAttempts = [3]
        let store = InMemoryTimerStateStore()
        let viewModel = TimerViewModel(
            timerStateStore: store,
            alarmScheduler: scheduler,
            liveActivityManager: TestTimerLiveActivityManager()
        )

        await viewModel.toggleRepeat()
        await viewModel.start()

        #expect(viewModel.isRunning)
        #expect(viewModel.alarmIssue == .limitedRepeatCoverage)
        #expect(try #require(store.snapshot?.loopAlarmSession).entries.count == 2)
    }

    @Test func inAppAcknowledgementClearsAllDueAlarmsAndRefillsOnCadence() async throws {
        let clock = TestTimerClock(Date(timeIntervalSinceReferenceDate: 0))
        let scheduler = TestTimerAlarmScheduler()
        let store = InMemoryTimerStateStore()
        let viewModel = TimerViewModel(
            selectedDuration: .seconds(30),
            clock: clock,
            timerStateStore: store,
            alarmScheduler: scheduler,
            liveActivityManager: TestTimerLiveActivityManager()
        )

        await viewModel.applicationDidBecomeActive()
        await viewModel.toggleRepeat()
        await viewModel.start()
        let originalSession = try #require(store.snapshot?.loopAlarmSession)
        clock.advance(by: .seconds(65))
        await viewModel.refresh()

        await viewModel.acknowledgeCompletion()

        let updatedSession = try #require(store.snapshot?.loopAlarmSession)
        #expect(Set(scheduler.stoppedAlarmIDs) == Set(originalSession.entries.prefix(2).map(\.id)))
        #expect(updatedSession.lastAcknowledgedCycleIndex == 2)
        #expect(updatedSession.entries.map(\.cycleIndex) == [3, 4, 5, 6])
        #expect(updatedSession.entries.map(\.fireDate).allSatisfy { $0 > clock.now() })
        #expect(!viewModel.isAwaitingRepeatCycleAcknowledgement)
    }

    @Test func turningRepeatOffKeepsOnlyTheCurrentCycleAlarm() async throws {
        let scheduler = TestTimerAlarmScheduler()
        let store = InMemoryTimerStateStore()
        let viewModel = TimerViewModel(
            timerStateStore: store,
            alarmScheduler: scheduler,
            liveActivityManager: TestTimerLiveActivityManager()
        )

        await viewModel.toggleRepeat()
        await viewModel.start()
        let session = try #require(store.snapshot?.loopAlarmSession)

        await viewModel.toggleRepeat()

        #expect(!viewModel.isRepeatEnabled)
        #expect(store.snapshot?.loopAlarmSession == nil)
        #expect(store.snapshot?.oneShotAlarmID == session.entries.first?.id)
        #expect(Set(scheduler.cancelledAlarmIDs) == Set(session.entries.dropFirst().map(\.id)))
    }

    @Test func systemDismissalRefillsAValidLoopSession() async throws {
        let scheduler = TestTimerAlarmScheduler()
        let store = InMemoryTimerStateStore()
        let sessionID = UUID()
        let firstID = UUID()
        let firstEntry = PersistedLoopAlarmEntry(
            id: firstID,
            cycleIndex: 1,
            fireDate: Date(timeIntervalSinceReferenceDate: 30)
        )
        var session = PersistedLoopAlarmSession(
            id: sessionID,
            anchorDeadline: firstEntry.fireDate,
            durationSeconds: 30,
            nextCycleIndex: 2,
            lastAcknowledgedCycleIndex: 0,
            entries: [firstEntry]
        )
        _ = await LoopAlarmQueueCoordinator.replenish(
            session: &session,
            now: Date(timeIntervalSinceReferenceDate: 0),
            scheduler: scheduler
        )
        store.save(
            PersistedTimerSnapshot(
                selectedDurationSeconds: 30,
                state: .running(deadline: firstEntry.fireDate),
                isRepeatEnabled: true,
                loopAlarmSession: session
            )
        )

        await LoopAlarmQueueCoordinator.handleSystemDismissal(
            alarmID: firstID,
            sessionID: sessionID,
            cycleIndex: 1,
            now: Date(timeIntervalSinceReferenceDate: 31),
            scheduler: scheduler,
            store: store,
            liveActivityManager: TestTimerLiveActivityManager()
        )

        let updatedSession = try #require(store.snapshot?.loopAlarmSession)
        #expect(updatedSession.lastAcknowledgedCycleIndex == 1)
        #expect(!updatedSession.entries.contains(where: { $0.id == firstID }))
        #expect(updatedSession.entries.count == 4)
        #expect(updatedSession.entries.map(\.cycleIndex) == [2, 3, 4, 5])
    }

    @Test func staleSystemDismissalCannotReviveDisabledLoop() async {
        let scheduler = TestTimerAlarmScheduler()
        let store = InMemoryTimerStateStore(
            snapshot: PersistedTimerSnapshot(
                selectedDurationSeconds: 30,
                state: .running(deadline: Date(timeIntervalSinceReferenceDate: 30)),
                isRepeatEnabled: false
            )
        )

        await LoopAlarmQueueCoordinator.handleSystemDismissal(
            alarmID: UUID(),
            sessionID: UUID(),
            cycleIndex: 1,
            now: Date(timeIntervalSinceReferenceDate: 31),
            scheduler: scheduler,
            store: store,
            liveActivityManager: TestTimerLiveActivityManager()
        )

        #expect(scheduler.scheduledAlarms.isEmpty)
        #expect(store.snapshot?.loopAlarmSession == nil)
    }
}
