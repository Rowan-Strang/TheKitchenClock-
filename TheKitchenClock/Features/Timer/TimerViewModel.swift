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
    @ObservationIgnored private let liveActivityManager: any TimerLiveActivityManaging
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var alarmUpdatesTask: Task<Void, Never>?
    private var currentDate: Date
    private var isApplicationActive = false
    private var isManagingAlarmQueue = false
    private var alarmLifecycleRevision: UInt = 0
    private var oneShotAlarmID: UUID?
    private var oneShotDeadline: Date?
    private var loopAlarmSession: PersistedLoopAlarmSession?

    init(
        selectedDuration: Duration = .seconds(30),
        state: TimerState = .ready,
        clock: any TimerClock = SystemTimerClock(),
        timerStateStore: any TimerStateStore = UserDefaultsTimerStateStore(),
        alarmScheduler: any TimerAlarmScheduling = SystemTimerAlarmScheduler(),
        liveActivityManager: any TimerLiveActivityManaging = SystemTimerLiveActivityManager()
    ) {
        self.clock = clock
        self.timerStateStore = timerStateStore
        self.alarmScheduler = alarmScheduler
        self.liveActivityManager = liveActivityManager
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
                self.oneShotDeadline = restoredTimer.oneShotDeadline
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

    func configure(duration: Duration) async {
        guard !isRunning else {
            return
        }

        clearTrackedAlarms()
        setReadyTimer(duration: duration, isRepeatEnabled: isRepeatEnabled)
        await synchronizeLiveActivity(allowStart: false)
    }

    func applyTimerLink(_ request: TimerLinkRequest) async -> TimerLinkApplicationResult {
        guard !isRunning else {
            return .rejectedWhileTimerIsActive
        }

        clearTrackedAlarms()
        setReadyTimer(duration: request.duration, isRepeatEnabled: false)
        await synchronizeLiveActivity(allowStart: false)
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

    func reset() async {
        clearTrackedAlarms()
        stopRefreshing()
        currentDate = clock.now()
        state = .ready
        isRepeatEnabled = false
        isAwaitingRepeatCycleAcknowledgement = false
        persist()
        await synchronizeLiveActivity(allowStart: false)
    }

    func refresh() async {
        currentDate = clock.now()
        let previousState = state
        refreshTimer(allowingRepeat: isApplicationActive && isRepeatEnabled)

        if state != previousState {
            await synchronizeLiveActivity(allowStart: false)
        }
    }

    func applicationDidBecomeActive() async {
        currentDate = clock.now()
        isApplicationActive = true
        synchronizeAlarmStateFromStore()

        if let alarmStatus = try? alarmScheduler.currentAlarmStatus() {
            await reconcileAlarms(alarmStatus: alarmStatus)
        } else {
            refreshTimer(allowingRepeat: isRepeatEnabled)
            await synchronizeLiveActivity(allowStart: true)
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
                await disableRepeatKeepingCurrentAlarm()
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
            self.oneShotDeadline = nil
            state = .ready
        }

        guard state == .ready else {
            return
        }

        isRepeatEnabled = true
        persist()
        await startRepeatingTimer()
    }

    func enableRepeatFromFinishedOneShot() async {
        guard state == .finished, !isStarting else {
            return
        }

        guard let oneShotDeadline else {
            await enableRepeatAndStart()
            return
        }

        isStarting = true
        defer { isStarting = false }
        let lifecycleRevision = beginAlarmLifecycleOperation()

        guard await authorizeAlarms(for: lifecycleRevision) else {
            return
        }

        currentDate = clock.now()
        let nextCycleIndex = Self.firstFutureCycleIndex(
            after: oneShotDeadline,
            currentDate: currentDate,
            duration: selectedDuration
        )
        var session = PersistedLoopAlarmSession(
            id: UUID(),
            anchorDeadline: oneShotDeadline,
            durationSeconds: selectedDuration.components.seconds,
            nextCycleIndex: nextCycleIndex,
            lastAcknowledgedCycleIndex: nextCycleIndex - 1,
            entries: []
        )
        let replenishmentResult = await LoopAlarmQueueCoordinator.replenish(
            session: &session,
            now: currentDate,
            scheduler: alarmScheduler,
            isSessionValid: { self.isAlarmLifecycleCurrent(lifecycleRevision) }
        )

        guard case let .completed(hasFailure) = replenishmentResult else {
            return
        }

        guard !session.entries.isEmpty, isAlarmLifecycleCurrent(lifecycleRevision) else {
            alarmIssue = .schedulingFailed
            return
        }

        if let oneShotAlarmID {
            try? alarmScheduler.stop(id: oneShotAlarmID)
        }

        self.oneShotAlarmID = nil
        self.oneShotDeadline = nil
        loopAlarmSession = session
        isRepeatEnabled = true

        if hasFailure {
            alarmIssue = .limitedRepeatCoverage
        }

        await beginRunning(
            deadline: session.fireDate(for: nextCycleIndex),
            lifecycleRevision: lifecycleRevision
        )
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
            let lifecycleRevision = alarmLifecycleRevision

            let dueEntries = session.entries.filter { $0.fireDate <= currentDate }

            for entry in dueEntries {
                try? alarmScheduler.stop(id: entry.id)
            }

            if let latestCycle = dueEntries.map(\.cycleIndex).max() {
                session.lastAcknowledgedCycleIndex = max(session.lastAcknowledgedCycleIndex, latestCycle)
            }

            let dueIDs = Set(dueEntries.map(\.id))
            session.entries.removeAll { dueIDs.contains($0.id) }
            let replenishmentResult = await LoopAlarmQueueCoordinator.replenish(
                session: &session,
                now: currentDate,
                scheduler: alarmScheduler,
                isSessionValid: { self.isAlarmLifecycleCurrent(lifecycleRevision) }
            )

            guard case let .completed(hasFailure) = replenishmentResult,
                  isAlarmLifecycleCurrent(lifecycleRevision) else {
                return
            }

            loopAlarmSession = session
            isAwaitingRepeatCycleAcknowledgement = false
            refreshTimer(allowingRepeat: isApplicationActive && isRepeatEnabled)
            persist()

            if hasFailure {
                alarmIssue = .limitedRepeatCoverage
            }

            await synchronizeLiveActivity(allowStart: false)
            return
        }

        guard state == .finished else {
            return
        }

        invalidateAlarmLifecycle()
        if let oneShotAlarmID {
            alarmScheduler.tearDown(ids: [oneShotAlarmID])
        }
        self.oneShotAlarmID = nil
        setReadyTimer(duration: selectedDuration, isRepeatEnabled: isRepeatEnabled)
        await synchronizeLiveActivity(allowStart: false)
    }

    func cancelAlarm() async {
        guard isAwaitingCompletionAcknowledgement else {
            return
        }

        if isAwaitingRepeatCycleAcknowledgement {
            await reset()
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
        let lifecycleRevision = beginAlarmLifecycleOperation()

        guard await authorizeAlarms(for: lifecycleRevision) else {
            return
        }

        currentDate = clock.now()
        let deadline = currentDate.addingTimeInterval(selectedDuration.timerTimeInterval)
        let alarmID = UUID()

        do {
            try await alarmScheduler.schedule(id: alarmID, deadline: deadline, loopContext: nil)
        } catch {
            guard isAlarmLifecycleCurrent(lifecycleRevision) else {
                alarmScheduler.tearDown(ids: [alarmID])
                return
            }

            alarmIssue = .schedulingFailed
            return
        }

        guard isAlarmLifecycleCurrent(lifecycleRevision) else {
            alarmScheduler.tearDown(ids: [alarmID])
            return
        }

        oneShotAlarmID = alarmID
        oneShotDeadline = deadline
        loopAlarmSession = nil
        await beginRunning(deadline: deadline, lifecycleRevision: lifecycleRevision)
    }

    private func startRepeatingTimer() async {
        isStarting = true
        defer { isStarting = false }
        let lifecycleRevision = beginAlarmLifecycleOperation()

        guard await authorizeAlarms(for: lifecycleRevision) else {
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
        let replenishmentResult = await LoopAlarmQueueCoordinator.replenish(
            session: &session,
            now: currentDate,
            scheduler: alarmScheduler,
            isSessionValid: { self.isAlarmLifecycleCurrent(lifecycleRevision) }
        )

        guard case let .completed(hasFailure) = replenishmentResult else {
            return
        }

        guard !session.entries.isEmpty, isAlarmLifecycleCurrent(lifecycleRevision) else {
            alarmIssue = .schedulingFailed
            return
        }

        oneShotAlarmID = nil
        oneShotDeadline = nil
        loopAlarmSession = session

        if hasFailure {
            alarmIssue = .limitedRepeatCoverage
        }

        await beginRunning(deadline: deadline, lifecycleRevision: lifecycleRevision)
    }

    private func convertRunningTimerToRepeat() async {
        guard case let .running(deadline) = state else {
            return
        }

        isStarting = true
        defer { isStarting = false }
        let lifecycleRevision = beginAlarmLifecycleOperation()

        guard await authorizeAlarms(for: lifecycleRevision) else {
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
        let replenishmentResult = await LoopAlarmQueueCoordinator.replenish(
            session: &session,
            now: currentDate,
            scheduler: alarmScheduler,
            isSessionValid: { self.isAlarmLifecycleCurrent(lifecycleRevision) }
        )

        guard case let .completed(hasFailure) = replenishmentResult else {
            return
        }

        guard !session.entries.isEmpty, isAlarmLifecycleCurrent(lifecycleRevision) else {
            alarmIssue = .schedulingFailed
            return
        }

        if let oneShotAlarmID {
            try? alarmScheduler.cancel(id: oneShotAlarmID)
        }

        oneShotAlarmID = nil
        oneShotDeadline = nil
        loopAlarmSession = session
        isRepeatEnabled = true
        persist()

        if hasFailure {
            alarmIssue = .limitedRepeatCoverage
        }

        await synchronizeLiveActivity(allowStart: true)
    }

    private func disableRepeatKeepingCurrentAlarm() async {
        invalidateAlarmLifecycle()

        guard case let .running(deadline) = state, let session = loopAlarmSession else {
            isRepeatEnabled = false
            loopAlarmSession = nil
            persist()
            await synchronizeLiveActivity(allowStart: false)
            return
        }

        let keptEntry = session.entries
            .filter { $0.fireDate >= deadline }
            .min { $0.fireDate < $1.fireDate }

        let removedAlarmIDs = Set(
            session.entries.lazy
                .filter { $0.id != keptEntry?.id }
                .map(\.id)
        )
        alarmScheduler.tearDown(ids: removedAlarmIDs)

        oneShotAlarmID = keptEntry?.id
        oneShotDeadline = keptEntry?.fireDate
        loopAlarmSession = nil
        isRepeatEnabled = false
        isAwaitingRepeatCycleAcknowledgement = false
        persist()
        await synchronizeLiveActivity(allowStart: true)
    }

    private func authorizeAlarms(for lifecycleRevision: UInt) async -> Bool {
        do {
            let authorization = try await alarmScheduler.requestAuthorization()

            guard isAlarmLifecycleCurrent(lifecycleRevision) else {
                return false
            }

            guard authorization == .authorized else {
                alarmIssue = .authorizationDenied
                return false
            }
            alarmIssue = nil
            return true
        } catch {
            guard isAlarmLifecycleCurrent(lifecycleRevision) else {
                return false
            }

            alarmIssue = .schedulingFailed
            return false
        }
    }

    private func beginRunning(deadline: Date, lifecycleRevision: UInt) async {
        guard isAlarmLifecycleCurrent(lifecycleRevision) else {
            return
        }

        state = .running(deadline: deadline)
        isAwaitingRepeatCycleAcknowledgement = false
        persist()
        startRefreshing()
        await synchronizeLiveActivity(allowStart: true)
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
        oneShotDeadline = nil
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
        invalidateAlarmLifecycle()
        var alarmIDs = Set(loopAlarmSession?.entries.map(\.id) ?? [])

        if let oneShotAlarmID {
            alarmIDs.insert(oneShotAlarmID)
        }

        alarmScheduler.tearDown(ids: alarmIDs)

        oneShotAlarmID = nil
        oneShotDeadline = nil
        loopAlarmSession = nil
    }

    private func beginAlarmLifecycleOperation() -> UInt {
        invalidateAlarmLifecycle()
        return alarmLifecycleRevision
    }

    private func invalidateAlarmLifecycle() {
        alarmLifecycleRevision &+= 1
    }

    private func isAlarmLifecycleCurrent(_ revision: UInt) -> Bool {
        alarmLifecycleRevision == revision
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
                oneShotDeadline: oneShotDeadline,
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

                await self.refresh()

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
            for await alarmStatus in updates {
                guard let self else {
                    return
                }

                guard !self.isStarting, !self.isManagingAlarmQueue else {
                    continue
                }

                let latestStatus = (try? self.alarmScheduler.currentAlarmStatus()) ?? alarmStatus
                await self.reconcileAlarms(alarmStatus: latestStatus)
            }
        }
    }

    private func reconcileAlarms(alarmStatus: TimerAlarmStatus) async {
        guard !isManagingAlarmQueue else {
            return
        }
        isManagingAlarmQueue = true
        defer { isManagingAlarmQueue = false }

        currentDate = clock.now()
        synchronizeAlarmStateFromStore()

        if let oneShotAlarmID, alarmStatus.alertingIDs.contains(oneShotAlarmID), let oneShotDeadline {
            currentDate = max(currentDate, oneShotDeadline)
        }

        if let loopAlarmSession {
            for entry in loopAlarmSession.entries where alarmStatus.alertingIDs.contains(entry.id) {
                currentDate = max(currentDate, entry.fireDate)
            }
        }

        if let oneShotAlarmID, !alarmStatus.activeIDs.contains(oneShotAlarmID) {
            self.oneShotAlarmID = nil
            self.oneShotDeadline = nil

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
            let lifecycleRevision = alarmLifecycleRevision
            let removedEntries = session.entries.filter { !alarmStatus.activeIDs.contains($0.id) }

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
            let replenishmentResult = await LoopAlarmQueueCoordinator.replenish(
                session: &session,
                now: currentDate,
                scheduler: alarmScheduler,
                isSessionValid: { self.isAlarmLifecycleCurrent(lifecycleRevision) }
            )

            guard case let .completed(hasFailure) = replenishmentResult,
                  isAlarmLifecycleCurrent(lifecycleRevision) else {
                return
            }

            loopAlarmSession = session

            if hasFailure {
                alarmIssue = .limitedRepeatCoverage
            }
        }

        refreshTimer(allowingRepeat: isRepeatEnabled)
        isAwaitingRepeatCycleAcknowledgement = hasUnacknowledgedDueLoopAlarm
        persist()
        await synchronizeLiveActivity(allowStart: isApplicationActive)
    }

    private func synchronizeLiveActivity(allowStart: Bool) async {
        let lifecycleRevision = alarmLifecycleRevision
        let duration = selectedDuration.timerTimeInterval
        let activityState: TimerLiveActivityState

        switch state {
        case .ready:
            activityState = .inactive
        case let .running(deadline):
            if let sessionID = loopAlarmSession?.id ?? oneShotAlarmID {
                activityState = .countdown(
                    sessionID: sessionID,
                    startDate: deadline.addingTimeInterval(-duration),
                    deadline: deadline
                )
            } else {
                activityState = .inactive
            }
        case .finished:
            if let oneShotAlarmID, let oneShotDeadline {
                activityState = .finished(
                    sessionID: oneShotAlarmID,
                    startDate: oneShotDeadline.addingTimeInterval(-duration),
                    deadline: oneShotDeadline
                )
            } else {
                activityState = .inactive
            }
        }

        await liveActivityManager.synchronize(activityState, allowStart: allowStart)

        guard !isAlarmLifecycleCurrent(lifecycleRevision) else {
            return
        }

        await synchronizeLiveActivity(allowStart: isApplicationActive)
    }

    private func synchronizeAlarmStateFromStore() {
        guard let snapshot = timerStateStore.load() else {
            return
        }

        if snapshot.state == .ready,
           snapshot.oneShotAlarmID == nil,
           snapshot.loopAlarmSession == nil,
           (state == .finished || (state.isRunning && !isRepeatEnabled)) {
            state = .ready
            isRepeatEnabled = false
            isAwaitingRepeatCycleAcknowledgement = false
            stopRefreshing()
        }

        oneShotAlarmID = snapshot.oneShotAlarmID
        oneShotDeadline = snapshot.oneShotDeadline
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
        oneShotDeadline: Date?,
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
            snapshot.isRepeatEnabled ? nil : snapshot.oneShotDeadline,
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

    private static func firstFutureCycleIndex(
        after anchorDeadline: Date,
        currentDate: Date,
        duration: Duration
    ) -> Int {
        let durationSeconds = duration.timerTimeInterval
        let completedIntervals = max(0, floor(currentDate.timeIntervalSince(anchorDeadline) / durationSeconds))

        return Int(completedIntervals) + 2
    }
}
