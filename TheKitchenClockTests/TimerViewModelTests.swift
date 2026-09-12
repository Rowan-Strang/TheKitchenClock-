import Foundation
import Testing
@testable import TheKitchenClock

@MainActor
struct TimerViewModelTests {
    @Test func defaultTimerIsReadyForThirtySeconds() {
        let viewModel = TimerViewModel()

        #expect(viewModel.selectedDuration == .seconds(30))
        #expect(viewModel.state == .ready)
        #expect(viewModel.displayText == "00:30")
    }

    @Test func configuredDurationIsClampedToSupportedRange() {
        let viewModel = TimerViewModel(selectedDuration: .zero)

        #expect(viewModel.selectedDuration == .seconds(1))

        viewModel.configure(duration: .seconds(100 * 3_600))

        #expect(viewModel.selectedDuration == .seconds(99 * 3_600 + 59 * 60 + 59))
        #expect(viewModel.displayText == "99:59:59")
    }

    @Test func runningTimerUsesItsDeadlineForTheDisplayedRemainingTime() {
        let clock = TestTimerClock(Date(timeIntervalSinceReferenceDate: 0))
        let viewModel = TimerViewModel(selectedDuration: .seconds(30), clock: clock)

        viewModel.start()
        clock.advance(by: .seconds(10))
        viewModel.refresh()

        #expect(viewModel.displayText == "00:20")
        #expect(viewModel.state == .running(deadline: Date(timeIntervalSinceReferenceDate: 30)))
    }

    @Test func pausePreservesRemainingTimeAndResumeCreatesANewDeadline() {
        let clock = TestTimerClock(Date(timeIntervalSinceReferenceDate: 0))
        let viewModel = TimerViewModel(selectedDuration: .seconds(30), clock: clock)

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
        let viewModel = TimerViewModel(selectedDuration: .seconds(30), clock: clock)

        viewModel.start()
        clock.advance(by: .seconds(5))
        viewModel.reset()

        #expect(viewModel.state == .ready)
        #expect(viewModel.displayText == "00:30")
    }

    @Test func expiryTransitionsOnceAndCanStartTheSameDurationAgain() {
        let clock = TestTimerClock(Date(timeIntervalSinceReferenceDate: 0))
        let viewModel = TimerViewModel(selectedDuration: .seconds(30), clock: clock)

        viewModel.start()
        clock.advance(by: .seconds(30))
        viewModel.refresh()
        viewModel.refresh()

        #expect(viewModel.state == .finished)
        #expect(viewModel.displayText == "00:00")
        #expect(viewModel.completionCount == 1)

        viewModel.start()

        #expect(viewModel.state == .running(deadline: Date(timeIntervalSinceReferenceDate: 60)))
        #expect(viewModel.displayText == "00:30")
    }
}
