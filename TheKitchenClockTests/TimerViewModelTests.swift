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
}
