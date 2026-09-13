@preconcurrency import AlarmKit
import Foundation
import SwiftUI

@MainActor
final class SystemTimerAlarmScheduler: TimerAlarmScheduling {
    private let alarmManager = AlarmManager.shared

    func requestAuthorization() async throws -> TimerAlarmAuthorization {
        switch alarmManager.authorizationState {
        case .notDetermined:
            let state = try await alarmManager.requestAuthorization()
            return state == .authorized ? .authorized : .denied
        case .authorized:
            return .authorized
        case .denied:
            return .denied
        @unknown default:
            return .denied
        }
    }

    func schedule(id: UUID, deadline: Date, loopContext: TimerAlarmLoopContext?) async throws {
        let alert: AlarmPresentation.Alert

        if #available(iOS 26.1, *) {
            alert = AlarmPresentation.Alert(title: "Timer Finished")
        } else {
            let stopButton = AlarmButton(
                text: "Dismiss",
                textColor: .white,
                systemImageName: "stop.circle"
            )
            alert = AlarmPresentation.Alert(title: "Timer Finished", stopButton: stopButton)
        }

        let attributes = AlarmAttributes<TimerAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),
            tintColor: .accentColor
        )
        let stopIntent = loopContext.map {
            LoopAlarmStopIntent(
                alarmID: id.uuidString,
                sessionID: $0.sessionID.uuidString,
                cycleIndex: $0.cycleIndex
            )
        }
        let configuration = AlarmManager.AlarmConfiguration<TimerAlarmMetadata>.alarm(
            schedule: .fixed(deadline),
            attributes: attributes,
            stopIntent: stopIntent
        )

        _ = try await alarmManager.schedule(id: id, configuration: configuration)
    }

    func cancel(id: UUID) throws {
        try alarmManager.cancel(id: id)
    }

    func stop(id: UUID) throws {
        try alarmManager.stop(id: id)
    }

    func scheduledAlarmIDs() throws -> Set<UUID> {
        Set(try alarmManager.alarms.map(\.id))
    }

    func alarmUpdates() -> AsyncStream<Set<UUID>> {
        let updates = alarmManager.alarmUpdates

        return AsyncStream { continuation in
            let task = Task {
                for await alarms in updates {
                    continuation.yield(Set(alarms.map(\.id)))
                }

                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
