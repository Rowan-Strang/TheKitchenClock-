import Foundation
@testable import TheKitchenClock

@MainActor
final class TestTimerAlarmScheduler: TimerAlarmScheduling {
    struct ScheduledAlarm: Equatable {
        let id: UUID
        let deadline: Date
        let loopContext: TimerAlarmLoopContext?
    }

    enum TestError: Error {
        case failed
    }

    var authorization: TimerAlarmAuthorization = .authorized
    var authorizationError: Error?
    var failingScheduleAttempts: Set<Int> = []
    var suspendedScheduleAttempts: Set<Int> = []
    private(set) var authorizationRequestCount = 0
    private(set) var scheduleAttemptCount = 0
    private(set) var scheduledAlarms: [UUID: ScheduledAlarm] = [:]
    private(set) var cancelledAlarmIDs: [UUID] = []
    private(set) var stoppedAlarmIDs: [UUID] = []
    private(set) var tornDownAlarmIDs: Set<UUID> = []
    private(set) var alertingAlarmIDs: Set<UUID> = []
    private var suspendedScheduleContinuations: [Int: CheckedContinuation<Void, Never>] = [:]
    private let updatesStream: AsyncStream<TimerAlarmStatus>
    private let updatesContinuation: AsyncStream<TimerAlarmStatus>.Continuation

    init() {
        (updatesStream, updatesContinuation) = AsyncStream.makeStream()
    }

    func requestAuthorization() async throws -> TimerAlarmAuthorization {
        authorizationRequestCount += 1

        if let authorizationError {
            throw authorizationError
        }

        return authorization
    }

    func schedule(id: UUID, deadline: Date, loopContext: TimerAlarmLoopContext?) async throws {
        scheduleAttemptCount += 1
        let attempt = scheduleAttemptCount

        if suspendedScheduleAttempts.contains(attempt) {
            await withCheckedContinuation { continuation in
                suspendedScheduleContinuations[attempt] = continuation
            }
        }

        if failingScheduleAttempts.contains(attempt) {
            throw TestError.failed
        }

        scheduledAlarms[id] = ScheduledAlarm(id: id, deadline: deadline, loopContext: loopContext)
    }

    func cancel(id: UUID) throws {
        cancelledAlarmIDs.append(id)
        scheduledAlarms[id] = nil
        alertingAlarmIDs.remove(id)
    }

    func stop(id: UUID) throws {
        stoppedAlarmIDs.append(id)
        scheduledAlarms[id] = nil
        alertingAlarmIDs.remove(id)
    }

    func tearDown(ids: Set<UUID>) {
        tornDownAlarmIDs.formUnion(ids)

        for id in ids {
            if alertingAlarmIDs.contains(id) {
                try? stop(id: id)
            } else {
                try? cancel(id: id)
            }
        }
    }

    func currentAlarmStatus() throws -> TimerAlarmStatus {
        TimerAlarmStatus(activeIDs: Set(scheduledAlarms.keys), alertingIDs: alertingAlarmIDs)
    }

    func alarmUpdates() -> AsyncStream<TimerAlarmStatus> {
        updatesStream
    }

    func sendAlarmUpdate() {
        updatesContinuation.yield(
            TimerAlarmStatus(activeIDs: Set(scheduledAlarms.keys), alertingIDs: alertingAlarmIDs)
        )
    }

    func fire(id: UUID, sendsUpdate: Bool = true) {
        alertingAlarmIDs.insert(id)

        if sendsUpdate {
            sendAlarmUpdate()
        }
    }

    func waitUntilScheduleAttemptIsSuspended(_ attempt: Int) async {
        while suspendedScheduleContinuations[attempt] == nil {
            await Task.yield()
        }
    }

    func resumeScheduleAttempt(_ attempt: Int) {
        suspendedScheduleContinuations.removeValue(forKey: attempt)?.resume()
    }
}
