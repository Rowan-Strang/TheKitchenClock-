import Foundation

enum TimerDurationFormatter {
    static func string(for duration: Duration) -> String {
        let totalSeconds = max(duration.components.seconds, 0)
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60

        let formattedMinutes = minutes.formatted(.number.precision(.integerLength(2)))
        let formattedSeconds = seconds.formatted(.number.precision(.integerLength(2)))

        if hours > 0 {
            let formattedHours = hours.formatted(.number.precision(.integerLength(2)))
            return "\(formattedHours):\(formattedMinutes):\(formattedSeconds)"
        }

        return "\(formattedMinutes):\(formattedSeconds)"
    }
}
