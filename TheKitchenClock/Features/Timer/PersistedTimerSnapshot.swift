import Foundation

struct PersistedTimerSnapshot: Codable, Equatable {
    let selectedDurationSeconds: Int64
    let state: PersistedTimerState
    let isRepeatEnabled: Bool
    let presets: [TimerPreset]
    let isAwaitingRepeatCycleAcknowledgement: Bool
    let oneShotAlarmID: UUID?
    let loopAlarmSession: PersistedLoopAlarmSession?

    init(
        selectedDurationSeconds: Int64,
        state: PersistedTimerState,
        isRepeatEnabled: Bool = false,
        presets: [TimerPreset] = [.defaultPreset],
        isAwaitingRepeatCycleAcknowledgement: Bool = false,
        oneShotAlarmID: UUID? = nil,
        loopAlarmSession: PersistedLoopAlarmSession? = nil
    ) {
        self.selectedDurationSeconds = selectedDurationSeconds
        self.state = state
        self.isRepeatEnabled = isRepeatEnabled
        self.presets = presets
        self.isAwaitingRepeatCycleAcknowledgement = isAwaitingRepeatCycleAcknowledgement
        self.oneShotAlarmID = oneShotAlarmID
        self.loopAlarmSession = loopAlarmSession
    }

    private enum CodingKeys: String, CodingKey {
        case selectedDurationSeconds
        case state
        case isRepeatEnabled
        case presets
        case isAwaitingRepeatCycleAcknowledgement
        case oneShotAlarmID
        case loopAlarmSession
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
        oneShotAlarmID = try container.decodeIfPresent(UUID.self, forKey: .oneShotAlarmID)
        loopAlarmSession = try container.decodeIfPresent(PersistedLoopAlarmSession.self, forKey: .loopAlarmSession)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(selectedDurationSeconds, forKey: .selectedDurationSeconds)
        try container.encode(state, forKey: .state)
        try container.encode(isRepeatEnabled, forKey: .isRepeatEnabled)
        try container.encode(presets, forKey: .presets)
        try container.encode(isAwaitingRepeatCycleAcknowledgement, forKey: .isAwaitingRepeatCycleAcknowledgement)
        try container.encodeIfPresent(oneShotAlarmID, forKey: .oneShotAlarmID)
        try container.encodeIfPresent(loopAlarmSession, forKey: .loopAlarmSession)
    }

    func replacingAlarmState(
        oneShotAlarmID: UUID?,
        loopAlarmSession: PersistedLoopAlarmSession?,
        isAwaitingRepeatCycleAcknowledgement: Bool? = nil
    ) -> Self {
        Self(
            selectedDurationSeconds: selectedDurationSeconds,
            state: state,
            isRepeatEnabled: isRepeatEnabled,
            presets: presets,
            isAwaitingRepeatCycleAcknowledgement: isAwaitingRepeatCycleAcknowledgement
                ?? self.isAwaitingRepeatCycleAcknowledgement,
            oneShotAlarmID: oneShotAlarmID,
            loopAlarmSession: loopAlarmSession
        )
    }
}
