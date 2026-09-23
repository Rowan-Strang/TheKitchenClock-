import AppIntents
import Foundation

struct OneShotAlarmStopIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop Timer Alarm"
    static let description = IntentDescription("Dismisses a completed timer's Live Activity.")

    @Parameter(title: "Alarm ID")
    var alarmID: String

    init(alarmID: String) {
        self.alarmID = alarmID
    }

    init() {
        alarmID = ""
    }

    func perform() async throws -> some IntentResult {
        guard let alarmID = UUID(uuidString: alarmID) else {
            return .result()
        }

        await OneShotAlarmCoordinator.handleSystemDismissal(alarmID: alarmID)
        return .result()
    }
}
