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

    @Test func resetReturnsTheTimerToItsConfiguredDuration() {
        let clock = TestTimerClock(Date(timeIntervalSinceReferenceDate: 0))
        let viewModel = TimerViewModel(
            selectedDuration: .seconds(30),
            clock: clock,
            timerStateStore: InMemoryTimerStateStore()
        )

        viewModel.start()
        clock.advance(by: .seconds(5))
        viewModel.reset()

        #expect(viewModel.state == .ready)
        #expect(viewModel.displayText == "00:30")
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
}
