enum LoopAlarmQueueReplenishmentResult: Equatable {
    case completed(hasFailure: Bool)
    case invalidated
}
