import Foundation

@MainActor
protocol TimerAlarmScheduling {
    func requestAuthorization() async throws -> TimerAlarmAuthorization
    func schedule(id: UUID, deadline: Date, loopContext: TimerAlarmLoopContext?) async throws
    func cancel(id: UUID) throws
    func stop(id: UUID) throws
    func tearDown(ids: Set<UUID>)
    func currentAlarmStatus() throws -> TimerAlarmStatus
    func alarmUpdates() -> AsyncStream<TimerAlarmStatus>
}
