import AppIntents
import Foundation

struct LoopAlarmStopIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop Repeating Timer Alarm"
    static let description = IntentDescription("Stops this timer alarm and schedules the next repeating alarm.")

    @Parameter(title: "Alarm ID")
    var alarmID: String

    @Parameter(title: "Loop Session ID")
    var sessionID: String

    @Parameter(title: "Cycle Index")
    var cycleIndex: Int

    init(alarmID: String, sessionID: String, cycleIndex: Int) {
        self.alarmID = alarmID
        self.sessionID = sessionID
        self.cycleIndex = cycleIndex
    }

    init() {
        alarmID = ""
        sessionID = ""
        cycleIndex = 0
    }

    func perform() async throws -> some IntentResult {
        guard let alarmID = UUID(uuidString: alarmID),
              let sessionID = UUID(uuidString: sessionID) else {
            return .result()
        }

        await LoopAlarmQueueCoordinator.handleSystemDismissal(
            alarmID: alarmID,
            sessionID: sessionID,
            cycleIndex: cycleIndex
        )
        return .result()
    }
}
