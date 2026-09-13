import Foundation
import Testing
@testable import TheKitchenClock

@MainActor
struct TimerViewModelTests {
    @Test func defaultTimerIsReadyForThirtySeconds() async {
        let viewModel = TimerViewModel(timerStateStore: InMemoryTimerStateStore(), alarmScheduler: TestTimerAlarmScheduler())

        #expect(viewModel.selectedDuration == .seconds(30))
        #expect(viewModel.state == .ready)
        #expect(viewModel.displayText == "00:30")
        #expect(viewModel.presets == [.defaultPreset])
    }

    @Test func configuredDurationIsClampedToSupportedRange() async {
        let viewModel = TimerViewModel(selectedDuration: .zero, timerStateStore: InMemoryTimerStateStore(), alarmScheduler: TestTimerAlarmScheduler())

        #expect(viewModel.selectedDuration == .seconds(1))

        viewModel.configure(duration: .seconds(100 * 3_600))

        #expect(viewModel.selectedDuration == .seconds(99 * 3_600 + 59 * 60 + 59))
        #expect(viewModel.displayText == "99:59:59")
    }

    @Test func runningTimerUsesItsDeadlineForTheDisplayedRemainingTime() async {
        let clock = TestTimerClock(Date(timeIntervalSinceReferenceDate: 0))
        let viewModel = TimerViewModel(
            selectedDuration: .seconds(30),
            clock: clock,
            timerStateStore: InMemoryTimerStateStore(),
            alarmScheduler: TestTimerAlarmScheduler()
        )

        await viewModel.start()
        clock.advance(by: .seconds(10))
        viewModel.refresh()

        #expect(viewModel.displayText == "00:20")
        #expect(viewModel.state == .running(deadline: Date(timeIntervalSinceReferenceDate: 30)))
    }

    @Test func resetWhileRunningReturnsToSingleTimerModeAtTheConfiguredDuration() async {
        let store = InMemoryTimerStateStore()
        let clock = TestTimerClock(Date(timeIntervalSinceReferenceDate: 0))
        let viewModel = TimerViewModel(
            selectedDuration: .seconds(30),
            clock: clock,
            timerStateStore: store,
            alarmScheduler: TestTimerAlarmScheduler()
        )

        await viewModel.toggleRepeat()
        await viewModel.start()
        clock.advance(by: .seconds(5))
        viewModel.reset()

        #expect(viewModel.state == .ready)
        #expect(viewModel.displayText == "00:30")
        #expect(!viewModel.isRepeatEnabled)
        #expect(!viewModel.isAwaitingRepeatCycleAcknowledgement)
        #expect(store.snapshot == PersistedTimerSnapshot(selectedDurationSeconds: 30, state: .ready))

        let restoredViewModel = TimerViewModel(clock: clock, timerStateStore: store, alarmScheduler: TestTimerAlarmScheduler())

        #expect(restoredViewModel.state == .ready)
        #expect(!restoredViewModel.isRepeatEnabled)
    }

    @Test func expiryTransitionsOnceAndRequiresAcknowledgementBeforeAnotherStart() async {
        let store = InMemoryTimerStateStore()
        let clock = TestTimerClock(Date(timeIntervalSinceReferenceDate: 0))
        let viewModel = TimerViewModel(
            selectedDuration: .seconds(30),
            clock: clock,
            timerStateStore: store,
            alarmScheduler: TestTimerAlarmScheduler()
        )

        await viewModel.start()
        clock.advance(by: .seconds(30))
        viewModel.refresh()
        viewModel.refresh()

        #expect(viewModel.state == .finished)
        #expect(viewModel.displayText == "00:00")
        #expect(viewModel.completionCount == 1)
        #expect(store.snapshot?.state == .finished)
        #expect(viewModel.isAwaitingCompletionAcknowledgement)
        #expect(!viewModel.shouldShowToolbarControls)

        await viewModel.start()

        #expect(viewModel.state == .finished)
        #expect(viewModel.displayText == "00:00")
    }

    @Test func acknowledgingAFinishedSingleTimerReturnsItToReadyAtItsConfiguredDuration() async {
        let store = InMemoryTimerStateStore()
        let clock = TestTimerClock(Date(timeIntervalSinceReferenceDate: 0))
        let viewModel = TimerViewModel(
            selectedDuration: .seconds(30),
            clock: clock,
            timerStateStore: store,
            alarmScheduler: TestTimerAlarmScheduler()
        )

        await viewModel.start()
        clock.advance(by: .seconds(30))
        viewModel.refresh()

        #expect(viewModel.isAwaitingCompletionAcknowledgement)

        await viewModel.acknowledgeCompletion()

        #expect(viewModel.state == .ready)
        #expect(viewModel.displayText == "00:30")
        #expect(!viewModel.isRepeatEnabled)
        #expect(!viewModel.isAwaitingCompletionAcknowledgement)
        #expect(viewModel.shouldShowToolbarControls)
        #expect(store.snapshot == PersistedTimerSnapshot(selectedDurationSeconds: 30, state: .ready))
    }

    @Test func cancellingAFinishedSingleTimerMatchesAcknowledgement() async {
        let store = InMemoryTimerStateStore()
        let clock = TestTimerClock(Date(timeIntervalSinceReferenceDate: 0))
        let viewModel = TimerViewModel(
            selectedDuration: .seconds(30),
            clock: clock,
            timerStateStore: store,
            alarmScheduler: TestTimerAlarmScheduler()
        )

        await viewModel.start()
        clock.advance(by: .seconds(30))
        viewModel.refresh()

        await viewModel.cancelAlarm()

        #expect(viewModel.state == .ready)
        #expect(viewModel.displayText == "00:30")
        #expect(!viewModel.isRepeatEnabled)
        #expect(!viewModel.isAwaitingCompletionAcknowledgement)
        #expect(store.snapshot == PersistedTimerSnapshot(selectedDurationSeconds: 30, state: .ready))
    }

    @Test func missingSavedStateStartsWithTheDefaultTimer() async {
        let viewModel = TimerViewModel(timerStateStore: InMemoryTimerStateStore(), alarmScheduler: TestTimerAlarmScheduler())

        #expect(viewModel.selectedDuration == .seconds(30))
        #expect(viewModel.state == .ready)
    }

    @Test func savedReadyTimerRestoresItsSelectedDuration() async {
        let store = InMemoryTimerStateStore()
        let firstViewModel = TimerViewModel(timerStateStore: store, alarmScheduler: TestTimerAlarmScheduler())

        firstViewModel.configure(duration: .seconds(75))

        let restoredViewModel = TimerViewModel(timerStateStore: store, alarmScheduler: TestTimerAlarmScheduler())

        #expect(restoredViewModel.selectedDuration == .seconds(75))
        #expect(restoredViewModel.state == .ready)
        #expect(restoredViewModel.displayText == "01:15")
    }

    @Test func runningTimerRestoresItsRemainingTimeBeforeExpiry() async {
        let store = InMemoryTimerStateStore()
        let clock = TestTimerClock(Date(timeIntervalSinceReferenceDate: 0))
        let firstViewModel = TimerViewModel(
            selectedDuration: .seconds(30),
            clock: clock,
            timerStateStore: store,
            alarmScheduler: TestTimerAlarmScheduler()
        )

        await firstViewModel.start()
        clock.advance(by: .seconds(10))

        let restoredViewModel = TimerViewModel(clock: clock, timerStateStore: store, alarmScheduler: TestTimerAlarmScheduler())

        #expect(restoredViewModel.state == .running(deadline: Date(timeIntervalSinceReferenceDate: 30)))
        #expect(restoredViewModel.displayText == "00:20")
    }

    @Test func expiredRunningTimerRestoresAsFinished() async {
        let store = InMemoryTimerStateStore()
        let clock = TestTimerClock(Date(timeIntervalSinceReferenceDate: 0))
        let firstViewModel = TimerViewModel(
            selectedDuration: .seconds(30),
            clock: clock,
            timerStateStore: store,
            alarmScheduler: TestTimerAlarmScheduler()
        )

        await firstViewModel.start()
        clock.advance(by: .seconds(30))

        let restoredViewModel = TimerViewModel(clock: clock, timerStateStore: store, alarmScheduler: TestTimerAlarmScheduler())

        #expect(restoredViewModel.state == .finished)
        #expect(restoredViewModel.displayText == "00:00")
        #expect(store.snapshot?.state == .finished)
    }

    @Test func resetAndConfigurationReplaceTheSavedSnapshot() async {
        let store = InMemoryTimerStateStore()
        let viewModel = TimerViewModel(timerStateStore: store, alarmScheduler: TestTimerAlarmScheduler())

        viewModel.configure(duration: .seconds(75))

        #expect(store.snapshot == PersistedTimerSnapshot(selectedDurationSeconds: 75, state: .ready))

        await viewModel.start()
        viewModel.reset()

        #expect(store.snapshot == PersistedTimerSnapshot(selectedDurationSeconds: 75, state: .ready))
    }

    @Test func presetsAreSavedOnceSortedAndPersisted() async {
        let store = InMemoryTimerStateStore()
        let viewModel = TimerViewModel(timerStateStore: store, alarmScheduler: TestTimerAlarmScheduler())

        viewModel.configure(duration: .seconds(75))
        viewModel.saveSelectedDurationAsPreset()
        viewModel.configure(duration: .seconds(60))
        viewModel.saveSelectedDurationAsPreset()
        viewModel.saveSelectedDurationAsPreset()

        let savedPresets: [TimerPreset] = [
            .defaultPreset,
            TimerPreset(duration: .seconds(60)),
            TimerPreset(duration: .seconds(75))
        ]

        #expect(viewModel.presets == savedPresets)

        viewModel.configure(duration: .seconds(75))

        #expect(viewModel.selectedDuration == .seconds(75))
        #expect(viewModel.presets == savedPresets)

        let selectedPresetViewModel = TimerViewModel(timerStateStore: store, alarmScheduler: TestTimerAlarmScheduler())

        #expect(selectedPresetViewModel.selectedDuration == .seconds(75))
        #expect(selectedPresetViewModel.presets == savedPresets)

        viewModel.removePreset(TimerPreset(duration: .seconds(60)))

        let restoredViewModel = TimerViewModel(timerStateStore: store, alarmScheduler: TestTimerAlarmScheduler())

        #expect(restoredViewModel.presets == [.defaultPreset, TimerPreset(duration: .seconds(75))])
        #expect(restoredViewModel.selectedDuration == .seconds(75))
    }

    @Test func repeatSettingIsPersisted() async {
        let store = InMemoryTimerStateStore()
        let viewModel = TimerViewModel(timerStateStore: store, alarmScheduler: TestTimerAlarmScheduler())

        await viewModel.toggleRepeat()

        let restoredViewModel = TimerViewModel(timerStateStore: store, alarmScheduler: TestTimerAlarmScheduler())

        #expect(restoredViewModel.isRepeatEnabled)
        #expect(store.snapshot?.isRepeatEnabled == true)

        await restoredViewModel.toggleRepeat()

        let disabledViewModel = TimerViewModel(timerStateStore: store, alarmScheduler: TestTimerAlarmScheduler())

        #expect(!disabledViewModel.isRepeatEnabled)
        #expect(store.snapshot?.isRepeatEnabled == false)
    }

    @Test func enablingRepeatAndStartingStartsReadyAndFinishedTimersAtTheirConfiguredDuration() async {
        let clock = TestTimerClock(Date(timeIntervalSinceReferenceDate: 0))
        let viewModel = TimerViewModel(
            selectedDuration: .seconds(30),
            clock: clock,
            timerStateStore: InMemoryTimerStateStore(),
            alarmScheduler: TestTimerAlarmScheduler()
        )

        await viewModel.enableRepeatAndStart()

        #expect(viewModel.isRepeatEnabled)
        #expect(viewModel.state == .running(deadline: Date(timeIntervalSinceReferenceDate: 30)))

        clock.advance(by: .seconds(30))
        await viewModel.toggleRepeat()
        viewModel.refresh()

        #expect(viewModel.state == .finished)

        await viewModel.enableRepeatAndStart()

        #expect(viewModel.isRepeatEnabled)
        #expect(viewModel.state == .running(deadline: Date(timeIntervalSinceReferenceDate: 60)))
        #expect(viewModel.displayText == "00:30")
    }

    @Test func foregroundRepeatShowsOneAcknowledgementWhileTheNextCycleRuns() async {
        let store = InMemoryTimerStateStore()
        let clock = TestTimerClock(Date(timeIntervalSinceReferenceDate: 0))
        let viewModel = TimerViewModel(
            selectedDuration: .seconds(30),
            clock: clock,
            timerStateStore: store,
            alarmScheduler: TestTimerAlarmScheduler()
        )

        await viewModel.applicationDidBecomeActive()
        await viewModel.toggleRepeat()
        await viewModel.start()
        clock.advance(by: .seconds(30))
        viewModel.refresh()

        #expect(viewModel.state == .running(deadline: Date(timeIntervalSinceReferenceDate: 60)))
        #expect(viewModel.isAwaitingRepeatCycleAcknowledgement)
        #expect(!viewModel.shouldShowToolbarControls)
        #expect(viewModel.displayText == "00:30")
        #expect(viewModel.completedCycleDisplayText == "00:00")
        #expect(store.snapshot?.isAwaitingRepeatCycleAcknowledgement == true)

        clock.advance(by: .seconds(30))
        viewModel.refresh()

        #expect(viewModel.state == .running(deadline: Date(timeIntervalSinceReferenceDate: 90)))
        #expect(viewModel.isAwaitingRepeatCycleAcknowledgement)
        #expect(viewModel.completionCount == 2)

        await viewModel.acknowledgeCompletion()

        #expect(!viewModel.isAwaitingRepeatCycleAcknowledgement)
        #expect(viewModel.shouldShowToolbarControls)
        #expect(viewModel.state == .running(deadline: Date(timeIntervalSinceReferenceDate: 90)))
        #expect(viewModel.completedCycleDisplayText == nil)
        #expect(store.snapshot?.isAwaitingRepeatCycleAcknowledgement == false)
    }

    @Test func cancellingARepeatingAlarmStopsTheCurrentAndFutureCycles() async {
        let store = InMemoryTimerStateStore()
        let clock = TestTimerClock(Date(timeIntervalSinceReferenceDate: 0))
        let viewModel = TimerViewModel(
            selectedDuration: .seconds(30),
            clock: clock,
            timerStateStore: store,
            alarmScheduler: TestTimerAlarmScheduler()
        )

        await viewModel.applicationDidBecomeActive()
        await viewModel.enableRepeatAndStart()
        clock.advance(by: .seconds(30))
        viewModel.refresh()

        #expect(viewModel.state == .running(deadline: Date(timeIntervalSinceReferenceDate: 60)))
        #expect(viewModel.isAwaitingRepeatCycleAcknowledgement)

        await viewModel.cancelAlarm()

        #expect(viewModel.state == .ready)
        #expect(viewModel.displayText == "00:30")
        #expect(!viewModel.isRepeatEnabled)
        #expect(!viewModel.isAwaitingRepeatCycleAcknowledgement)
        #expect(!viewModel.isAwaitingCompletionAcknowledgement)
        #expect(store.snapshot == PersistedTimerSnapshot(selectedDurationSeconds: 30, state: .ready))
    }

    @Test func elapsedRepeatTimerContinuesWhenTheAppReturns() async {
        let store = InMemoryTimerStateStore()
        let clock = TestTimerClock(Date(timeIntervalSinceReferenceDate: 0))
        let viewModel = TimerViewModel(
            selectedDuration: .seconds(30),
            clock: clock,
            timerStateStore: store,
            alarmScheduler: TestTimerAlarmScheduler()
        )

        await viewModel.applicationDidBecomeActive()
        await viewModel.toggleRepeat()
        await viewModel.start()
        viewModel.applicationDidBecomeInactive()
        clock.advance(by: .seconds(30))

        await viewModel.applicationDidBecomeActive()

        #expect(viewModel.state == .running(deadline: Date(timeIntervalSinceReferenceDate: 60)))
        #expect(viewModel.isRepeatEnabled)
        #expect(viewModel.isAwaitingRepeatCycleAcknowledgement)
        #expect(viewModel.displayText == "00:30")
    }

    @Test func elapsedRepeatTimerReconstructsTheLatestCycleAfterLaunch() async {
        let store = InMemoryTimerStateStore()
        let clock = TestTimerClock(Date(timeIntervalSinceReferenceDate: 0))
        let firstViewModel = TimerViewModel(
            selectedDuration: .seconds(30),
            clock: clock,
            timerStateStore: store,
            alarmScheduler: TestTimerAlarmScheduler()
        )

        await firstViewModel.applicationDidBecomeActive()
        await firstViewModel.toggleRepeat()
        await firstViewModel.start()
        firstViewModel.applicationDidBecomeInactive()
        clock.advance(by: .seconds(95))

        let restoredViewModel = TimerViewModel(clock: clock, timerStateStore: store, alarmScheduler: TestTimerAlarmScheduler())

        #expect(restoredViewModel.state == .running(deadline: Date(timeIntervalSinceReferenceDate: 120)))
        #expect(restoredViewModel.isRepeatEnabled)
        #expect(restoredViewModel.isAwaitingRepeatCycleAcknowledgement)
        #expect(restoredViewModel.displayText == "00:25")
        #expect(restoredViewModel.completionCount == 1)
    }

    @Test func legacySnapshotDecodesWithMilestoneFourDefaults() async throws {
        let data = Data("""
        {
          "selectedDurationSeconds": 30,
          "state": { "kind": "ready" }
        }
        """.utf8)

        let snapshot = try JSONDecoder().decode(PersistedTimerSnapshot.self, from: data)

        #expect(!snapshot.isRepeatEnabled)
        #expect(snapshot.presets == [.defaultPreset])
        #expect(!snapshot.isAwaitingRepeatCycleAcknowledgement)
    }

    @Test func corruptUserDefaultsDataFallsBackToTheDefaultTimer() async throws {
        let suiteName = "TimerViewModelTests.corruptUserDefaultsData"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        userDefaults.set(Data("not a timer snapshot".utf8), forKey: UserDefaultsTimerStateStore.storageKey)

        let viewModel = TimerViewModel(timerStateStore: UserDefaultsTimerStateStore(userDefaults: userDefaults), alarmScheduler: TestTimerAlarmScheduler())

        #expect(viewModel.selectedDuration == .seconds(30))
        #expect(viewModel.state == .ready)
        #expect(userDefaults.data(forKey: UserDefaultsTimerStateStore.storageKey) == nil)
    }

    @Test func timerLinkConfiguresAReadyTimerAndDisablesRepeat() async throws {
        let store = InMemoryTimerStateStore()
        let viewModel = TimerViewModel(timerStateStore: store, alarmScheduler: TestTimerAlarmScheduler())
        let request = try TimerLinkParser.parse(try url("kitchenclock://timer?seconds=75"))

        await viewModel.toggleRepeat()
        let result = viewModel.applyTimerLink(request)

        #expect(result == .configured)
        #expect(viewModel.selectedDuration == .seconds(75))
        #expect(viewModel.state == .ready)
        #expect(!viewModel.isRepeatEnabled)
        #expect(!viewModel.isAwaitingRepeatCycleAcknowledgement)
        #expect(store.snapshot == PersistedTimerSnapshot(selectedDurationSeconds: 75, state: .ready))
    }

    @Test func timerLinkConfiguresAFinishedTimer() async throws {
        let store = InMemoryTimerStateStore()
        let clock = TestTimerClock(Date(timeIntervalSinceReferenceDate: 0))
        let viewModel = TimerViewModel(clock: clock, timerStateStore: store, alarmScheduler: TestTimerAlarmScheduler())
        let request = try TimerLinkParser.parse(try url("kitchenclock://timer?seconds=75"))

        await viewModel.start()
        clock.advance(by: .seconds(30))
        viewModel.refresh()

        #expect(viewModel.state == .finished)

        let result = viewModel.applyTimerLink(request)

        #expect(result == .configured)
        #expect(viewModel.selectedDuration == .seconds(75))
        #expect(viewModel.state == .ready)
        #expect(!viewModel.isRepeatEnabled)
        #expect(store.snapshot == PersistedTimerSnapshot(selectedDurationSeconds: 75, state: .ready))
    }

    @Test func timerLinkDoesNotReplaceARunningTimer() async throws {
        let store = InMemoryTimerStateStore()
        let clock = TestTimerClock(Date(timeIntervalSinceReferenceDate: 0))
        let viewModel = TimerViewModel(clock: clock, timerStateStore: store, alarmScheduler: TestTimerAlarmScheduler())
        let request = try TimerLinkParser.parse(try url("kitchenclock://timer?seconds=75"))

        await viewModel.toggleRepeat()
        await viewModel.start()
        let originalState = viewModel.state
        let originalSnapshot = store.snapshot

        let result = viewModel.applyTimerLink(request)

        #expect(result == .rejectedWhileTimerIsActive)
        #expect(viewModel.selectedDuration == .seconds(30))
        #expect(viewModel.state == originalState)
        #expect(viewModel.isRepeatEnabled)
        #expect(!viewModel.isAwaitingRepeatCycleAcknowledgement)
        #expect(store.snapshot == originalSnapshot)
    }

    private func url(_ string: String) throws -> URL {
        try #require(URL(string: string))
    }
}
