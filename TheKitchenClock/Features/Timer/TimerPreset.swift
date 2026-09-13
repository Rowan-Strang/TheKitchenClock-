import Foundation

struct TimerPreset: Codable, Equatable, Identifiable {
    static let defaultPreset = TimerPreset(duration: .seconds(30))

    let durationSeconds: Int64

    var id: Int64 {
        durationSeconds
    }

    var duration: Duration {
        .seconds(durationSeconds)
    }

    init(duration: Duration) {
        durationSeconds = min(
            max(duration.components.seconds, 1),
            99 * 3_600 + 59 * 60 + 59
        )
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let durationSeconds = try container.decode(Int64.self)

        guard (1...(99 * 3_600 + 59 * 60 + 59)).contains(durationSeconds) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Preset durations must be between 1 second and 99:59:59."
            )
        }

        self.durationSeconds = durationSeconds
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(durationSeconds)
    }
}
