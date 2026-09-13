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
    private(set) var presets: [TimerPreset]
    private(set) var isRepeatEnabled: Bool
    private(set) var isAwaitingRepeatCycleAcknowledgement: Bool

    @ObservationIgnored private let clock: any TimerClock
    @ObservationIgnored private let timerStateStore: any TimerStateStore
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    private var currentDate: Date
    private var isApplicationActive = false

    init(
        selectedDuration: Duration = .seconds(30),
        state: TimerState = .ready,
        clock: any TimerClock = SystemTimerClock(),
        timerStateStore: any TimerStateStore = UserDefaultsTimerStateStore()
    ) {
        self.clock = clock
        self.timerStateStore = timerStateStore
        self.currentDate = clock.now()
        self.selectedDuration = Self.clampedDuration(selectedDuration)
        self.state = state
        self.presets = [.defaultPreset]
        self.isRepeatEnabled = false
        self.isAwaitingRepeatCycleAcknowledgement = false

        if let snapshot = timerStateStore.load() {
            if let restoredTimer = Self.restore(from: snapshot) {
                self.selectedDuration = restoredTimer.selectedDuration
                self.state = restoredTimer.state
                self.presets = restoredTimer.presets
                self.isRepeatEnabled = restoredTimer.isRepeatEnabled
                self.isAwaitingRepeatCycleAcknowledgement = restoredTimer.isAwaitingRepeatCycleAcknowledgement
            } else {
                persist()
            }
        }

        restorePersistedTimerState()
    }

    deinit {
        refreshTask?.cancel()
    }

    var displayText: String {
        TimerDurationFormatter.string(for: displayDuration)
    }

    var completedCycleDisplayText: String? {
        guard isAwaitingRepeatCycleAcknowledgement else {
            return nil
        }

        return TimerDurationFormatter.string(for: .zero)
    }

    var isRunning: Bool {
        state.isRunning
    }

    var isAwaitingCompletionAcknowledgement: Bool {
        isAwaitingRepeatCycleAcknowledgement || state == .finished
    }

    var shouldShowToolbarControls: Bool {
        !isAwaitingCompletionAcknowledgement
    }

    func configure(duration: Duration) {
        guard !isRunning else {
            return
        }

        setReadyTimer(duration: duration, isRepeatEnabled: isRepeatEnabled)
    }

    func applyTimerLink(_ request: TimerLinkRequest) -> TimerLinkApplicationResult {
        guard !isRunning else {
            return .rejectedWhileTimerIsActive
        }

        setReadyTimer(duration: request.duration, isRepeatEnabled: false)
        return .configured
    }

    func start() {
        currentDate = clock.now()

        switch state {
        case .ready:
            startTimer(with: selectedDuration)
        case .running, .finished:
            break
        }
    }

    func reset() {
        stopRefreshing()
        currentDate = clock.now()
        state = .ready
        isRepeatEnabled = false
        isAwaitingRepeatCycleAcknowledgement = false
        persist()
    }

    func refresh() {
        currentDate = clock.now()
        refreshTimer(allowingRepeat: isApplicationActive && isRepeatEnabled)
    }

    func applicationDidBecomeActive() {
        currentDate = clock.now()
        isApplicationActive = true
        refreshTimer(allowingRepeat: isRepeatEnabled)

        if isRunning {
            startRefreshing()
        }
    }

    func applicationDidBecomeInactive() {
        isApplicationActive = false
        stopRefreshing()
    }

    func toggleRepeat() {
        isRepeatEnabled.toggle()

        if !isRepeatEnabled {
            isAwaitingRepeatCycleAcknowledgement = false
        }

        persist()
    }

    func enableRepeatAndStart() {
        isRepeatEnabled = true
        currentDate = clock.now()

        switch state {
        case .ready, .finished:
            startTimer(with: selectedDuration)
        case .running:
            persist()
        }
    }

    func acknowledgeCompletion() {
        if isAwaitingRepeatCycleAcknowledgement {
            currentDate = clock.now()
            isAwaitingRepeatCycleAcknowledgement = false
            refreshTimer(allowingRepeat: isApplicationActive && isRepeatEnabled)
            persist()
            return
        }

        guard state == .finished else {
            return
        }

        setReadyTimer(duration: selectedDuration, isRepeatEnabled: isRepeatEnabled)
    }

    func cancelAlarm() {
        guard isAwaitingCompletionAcknowledgement else {
            return
        }

        if isAwaitingRepeatCycleAcknowledgement {
            reset()
        } else {
            acknowledgeCompletion()
        }
    }

    func saveSelectedDurationAsPreset() {
        let preset = TimerPreset(duration: selectedDuration)

        guard !presets.contains(preset) else {
            return
        }

        presets = Self.normalizedPresets(presets + [preset])
        persist()
    }

    func removePreset(_ preset: TimerPreset) {
        presets.removeAll { $0 == preset }
        persist()
    }

    private func refreshTimer(allowingRepeat: Bool) {
        guard case let .running(deadline) = state, deadline <= currentDate else {
            return
        }

        completionCount += 1

        if allowingRepeat {
            state = .running(deadline: Self.nextDeadline(after: deadline, currentDate: currentDate, duration: selectedDuration))
            isAwaitingRepeatCycleAcknowledgement = true
        } else {
            state = .finished
            isAwaitingRepeatCycleAcknowledgement = false
            stopRefreshing()
        }

        persist()
    }

    private var displayDuration: Duration {
        switch state {
        case .ready:
            selectedDuration
        case .running(let deadline):
            Self.remainingDuration(until: deadline, from: currentDate)
        case .finished:
            .zero
        }
    }

    private func startTimer(with duration: Duration) {
        let deadline = currentDate.addingTimeInterval(duration.timerTimeInterval)
        state = .running(deadline: deadline)
        isAwaitingRepeatCycleAcknowledgement = false
        persist()
        startRefreshing()
    }

    private func setReadyTimer(duration: Duration, isRepeatEnabled: Bool) {
        selectedDuration = Self.clampedDuration(duration)
        currentDate = clock.now()
        state = .ready
        self.isRepeatEnabled = isRepeatEnabled
        isAwaitingRepeatCycleAcknowledgement = false
        persist()
    }

    private func restorePersistedTimerState() {
        guard case let .running(deadline) = state else {
            return
        }

        if deadline <= currentDate {
            refreshTimer(allowingRepeat: isRepeatEnabled)
        }
    }

    private func persist() {
        let persistedState: PersistedTimerState

        switch state {
        case .ready:
            persistedState = .ready
        case .running(let deadline):
            persistedState = .running(deadline: deadline)
        case .finished:
            persistedState = .finished
        }

        timerStateStore.save(
            PersistedTimerSnapshot(
                selectedDurationSeconds: selectedDuration.components.seconds,
                state: persistedState,
                isRepeatEnabled: isRepeatEnabled,
                presets: presets,
                isAwaitingRepeatCycleAcknowledgement: isAwaitingRepeatCycleAcknowledgement
            )
        )
    }

    private func startRefreshing() {
        guard isApplicationActive else {
            return
        }

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

    private static func restore(
        from snapshot: PersistedTimerSnapshot
    ) -> (
        selectedDuration: Duration,
        state: TimerState,
        presets: [TimerPreset],
        isRepeatEnabled: Bool,
        isAwaitingRepeatCycleAcknowledgement: Bool
    )? {
        guard supportedDurationSeconds.contains(snapshot.selectedDurationSeconds) else {
            return nil
        }

        let selectedDuration = Duration.seconds(snapshot.selectedDurationSeconds)
        let state: TimerState

        switch snapshot.state {
        case .ready:
            state = .ready
        case .running(let deadline):
            state = .running(deadline: deadline)
        case .finished:
            state = .finished
        }

        let isAwaitingRepeatCycleAcknowledgement = snapshot.isRepeatEnabled
            && state.isRunning
            && snapshot.isAwaitingRepeatCycleAcknowledgement

        return (
            selectedDuration,
            state,
            normalizedPresets(snapshot.presets),
            snapshot.isRepeatEnabled,
            isAwaitingRepeatCycleAcknowledgement
        )
    }

    private static var supportedDurationSeconds: ClosedRange<Int64> {
        minimumDuration.components.seconds...maximumDuration.components.seconds
    }

    private static func remainingDuration(until deadline: Date, from currentDate: Date) -> Duration {
        let remainingSeconds = deadline.timeIntervalSince(currentDate)

        guard remainingSeconds > 0 else {
            return .zero
        }

        return .seconds(Int64(remainingSeconds.rounded(.up)))
    }

    private static func normalizedPresets(_ presets: [TimerPreset]) -> [TimerPreset] {
        var normalizedPresets: [TimerPreset] = []

        for preset in presets.sorted(by: { $0.durationSeconds < $1.durationSeconds }) {
            guard normalizedPresets.last != preset else {
                continue
            }

            normalizedPresets.append(preset)
        }

        return normalizedPresets
    }

    private static func nextDeadline(after deadline: Date, currentDate: Date, duration: Duration) -> Date {
        let durationSeconds = duration.timerTimeInterval
        let elapsedIntervals = max(0, floor(currentDate.timeIntervalSince(deadline) / durationSeconds))
        let nextIntervalCount = elapsedIntervals + 1

        return deadline.addingTimeInterval(durationSeconds * nextIntervalCount)
    }
}
