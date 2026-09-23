import ActivityKit
import Foundation

nonisolated struct TimerLiveActivityAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable {
        let startDate: Date
        let deadline: Date
        let isFinished: Bool
    }

    let sessionID: UUID
}
