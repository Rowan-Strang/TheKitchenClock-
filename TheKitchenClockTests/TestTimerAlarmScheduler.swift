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
    private let updatesStream: AsyncStream<Set<UUID>>
    private let updatesContinuation: AsyncStream<Set<UUID>>.Continuation

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
    }

    func stop(id: UUID) throws {
        stoppedAlarmIDs.append(id)
        scheduledAlarms[id] = nil
    }

    func scheduledAlarmIDs() throws -> Set<UUID> {
        Set(scheduledAlarms.keys)
    }

    func alarmUpdates() -> AsyncStream<Set<UUID>> {
        updatesStream
    }

    func sendAlarmUpdate() {
        updatesContinuation.yield(Set(scheduledAlarms.keys))
    }
}
