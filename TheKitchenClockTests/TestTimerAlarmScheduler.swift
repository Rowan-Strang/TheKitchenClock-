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
    private(set) var authorizationRequestCount = 0
    private(set) var scheduleAttemptCount = 0
    private(set) var scheduledAlarms: [UUID: ScheduledAlarm] = [:]
    private(set) var cancelledAlarmIDs: [UUID] = []
    private(set) var stoppedAlarmIDs: [UUID] = []
    private(set) var alertingAlarmIDs: Set<UUID> = []
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

        if failingScheduleAttempts.contains(scheduleAttemptCount) {
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

    func fire(id: UUID) {
        alertingAlarmIDs.insert(id)
        sendAlarmUpdate()
    }
}
