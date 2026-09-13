import Foundation
import Testing
@testable import TheKitchenClock

@MainActor
struct TimerViewModelTests {
    @Test func defaultTimerIsReadyForThirtySeconds() {
        let viewModel = TimerViewModel(timerStateStore: InMemoryTimerStateStore())

        #expect(viewModel.selectedDuration == .seconds(30))
        #expect(viewModel.state == .ready)
        #expect(viewModel.displayText == "00:30")
        #expect(viewModel.presets == [.defaultPreset])
    }

    @Test func configuredDurationIsClampedToSupportedRange() {
        let viewModel = TimerViewModel(selectedDuration: .zero, timerStateStore: InMemoryTimerStateStore())

        #expect(viewModel.selectedDuration == .seconds(1))

        viewModel.configure(duration: .seconds(100 * 3_600))

        #expect(viewModel.selectedDuration == .seconds(99 * 3_600 + 59 * 60 + 59))
        #expect(viewModel.displayText == "99:59:59")
    }

    @Test func runningTimerUsesItsDeadlineForTheDisplayedRemainingTime() {
        let clock = TestTimerClock(Date(timeIntervalSinceReferenceDate: 0))
        let viewModel = TimerViewModel(
            selectedDuration: .seconds(30),
            clock: clock,
            timerStateStore: InMemoryTimerStateStore()
        )

        viewModel.start()
        clock.advance(by: .seconds(10))
        viewModel.refresh()

        #expect(viewModel.displayText == "00:20")
        #expect(viewModel.state == .running(deadline: Date(timeIntervalSinceReferenceDate: 30)))
    }

    @Test func pausePreservesRemainingTimeAndResumeCreatesANewDeadline() {
        let clock = TestTimerClock(Date(timeIntervalSinceReferenceDate: 0))
        let viewModel = TimerViewModel(
            selectedDuration: .seconds(30),
            clock: clock,
            timerStateStore: InMemoryTimerStateStore()
        )

        viewModel.start()
        clock.advance(by: .seconds(12))
        viewModel.pause()

        #expect(viewModel.state == .paused(remaining: .seconds(18)))
        #expect(viewModel.displayText == "00:18")

        clock.advance(by: .seconds(600))
        viewModel.refresh()
        viewModel.start()

        #expect(viewModel.state == .running(deadline: Date(timeIntervalSinceReferenceDate: 630)))
        #expect(viewModel.displayText == "00:18")
    }

    @Test func resetWhileRunningReturnsToSingleTimerModeAtTheConfiguredDuration() {
        let store = InMemoryTimerStateStore()
        let clock = TestTimerClock(Date(timeIntervalSinceReferenceDate: 0))
        let viewModel = TimerViewModel(
            selectedDuration: .seconds(30),
            clock: clock,
            timerStateStore: store
        )

        viewModel.toggleRepeat()
        viewModel.start()
        clock.advance(by: .seconds(5))
        viewModel.reset()

        #expect(viewModel.state == .ready)
        #expect(viewModel.displayText == "00:30")
        #expect(!viewModel.isRepeatEnabled)
        #expect(!viewModel.isAwaitingRepeatCycleAcknowledgement)
        #expect(store.snapshot == PersistedTimerSnapshot(selectedDurationSeconds: 30, state: .ready))

        let restoredViewModel = TimerViewModel(clock: clock, timerStateStore: store)

        #expect(restoredViewModel.state == .ready)
        #expect(!restoredViewModel.isRepeatEnabled)
    }

    @Test func resetWhilePausedReturnsToSingleTimerModeAtTheConfiguredDuration() {
        let store = InMemoryTimerStateStore()
        let clock = TestTimerClock(Date(timeIntervalSinceReferenceDate: 0))
        let viewModel = TimerViewModel(
            selectedDuration: .seconds(30),
            clock: clock,
            timerStateStore: store
        )

        viewModel.toggleRepeat()
        viewModel.start()
        clock.advance(by: .seconds(12))
        viewModel.pause()
        viewModel.reset()

        #expect(viewModel.state == .ready)
        #expect(viewModel.displayText == "00:30")
        #expect(!viewModel.isRepeatEnabled)
        #expect(!viewModel.isAwaitingRepeatCycleAcknowledgement)
        #expect(store.snapshot == PersistedTimerSnapshot(selectedDurationSeconds: 30, state: .ready))
    }

    @Test func expiryTransitionsOnceAndCanStartTheSameDurationAgain() {
        let store = InMemoryTimerStateStore()
        let clock = TestTimerClock(Date(timeIntervalSinceReferenceDate: 0))
        let viewModel = TimerViewModel(
            selectedDuration: .seconds(30),
            clock: clock,
            timerStateStore: store
        )

        viewModel.start()
        clock.advance(by: .seconds(30))
        viewModel.refresh()
        viewModel.refresh()

        #expect(viewModel.state == .finished)
        #expect(viewModel.displayText == "00:00")
        #expect(viewModel.completionCount == 1)
        #expect(store.snapshot?.state == .finished)

        viewModel.start()

        #expect(viewModel.state == .running(deadline: Date(timeIntervalSinceReferenceDate: 60)))
        #expect(viewModel.displayText == "00:30")
    }

    @Test func missingSavedStateStartsWithTheDefaultTimer() {
        let viewModel = TimerViewModel(timerStateStore: InMemoryTimerStateStore())

        #expect(viewModel.selectedDuration == .seconds(30))
        #expect(viewModel.state == .ready)
    }

    @Test func savedReadyTimerRestoresItsSelectedDuration() {
        let store = InMemoryTimerStateStore()
        let firstViewModel = TimerViewModel(timerStateStore: store)

        firstViewModel.configure(duration: .seconds(75))

        let restoredViewModel = TimerViewModel(timerStateStore: store)

        #expect(restoredViewModel.selectedDuration == .seconds(75))
        #expect(restoredViewModel.state == .ready)
        #expect(restoredViewModel.displayText == "01:15")
    }

    @Test func runningTimerRestoresItsRemainingTimeBeforeExpiry() {
        let store = InMemoryTimerStateStore()
        let clock = TestTimerClock(Date(timeIntervalSinceReferenceDate: 0))
        let firstViewModel = TimerViewModel(
            selectedDuration: .seconds(30),
            clock: clock,
            timerStateStore: store
        )

        firstViewModel.start()
        clock.advance(by: .seconds(10))

        let restoredViewModel = TimerViewModel(clock: clock, timerStateStore: store)

        #expect(restoredViewModel.state == .running(deadline: Date(timeIntervalSinceReferenceDate: 30)))
        #expect(restoredViewModel.displayText == "00:20")
    }

    @Test func expiredRunningTimerRestoresAsFinished() {
        let store = InMemoryTimerStateStore()
        let clock = TestTimerClock(Date(timeIntervalSinceReferenceDate: 0))
        let firstViewModel = TimerViewModel(
            selectedDuration: .seconds(30),
            clock: clock,
            timerStateStore: store
        )

        firstViewModel.start()
        clock.advance(by: .seconds(30))

        let restoredViewModel = TimerViewModel(clock: clock, timerStateStore: store)

        #expect(restoredViewModel.state == .finished)
        #expect(restoredViewModel.displayText == "00:00")
        #expect(store.snapshot?.state == .finished)
    }

    @Test func pausedTimerRestoresItsCapturedRemainingTime() {
        let store = InMemoryTimerStateStore()
        let clock = TestTimerClock(Date(timeIntervalSinceReferenceDate: 0))
        let firstViewModel = TimerViewModel(
            selectedDuration: .seconds(30),
            clock: clock,
            timerStateStore: store
        )

        firstViewModel.start()
        clock.advance(by: .seconds(12))
        firstViewModel.pause()
        clock.advance(by: .seconds(600))

        let restoredViewModel = TimerViewModel(clock: clock, timerStateStore: store)

        #expect(restoredViewModel.state == .paused(remaining: .seconds(18)))
        #expect(restoredViewModel.displayText == "00:18")
    }

    @Test func resetAndConfigurationReplaceTheSavedSnapshot() {
        let store = InMemoryTimerStateStore()
        let viewModel = TimerViewModel(timerStateStore: store)

        viewModel.configure(duration: .seconds(75))

        #expect(store.snapshot == PersistedTimerSnapshot(selectedDurationSeconds: 75, state: .ready))

        viewModel.start()
        viewModel.reset()

        #expect(store.snapshot == PersistedTimerSnapshot(selectedDurationSeconds: 75, state: .ready))
    }

    @Test func presetsAreSavedOnceSortedAndPersisted() {
        let store = InMemoryTimerStateStore()
        let viewModel = TimerViewModel(timerStateStore: store)

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

        let selectedPresetViewModel = TimerViewModel(timerStateStore: store)

        #expect(selectedPresetViewModel.selectedDuration == .seconds(75))
        #expect(selectedPresetViewModel.presets == savedPresets)

        viewModel.removePreset(TimerPreset(duration: .seconds(60)))

        let restoredViewModel = TimerViewModel(timerStateStore: store)

        #expect(restoredViewModel.presets == [.defaultPreset, TimerPreset(duration: .seconds(75))])
        #expect(restoredViewModel.selectedDuration == .seconds(75))
    }

    @Test func repeatSettingIsPersisted() {
        let store = InMemoryTimerStateStore()
        let viewModel = TimerViewModel(timerStateStore: store)

        viewModel.toggleRepeat()

        let restoredViewModel = TimerViewModel(timerStateStore: store)

        #expect(restoredViewModel.isRepeatEnabled)
        #expect(store.snapshot?.isRepeatEnabled == true)

        restoredViewModel.toggleRepeat()

        let disabledViewModel = TimerViewModel(timerStateStore: store)

        #expect(!disabledViewModel.isRepeatEnabled)
        #expect(store.snapshot?.isRepeatEnabled == false)
    }

    @Test func togglingRepeatAndStartingRestartsTheConfiguredDuration() {
        let clock = TestTimerClock(Date(timeIntervalSinceReferenceDate: 0))
        let viewModel = TimerViewModel(
            selectedDuration: .seconds(30),
            clock: clock,
            timerStateStore: InMemoryTimerStateStore()
        )

        viewModel.applicationDidBecomeActive()
        viewModel.start()
        clock.advance(by: .seconds(12))
        viewModel.pause()
        viewModel.toggleRepeatAndStart()

        #expect(viewModel.isRepeatEnabled)
        #expect(viewModel.state == .running(deadline: Date(timeIntervalSinceReferenceDate: 42)))
        #expect(viewModel.displayText == "00:30")
    }

    @Test func foregroundRepeatShowsOneAcknowledgementWhileTheNextCycleRuns() {
        let store = InMemoryTimerStateStore()
        let clock = TestTimerClock(Date(timeIntervalSinceReferenceDate: 0))
        let viewModel = TimerViewModel(
            selectedDuration: .seconds(30),
            clock: clock,
            timerStateStore: store
        )

        viewModel.applicationDidBecomeActive()
        viewModel.toggleRepeat()
        viewModel.start()
        clock.advance(by: .seconds(30))
        viewModel.refresh()

        #expect(viewModel.state == .running(deadline: Date(timeIntervalSinceReferenceDate: 60)))
        #expect(viewModel.isAwaitingRepeatCycleAcknowledgement)
        #expect(viewModel.displayText == "00:30")
        #expect(store.snapshot?.isAwaitingRepeatCycleAcknowledgement == true)

        clock.advance(by: .seconds(30))
        viewModel.refresh()

        #expect(viewModel.state == .running(deadline: Date(timeIntervalSinceReferenceDate: 90)))
        #expect(viewModel.isAwaitingRepeatCycleAcknowledgement)
        #expect(viewModel.completionCount == 2)

        viewModel.acknowledgeRepeatCycleCompletion()

        #expect(!viewModel.isAwaitingRepeatCycleAcknowledgement)
        #expect(viewModel.state == .running(deadline: Date(timeIntervalSinceReferenceDate: 90)))
        #expect(store.snapshot?.isAwaitingRepeatCycleAcknowledgement == false)
    }

    @Test func elapsedRepeatTimerContinuesWhenTheAppReturns() {
        let store = InMemoryTimerStateStore()
        let clock = TestTimerClock(Date(timeIntervalSinceReferenceDate: 0))
        let viewModel = TimerViewModel(
            selectedDuration: .seconds(30),
            clock: clock,
            timerStateStore: store
        )

        viewModel.applicationDidBecomeActive()
        viewModel.toggleRepeat()
        viewModel.start()
        viewModel.applicationDidBecomeInactive()
        clock.advance(by: .seconds(30))

        viewModel.applicationDidBecomeActive()

        #expect(viewModel.state == .running(deadline: Date(timeIntervalSinceReferenceDate: 60)))
        #expect(viewModel.isRepeatEnabled)
        #expect(viewModel.isAwaitingRepeatCycleAcknowledgement)
        #expect(viewModel.displayText == "00:30")
    }

    @Test func elapsedRepeatTimerReconstructsTheLatestCycleAfterLaunch() {
        let store = InMemoryTimerStateStore()
        let clock = TestTimerClock(Date(timeIntervalSinceReferenceDate: 0))
        let firstViewModel = TimerViewModel(
            selectedDuration: .seconds(30),
            clock: clock,
            timerStateStore: store
        )

        firstViewModel.applicationDidBecomeActive()
        firstViewModel.toggleRepeat()
        firstViewModel.start()
        firstViewModel.applicationDidBecomeInactive()
        clock.advance(by: .seconds(95))

        let restoredViewModel = TimerViewModel(clock: clock, timerStateStore: store)

        #expect(restoredViewModel.state == .running(deadline: Date(timeIntervalSinceReferenceDate: 120)))
        #expect(restoredViewModel.isRepeatEnabled)
        #expect(restoredViewModel.isAwaitingRepeatCycleAcknowledgement)
        #expect(restoredViewModel.displayText == "00:25")
        #expect(restoredViewModel.completionCount == 1)
    }

    @Test func legacySnapshotDecodesWithMilestoneFourDefaults() throws {
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

    @Test func invalidSavedSnapshotFallsBackToTheDefaultTimer() {
        let store = InMemoryTimerStateStore(
            snapshot: PersistedTimerSnapshot(
                selectedDurationSeconds: 30,
                state: .paused(remainingSeconds: 0)
            )
        )

        let viewModel = TimerViewModel(timerStateStore: store)

        #expect(viewModel.selectedDuration == .seconds(30))
        #expect(viewModel.state == .ready)
        #expect(store.snapshot == PersistedTimerSnapshot(selectedDurationSeconds: 30, state: .ready))
    }

    @Test func corruptUserDefaultsDataFallsBackToTheDefaultTimer() throws {
        let suiteName = "TimerViewModelTests.corruptUserDefaultsData"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        userDefaults.set(Data("not a timer snapshot".utf8), forKey: UserDefaultsTimerStateStore.storageKey)

        let viewModel = TimerViewModel(timerStateStore: UserDefaultsTimerStateStore(userDefaults: userDefaults))

        #expect(viewModel.selectedDuration == .seconds(30))
        #expect(viewModel.state == .ready)
        #expect(userDefaults.data(forKey: UserDefaultsTimerStateStore.storageKey) == nil)
    }

    @Test func timerLinkConfiguresAReadyTimerAndDisablesRepeat() throws {
        let store = InMemoryTimerStateStore()
        let viewModel = TimerViewModel(timerStateStore: store)
        let request = try TimerLinkParser.parse(try url("kitchenclock://timer?seconds=75"))

        viewModel.toggleRepeat()
        let result = viewModel.applyTimerLink(request)

        #expect(result == .configured)
        #expect(viewModel.selectedDuration == .seconds(75))
        #expect(viewModel.state == .ready)
        #expect(!viewModel.isRepeatEnabled)
        #expect(!viewModel.isAwaitingRepeatCycleAcknowledgement)
        #expect(store.snapshot == PersistedTimerSnapshot(selectedDurationSeconds: 75, state: .ready))
    }

    @Test func timerLinkConfiguresAFinishedTimer() throws {
        let store = InMemoryTimerStateStore()
        let clock = TestTimerClock(Date(timeIntervalSinceReferenceDate: 0))
        let viewModel = TimerViewModel(clock: clock, timerStateStore: store)
        let request = try TimerLinkParser.parse(try url("kitchenclock://timer?seconds=75"))

        viewModel.start()
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

    @Test func timerLinkDoesNotReplaceARunningTimer() throws {
        let store = InMemoryTimerStateStore()
        let clock = TestTimerClock(Date(timeIntervalSinceReferenceDate: 0))
        let viewModel = TimerViewModel(clock: clock, timerStateStore: store)
        let request = try TimerLinkParser.parse(try url("kitchenclock://timer?seconds=75"))

        viewModel.toggleRepeat()
        viewModel.start()
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

    @Test func timerLinkDoesNotReplaceAPausedTimer() throws {
        let store = InMemoryTimerStateStore()
        let clock = TestTimerClock(Date(timeIntervalSinceReferenceDate: 0))
        let viewModel = TimerViewModel(clock: clock, timerStateStore: store)
        let request = try TimerLinkParser.parse(try url("kitchenclock://timer?seconds=75"))

        viewModel.toggleRepeat()
        viewModel.start()
        clock.advance(by: .seconds(12))
        viewModel.pause()
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
