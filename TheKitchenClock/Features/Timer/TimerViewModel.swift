import Foundation
import Observation

@MainActor
@Observable
final class TimerViewModel {
    static let defaultDuration: Duration = .seconds(30)
    static let minimumDuration: Duration = .seconds(1)
    static let maximumDuration: Duration = .seconds(99 * 3_600 + 59 * 60 + 59)

    private(set) var selectedDuration: Duration
    private(set) var state: TimerState
    private(set) var completionCount = 0

    @ObservationIgnored private let clock: any TimerClock
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    private var currentDate: Date

    init(
        selectedDuration: Duration = .seconds(30),
        state: TimerState = .ready,
        clock: any TimerClock = SystemTimerClock()
    ) {
        self.clock = clock
        self.currentDate = clock.now()
        self.selectedDuration = Self.clampedDuration(selectedDuration)
        self.state = state
    }

    deinit {
        refreshTask?.cancel()
    }

    var displayText: String {
        TimerDurationFormatter.string(for: displayDuration)
    }

    var isRunning: Bool {
        state.isRunning
    }

    var primaryActionTitle: String {
        switch state {
        case .ready:
            "Start"
        case .paused:
            "Resume"
        case .finished:
            "Start Again"
        case .running:
            ""
        }
    }

    func configure(duration: Duration) {
        guard !isRunning else {
            return
        }

        selectedDuration = Self.clampedDuration(duration)
        currentDate = clock.now()
        state = .ready
    }

    func start() {
        currentDate = clock.now()

        switch state {
        case .ready, .finished:
            startTimer(with: selectedDuration)
        case .paused(let remaining):
            startTimer(with: remaining)
        case .running:
            break
        }
    }

    func pause() {
        refresh()

        guard state.isRunning else {
            return
        }

        state = .paused(remaining: displayDuration)
        stopRefreshing()
    }

    func reset() {
        stopRefreshing()
        currentDate = clock.now()
        state = .ready
    }

    func refresh() {
        currentDate = clock.now()

        guard case let .running(deadline) = state, deadline <= currentDate else {
            return
        }

        state = .finished
        completionCount += 1
        stopRefreshing()
    }

    private var displayDuration: Duration {
        switch state {
        case .ready:
            selectedDuration
        case .running(let deadline):
            Self.remainingDuration(until: deadline, from: currentDate)
        case .paused(let remaining):
            remaining
        case .finished:
            .zero
        }
    }

    private func startTimer(with duration: Duration) {
        let deadline = currentDate.addingTimeInterval(duration.timerTimeInterval)
        state = .running(deadline: deadline)
        startRefreshing()
    }

    private func startRefreshing() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }

                guard let self else {
                    return
                }

                self.refresh()

                guard self.isRunning else {
                    return
                }
            }
        }
    }

    private func stopRefreshing() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    private static func clampedDuration(_ duration: Duration) -> Duration {
        let seconds = min(
            max(duration.components.seconds, minimumDuration.components.seconds),
            maximumDuration.components.seconds
        )

        return .seconds(seconds)
    }

    private static func remainingDuration(until deadline: Date, from currentDate: Date) -> Duration {
        let remainingSeconds = deadline.timeIntervalSince(currentDate)

        guard remainingSeconds > 0 else {
            return .zero
        }

        return .seconds(Int64(remainingSeconds.rounded(.up)))
    }
}
