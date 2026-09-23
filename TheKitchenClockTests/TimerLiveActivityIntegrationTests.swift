import Foundation
import Testing
@testable import TheKitchenClock

@MainActor
struct TimerLiveActivityIntegrationTests {
    @Test func oneShotActivityCountsDownThenEndsOnAcknowledgement() async throws {
        let clock = TestTimerClock(Date(timeIntervalSinceReferenceDate: 0))
        let scheduler = TestTimerAlarmScheduler()
        let activity = TestTimerLiveActivityManager()
        let viewModel = TimerViewModel(
            selectedDuration: .seconds(30),
            clock: clock,
            timerStateStore: InMemoryTimerStateStore(),
            alarmScheduler: scheduler,
            liveActivityManager: activity
        )

        await viewModel.start()
        let alarmID = try #require(scheduler.scheduledAlarms.keys.first)
        #expect(activity.currentState == .countdown(
            sessionID: alarmID,
            startDate: Date(timeIntervalSinceReferenceDate: 0),
            deadline: Date(timeIntervalSinceReferenceDate: 30)
        ))

        clock.advance(by: .seconds(30))
        await viewModel.refresh()
        #expect(activity.currentState == .finished(
            sessionID: alarmID,
            startDate: Date(timeIntervalSinceReferenceDate: 0),
            deadline: Date(timeIntervalSinceReferenceDate: 30)
        ))

        await viewModel.acknowledgeCompletion()
        #expect(activity.currentState == .inactive)
    }

    @Test func activityUnavailabilityDoesNotBlockAnAlarm() async {
        let scheduler = TestTimerAlarmScheduler()
        let activity = TestTimerLiveActivityManager()
        activity.canStart = false
        let viewModel = TimerViewModel(
            timerStateStore: InMemoryTimerStateStore(),
            alarmScheduler: scheduler,
            liveActivityManager: activity
        )

        await viewModel.start()

        #expect(viewModel.isRunning)
        #expect(scheduler.scheduledAlarms.count == 1)
        #expect(activity.currentState == .inactive)
    }

    @Test func schedulingFailureNeverStartsAnActivity() async {
        let scheduler = TestTimerAlarmScheduler()
        scheduler.failingScheduleAttempts = [1]
        let activity = TestTimerLiveActivityManager()
        let viewModel = TimerViewModel(
            timerStateStore: InMemoryTimerStateStore(),
            alarmScheduler: scheduler,
            liveActivityManager: activity
        )

        await viewModel.start()

        #expect(viewModel.state == .ready)
        #expect(activity.updates.isEmpty)
    }

    @Test func resetEndsTheActivity() async {
        let activity = TestTimerLiveActivityManager()
        let viewModel = TimerViewModel(
            timerStateStore: InMemoryTimerStateStore(),
            alarmScheduler: TestTimerAlarmScheduler(),
            liveActivityManager: activity
        )

        await viewModel.start()
        await viewModel.reset()

        #expect(activity.currentState == .inactive)
    }

    @Test func alertingRepeatAlarmAdvancesTheSameActivityBeforeDismissal() async throws {
        let clock = TestTimerClock(Date(timeIntervalSinceReferenceDate: 0))
        let scheduler = TestTimerAlarmScheduler()
        let store = InMemoryTimerStateStore()
        let activity = TestTimerLiveActivityManager()
        let viewModel = TimerViewModel(
            selectedDuration: .seconds(30),
            clock: clock,
            timerStateStore: store,
            alarmScheduler: scheduler,
            liveActivityManager: activity
        )

        await viewModel.applicationDidBecomeActive()
        await viewModel.enableRepeatAndStart()
        let session = try #require(store.snapshot?.loopAlarmSession)
        let firstID = try #require(session.entries.first?.id)

        clock.advance(by: .seconds(30))
        scheduler.fire(id: firstID)
        await viewModel.applicationDidBecomeActive()

        let nextCycle = TimerLiveActivityState.countdown(
            sessionID: session.id,
            startDate: Date(timeIntervalSinceReferenceDate: 30),
            deadline: Date(timeIntervalSinceReferenceDate: 60)
        )
        #expect(activity.currentState == nextCycle)
        #expect(viewModel.isAwaitingRepeatCycleAcknowledgement)

        await viewModel.acknowledgeCompletion()
        #expect(activity.currentState == nextCycle)
    }

    @Test func missedRepeatCyclesCatchUpOnAppReturn() async throws {
        let clock = TestTimerClock(Date(timeIntervalSinceReferenceDate: 0))
        let scheduler = TestTimerAlarmScheduler()
        let store = InMemoryTimerStateStore()
        let activity = TestTimerLiveActivityManager()
        let firstViewModel = TimerViewModel(
            selectedDuration: .seconds(30),
            clock: clock,
            timerStateStore: store,
            alarmScheduler: scheduler,
            liveActivityManager: activity
        )

        await firstViewModel.applicationDidBecomeActive()
        await firstViewModel.enableRepeatAndStart()
        let sessionID = try #require(store.snapshot?.loopAlarmSession?.id)
        firstViewModel.applicationDidBecomeInactive()
        clock.advance(by: .seconds(95))

        let restoredViewModel = TimerViewModel(
            clock: clock,
            timerStateStore: store,
            alarmScheduler: scheduler,
            liveActivityManager: activity
        )
        await restoredViewModel.applicationDidBecomeActive()

        #expect(activity.currentState == .countdown(
            sessionID: sessionID,
            startDate: Date(timeIntervalSinceReferenceDate: 90),
            deadline: Date(timeIntervalSinceReferenceDate: 120)
        ))
    }

    @Test func changingRepeatModeKeepsTheActivityOnTheScheduledDeadline() async throws {
        let clock = TestTimerClock(Date(timeIntervalSinceReferenceDate: 0))
        let scheduler = TestTimerAlarmScheduler()
        let store = InMemoryTimerStateStore()
        let activity = TestTimerLiveActivityManager()
        let viewModel = TimerViewModel(
            selectedDuration: .seconds(30),
            clock: clock,
            timerStateStore: store,
            alarmScheduler: scheduler,
            liveActivityManager: activity
        )

        await viewModel.start()
        await viewModel.toggleRepeat()
        let sessionID = try #require(store.snapshot?.loopAlarmSession?.id)
        #expect(activity.currentState == .countdown(
            sessionID: sessionID,
            startDate: Date(timeIntervalSinceReferenceDate: 0),
            deadline: Date(timeIntervalSinceReferenceDate: 30)
        ))

        await viewModel.toggleRepeat()
        let keptAlarmID = try #require(store.snapshot?.oneShotAlarmID)
        #expect(activity.currentState == .countdown(
            sessionID: keptAlarmID,
            startDate: Date(timeIntervalSinceReferenceDate: 0),
            deadline: Date(timeIntervalSinceReferenceDate: 30)
        ))
    }

    @Test func stoppingARepeatingTimerEndsTheActivity() async {
        let clock = TestTimerClock(Date(timeIntervalSinceReferenceDate: 0))
        let activity = TestTimerLiveActivityManager()
        let viewModel = TimerViewModel(
            selectedDuration: .seconds(30),
            clock: clock,
            timerStateStore: InMemoryTimerStateStore(),
            alarmScheduler: TestTimerAlarmScheduler(),
            liveActivityManager: activity
        )

        await viewModel.applicationDidBecomeActive()
        await viewModel.enableRepeatAndStart()
        clock.advance(by: .seconds(30))
        await viewModel.refresh()
        await viewModel.cancelAlarm()

        #expect(activity.currentState == .inactive)
    }

    @Test func systemDismissalEndsOnlyTheMatchingOneShotActivity() async throws {
        let scheduler = TestTimerAlarmScheduler()
        let store = InMemoryTimerStateStore()
        let activity = TestTimerLiveActivityManager()
        let viewModel = TimerViewModel(
            timerStateStore: store,
            alarmScheduler: scheduler,
            liveActivityManager: activity
        )

        await viewModel.start()
        let alarmID = try #require(store.snapshot?.oneShotAlarmID)
        await OneShotAlarmCoordinator.handleSystemDismissal(
            alarmID: UUID(),
            store: store,
            liveActivityManager: activity
        )
        #expect(activity.currentState != .inactive)

        try scheduler.stop(id: alarmID)
        await OneShotAlarmCoordinator.handleSystemDismissal(
            alarmID: alarmID,
            store: store,
            liveActivityManager: activity
        )
        #expect(activity.currentState == .inactive)
        #expect(store.snapshot?.state == .ready)

        await viewModel.applicationDidBecomeActive()
        #expect(viewModel.state == .ready)
        #expect(activity.currentState == .inactive)
    }

    @Test func systemDismissalOfRepeatAlarmShowsTheNextCycle() async throws {
        let clock = TestTimerClock(Date(timeIntervalSinceReferenceDate: 0))
        let scheduler = TestTimerAlarmScheduler()
        let store = InMemoryTimerStateStore()
        let activity = TestTimerLiveActivityManager()
        let viewModel = TimerViewModel(
            selectedDuration: .seconds(30),
            clock: clock,
            timerStateStore: store,
            alarmScheduler: scheduler,
            liveActivityManager: activity
        )

        await viewModel.enableRepeatAndStart()
        let session = try #require(store.snapshot?.loopAlarmSession)
        let firstID = try #require(session.entries.first?.id)
        clock.advance(by: .seconds(31))

        await LoopAlarmQueueCoordinator.handleSystemDismissal(
            alarmID: firstID,
            sessionID: session.id,
            cycleIndex: 1,
            now: clock.now(),
            scheduler: scheduler,
            store: store,
            liveActivityManager: activity
        )

        #expect(activity.currentState == .countdown(
            sessionID: session.id,
            startDate: Date(timeIntervalSinceReferenceDate: 30),
            deadline: Date(timeIntervalSinceReferenceDate: 60)
        ))
    }
}
