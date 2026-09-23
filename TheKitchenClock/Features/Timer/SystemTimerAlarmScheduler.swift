@preconcurrency import AlarmKit
import AppIntents
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
        let stopIntent: any LiveActivityIntent

        if let loopContext {
            stopIntent = LoopAlarmStopIntent(
                alarmID: id.uuidString,
                sessionID: loopContext.sessionID.uuidString,
                cycleIndex: loopContext.cycleIndex
            )
        } else {
            stopIntent = OneShotAlarmStopIntent(alarmID: id.uuidString)
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

    func tearDown(ids: Set<UUID>) {
        guard !ids.isEmpty else {
            return
        }

        let alertingIDs = (try? currentAlarmStatus().alertingIDs) ?? []

        for id in ids {
            if alertingIDs.contains(id) {
                do {
                    try stop(id: id)
                } catch {
                    try? cancel(id: id)
                }
            } else {
                do {
                    try cancel(id: id)
                } catch {
                    try? stop(id: id)
                }
            }
        }
    }

    func currentAlarmStatus() throws -> TimerAlarmStatus {
        Self.status(for: try alarmManager.alarms)
    }

    func alarmUpdates() -> AsyncStream<TimerAlarmStatus> {
        let updates = alarmManager.alarmUpdates

        return AsyncStream { continuation in
            let task = Task {
                for await alarms in updates {
                    continuation.yield(Self.status(for: alarms))
                }

                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private static func status(for alarms: [Alarm]) -> TimerAlarmStatus {
        TimerAlarmStatus(
            activeIDs: Set(alarms.map(\.id)),
            alertingIDs: Set(alarms.filter { $0.state == .alerting }.map(\.id))
        )
    }
}
