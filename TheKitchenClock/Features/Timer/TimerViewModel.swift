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
    private(set) var isStarting = false
    private(set) var alarmIssue: TimerAlarmIssue?

    @ObservationIgnored private let clock: any TimerClock
    @ObservationIgnored private let timerStateStore: any TimerStateStore
    @ObservationIgnored private let alarmScheduler: any TimerAlarmScheduling
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var alarmUpdatesTask: Task<Void, Never>?
    private var currentDate: Date
    private var isApplicationActive = false
    private var isManagingAlarmQueue = false
    private var oneShotAlarmID: UUID?
    private var loopAlarmSession: PersistedLoopAlarmSession?

    init(
        selectedDuration: Duration = .seconds(30),
        state: TimerState = .ready,
        clock: any TimerClock = SystemTimerClock(),
        timerStateStore: any TimerStateStore = UserDefaultsTimerStateStore(),
        alarmScheduler: any TimerAlarmScheduling = SystemTimerAlarmScheduler()
    ) {
        self.clock = clock
        self.timerStateStore = timerStateStore
        self.alarmScheduler = alarmScheduler
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
                self.oneShotAlarmID = restoredTimer.oneShotAlarmID
                self.loopAlarmSession = restoredTimer.loopAlarmSession
            } else {
                persist()
            }
        }

        restorePersistedTimerState()
        observeAlarmUpdates()
    }

    deinit {
        refreshTask?.cancel()
        alarmUpdatesTask?.cancel()
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

        clearTrackedAlarms()
        setReadyTimer(duration: duration, isRepeatEnabled: isRepeatEnabled)
    }

    func applyTimerLink(_ request: TimerLinkRequest) -> TimerLinkApplicationResult {
        guard !isRunning else {
            return .rejectedWhileTimerIsActive
        }

        clearTrackedAlarms()
        setReadyTimer(duration: request.duration, isRepeatEnabled: false)
        return .configured
    }

    func start() async {
        guard state == .ready, !isStarting else {
            return
        }

        if isRepeatEnabled {
            await startRepeatingTimer()
        } else {
            await startOneShotTimer()
        }
    }

    func reset() {
        clearTrackedAlarms()
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

    func applicationDidBecomeActive() async {
        currentDate = clock.now()
        isApplicationActive = true
        synchronizeAlarmStateFromStore()

        if let activeAlarmIDs = try? alarmScheduler.scheduledAlarmIDs() {
            await reconcileAlarms(activeAlarmIDs: activeAlarmIDs)
        } else {
            refreshTimer(allowingRepeat: isRepeatEnabled)
        }

        if isRunning {
            startRefreshing()
        }
    }

    func applicationDidBecomeInactive() {
        isApplicationActive = false
        stopRefreshing()
    }

    func toggleRepeat() async {
        guard !isStarting else {
            return
        }

        if isRunning {
            if isRepeatEnabled {
                disableRepeatKeepingCurrentAlarm()
            } else {
                await convertRunningTimerToRepeat()
            }
            return
        }

        isRepeatEnabled.toggle()

        if !isRepeatEnabled {
            isAwaitingRepeatCycleAcknowledgement = false
        }

        persist()
    }

    func enableRepeatAndStart() async {
        guard !isStarting else {
            return
        }

        if state == .finished {
            if let oneShotAlarmID {
                try? alarmScheduler.stop(id: oneShotAlarmID)
            }
            self.oneShotAlarmID = nil
            state = .ready
        }

        guard state == .ready else {
            return
        }

        isRepeatEnabled = true
        persist()
        await startRepeatingTimer()
    }

    func acknowledgeCompletion() async {
        currentDate = clock.now()

        if isAwaitingRepeatCycleAcknowledgement {
            guard !isManagingAlarmQueue else {
                return
            }
            isManagingAlarmQueue = true
            defer { isManagingAlarmQueue = false }

            guard var session = loopAlarmSession else {
                isAwaitingRepeatCycleAcknowledgement = false
                persist()
                return
            }

            let dueEntries = session.entries.filter { $0.fireDate <= currentDate }

            for entry in dueEntries {
                try? alarmScheduler.stop(id: entry.id)
            }

            if let latestCycle = dueEntries.map(\.cycleIndex).max() {
                session.lastAcknowledgedCycleIndex = max(session.lastAcknowledgedCycleIndex, latestCycle)
            }

            let dueIDs = Set(dueEntries.map(\.id))
            session.entries.removeAll { dueIDs.contains($0.id) }
            let hasFailure = await LoopAlarmQueueCoordinator.replenish(
                session: &session,
                now: currentDate,
                scheduler: alarmScheduler
            )
            loopAlarmSession = session
            isAwaitingRepeatCycleAcknowledgement = false
            refreshTimer(allowingRepeat: isApplicationActive && isRepeatEnabled)
            persist()

            if hasFailure {
                alarmIssue = .limitedRepeatCoverage
            }
            return
        }

        guard state == .finished else {
            return
        }

        if let oneShotAlarmID {
            try? alarmScheduler.stop(id: oneShotAlarmID)
        }
        self.oneShotAlarmID = nil
        setReadyTimer(duration: selectedDuration, isRepeatEnabled: isRepeatEnabled)
    }

    func cancelAlarm() async {
        guard isAwaitingCompletionAcknowledgement else {
            return
        }

        if isAwaitingRepeatCycleAcknowledgement {
            reset()
        } else {
            await acknowledgeCompletion()
        }
    }

    func dismissAlarmIssue() {
        alarmIssue = nil
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

    private func startOneShotTimer() async {
        isStarting = true
        defer { isStarting = false }

        guard await authorizeAlarms() else {
            return
        }

        currentDate = clock.now()
        let deadline = currentDate.addingTimeInterval(selectedDuration.timerTimeInterval)
        let alarmID = UUID()

        do {
            try await alarmScheduler.schedule(id: alarmID, deadline: deadline, loopContext: nil)
        } catch {
            alarmIssue = .schedulingFailed
            return
        }

        oneShotAlarmID = alarmID
        loopAlarmSession = nil
        beginRunning(deadline: deadline)
    }

    private func startRepeatingTimer() async {
        isStarting = true
        defer { isStarting = false }

        guard await authorizeAlarms() else {
            return
        }

        currentDate = clock.now()
        let deadline = currentDate.addingTimeInterval(selectedDuration.timerTimeInterval)
        var session = PersistedLoopAlarmSession(
            id: UUID(),
            anchorDeadline: deadline,
            durationSeconds: selectedDuration.components.seconds,
            nextCycleIndex: 1,
            lastAcknowledgedCycleIndex: 0,
            entries: []
        )
        let hasFailure = await LoopAlarmQueueCoordinator.replenish(
            session: &session,
            now: currentDate,
            scheduler: alarmScheduler
        )

        guard !session.entries.isEmpty else {
            alarmIssue = .schedulingFailed
            return
        }

        oneShotAlarmID = nil
        loopAlarmSession = session
        beginRunning(deadline: deadline)

        if hasFailure {
            alarmIssue = .limitedRepeatCoverage
        }
    }

    private func convertRunningTimerToRepeat() async {
        guard case let .running(deadline) = state else {
            return
        }

        isStarting = true
        defer { isStarting = false }

        guard await authorizeAlarms() else {
            return
        }

        currentDate = clock.now()
        guard deadline > currentDate else {
            refreshTimer(allowingRepeat: false)
            return
        }

        var session = PersistedLoopAlarmSession(
            id: UUID(),
            anchorDeadline: deadline,
            durationSeconds: selectedDuration.components.seconds,
            nextCycleIndex: 1,
            lastAcknowledgedCycleIndex: 0,
            entries: []
        )
        let hasFailure = await LoopAlarmQueueCoordinator.replenish(
            session: &session,
            now: currentDate,
            scheduler: alarmScheduler
        )

        guard !session.entries.isEmpty else {
            alarmIssue = .schedulingFailed
            return
        }

        if let oneShotAlarmID {
            try? alarmScheduler.cancel(id: oneShotAlarmID)
        }

        oneShotAlarmID = nil
        loopAlarmSession = session
        isRepeatEnabled = true
        persist()

        if hasFailure {
            alarmIssue = .limitedRepeatCoverage
        }
    }

    private func disableRepeatKeepingCurrentAlarm() {
        guard case let .running(deadline) = state, let session = loopAlarmSession else {
            isRepeatEnabled = false
            loopAlarmSession = nil
            persist()
            return
        }

        let keptEntry = session.entries
            .filter { $0.fireDate >= deadline }
            .min { $0.fireDate < $1.fireDate }

        for entry in session.entries where entry.id != keptEntry?.id {
            try? alarmScheduler.cancel(id: entry.id)
        }

        oneShotAlarmID = keptEntry?.id
        loopAlarmSession = nil
        isRepeatEnabled = false
        isAwaitingRepeatCycleAcknowledgement = false
        persist()
    }

    private func authorizeAlarms() async -> Bool {
        do {
            guard try await alarmScheduler.requestAuthorization() == .authorized else {
                alarmIssue = .authorizationDenied
                return false
            }
            alarmIssue = nil
            return true
        } catch {
            alarmIssue = .schedulingFailed
            return false
        }
    }

    private func beginRunning(deadline: Date) {
        state = .running(deadline: deadline)
        isAwaitingRepeatCycleAcknowledgement = false
        persist()
        startRefreshing()
    }

    private func refreshTimer(allowingRepeat: Bool) {
        guard case let .running(deadline) = state, deadline <= currentDate else {
            return
        }

        completionCount += 1

        if allowingRepeat {
            state = .running(
                deadline: Self.nextDeadline(
                    after: deadline,
                    currentDate: currentDate,
                    duration: selectedDuration
                )
            )
            isAwaitingRepeatCycleAcknowledgement = hasUnacknowledgedDueLoopAlarm
        } else {
            state = .finished
            isAwaitingRepeatCycleAcknowledgement = false
            stopRefreshing()
        }

        persist()
    }

    private var hasUnacknowledgedDueLoopAlarm: Bool {
        guard let session = loopAlarmSession else {
            return false
        }

        return session.entries.contains {
            $0.fireDate <= currentDate && $0.cycleIndex > session.lastAcknowledgedCycleIndex
        }
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

    private func clearTrackedAlarms() {
        if let oneShotAlarmID {
            try? alarmScheduler.cancel(id: oneShotAlarmID)
        }

        if let loopAlarmSession {
            for entry in loopAlarmSession.entries {
                try? alarmScheduler.cancel(id: entry.id)
            }
        }

        oneShotAlarmID = nil
        loopAlarmSession = nil
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
                isAwaitingRepeatCycleAcknowledgement: isAwaitingRepeatCycleAcknowledgement,
                oneShotAlarmID: oneShotAlarmID,
                loopAlarmSession: loopAlarmSession
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

    private func observeAlarmUpdates() {
        let updates = alarmScheduler.alarmUpdates()

        alarmUpdatesTask = Task { [weak self] in
            for await activeAlarmIDs in updates {
                guard let self else {
                    return
                }

                guard !self.isStarting, !self.isManagingAlarmQueue else {
                    continue
                }

                let latestAlarmIDs = (try? self.alarmScheduler.scheduledAlarmIDs()) ?? activeAlarmIDs
                await self.reconcileAlarms(activeAlarmIDs: latestAlarmIDs)
            }
        }
    }

    private func reconcileAlarms(activeAlarmIDs: Set<UUID>) async {
        guard !isManagingAlarmQueue else {
            return
        }
        isManagingAlarmQueue = true
        defer { isManagingAlarmQueue = false }

        currentDate = clock.now()
        synchronizeAlarmStateFromStore()

        if let oneShotAlarmID, !activeAlarmIDs.contains(oneShotAlarmID) {
            self.oneShotAlarmID = nil

            if case let .running(deadline) = state, deadline <= currentDate {
                state = .ready
                isRepeatEnabled = false
                isAwaitingRepeatCycleAcknowledgement = false
            } else if state == .finished {
                state = .ready
                isRepeatEnabled = false
            }
        }

        if var session = loopAlarmSession {
            let removedEntries = session.entries.filter { !activeAlarmIDs.contains($0.id) }

            if let latestDismissedCycle = removedEntries
                .filter({ $0.fireDate <= currentDate })
                .map(\.cycleIndex)
                .max() {
                session.lastAcknowledgedCycleIndex = max(
                    session.lastAcknowledgedCycleIndex,
                    latestDismissedCycle
                )
            }

            let removedIDs = Set(removedEntries.map(\.id))
            session.entries.removeAll { removedIDs.contains($0.id) }
            let hasFailure = await LoopAlarmQueueCoordinator.replenish(
                session: &session,
                now: currentDate,
                scheduler: alarmScheduler
            )
            loopAlarmSession = session

            if hasFailure {
                alarmIssue = .limitedRepeatCoverage
            }
        }

        refreshTimer(allowingRepeat: isRepeatEnabled)
        isAwaitingRepeatCycleAcknowledgement = hasUnacknowledgedDueLoopAlarm
        persist()
    }

    private func synchronizeAlarmStateFromStore() {
        guard let snapshot = timerStateStore.load() else {
            return
        }

        oneShotAlarmID = snapshot.oneShotAlarmID
        loopAlarmSession = snapshot.loopAlarmSession

        if isRepeatEnabled {
            isAwaitingRepeatCycleAcknowledgement = snapshot.isAwaitingRepeatCycleAcknowledgement
        }
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
        isAwaitingRepeatCycleAcknowledgement: Bool,
        oneShotAlarmID: UUID?,
        loopAlarmSession: PersistedLoopAlarmSession?
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
            isAwaitingRepeatCycleAcknowledgement,
            snapshot.isRepeatEnabled ? nil : snapshot.oneShotAlarmID,
            snapshot.isRepeatEnabled ? snapshot.loopAlarmSession : nil
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
