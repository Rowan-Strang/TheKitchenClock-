import Foundation

struct PersistedTimerSnapshot: Codable, Equatable {
    let selectedDurationSeconds: Int64
    let state: PersistedTimerState
    let isRepeatEnabled: Bool
    let presets: [TimerPreset]
    let isAwaitingRepeatCycleAcknowledgement: Bool

    init(
        selectedDurationSeconds: Int64,
        state: PersistedTimerState,
        isRepeatEnabled: Bool = false,
        presets: [TimerPreset] = [.defaultPreset],
        isAwaitingRepeatCycleAcknowledgement: Bool = false
    ) {
        self.selectedDurationSeconds = selectedDurationSeconds
        self.state = state
        self.isRepeatEnabled = isRepeatEnabled
        self.presets = presets
        self.isAwaitingRepeatCycleAcknowledgement = isAwaitingRepeatCycleAcknowledgement
    }

    private enum CodingKeys: String, CodingKey {
        case selectedDurationSeconds
        case state
        case isRepeatEnabled
        case presets
        case isAwaitingRepeatCycleAcknowledgement
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        selectedDurationSeconds = try container.decode(Int64.self, forKey: .selectedDurationSeconds)
        state = try container.decode(PersistedTimerState.self, forKey: .state)
        isRepeatEnabled = try container.decodeIfPresent(Bool.self, forKey: .isRepeatEnabled) ?? false
        presets = try container.decodeIfPresent([TimerPreset].self, forKey: .presets) ?? [.defaultPreset]
        isAwaitingRepeatCycleAcknowledgement = try container.decodeIfPresent(
            Bool.self,
            forKey: .isAwaitingRepeatCycleAcknowledgement
        ) ?? false
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(selectedDurationSeconds, forKey: .selectedDurationSeconds)
        try container.encode(state, forKey: .state)
        try container.encode(isRepeatEnabled, forKey: .isRepeatEnabled)
        try container.encode(presets, forKey: .presets)
        try container.encode(isAwaitingRepeatCycleAcknowledgement, forKey: .isAwaitingRepeatCycleAcknowledgement)
    }
}
