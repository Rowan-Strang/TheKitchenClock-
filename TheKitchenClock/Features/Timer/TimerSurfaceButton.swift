import SwiftUI

struct TimerSurfaceButton<Content: View>: View {
    let isReady: Bool
    let isStarting: Bool
    let isAwaitingCompletionAcknowledgement: Bool
    let isAwaitingRepeatCycleAcknowledgement: Bool
    let accessibilityValue: String
    let onStart: () async -> Void
    let onEnableRepeatAndStart: () async -> Void
    let onAcknowledge: () async -> Void
    let onCancelAlarm: () async -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        if isReady {
            Button {
                Task {
                    await onStart()
                }
            } label: {
                content()
                    .background {
                        Rectangle().fill(.clear)
                    }
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(isStarting)
            .accessibilityLabel("Start timer")
            .accessibilityValue(accessibilityValue)
            .accessibilityHint("Double-tap to start. Use the Start Repeating Timer action to enable repeat and start.")
            .accessibilityAction(named: "Start Repeating Timer") {
                Task {
                    await onEnableRepeatAndStart()
                }
            }
            .highPriorityGesture(
                LongPressGesture(minimumDuration: 0.75)
                    .onEnded { _ in
                        Task {
                            await onEnableRepeatAndStart()
                        }
                    }
            )
        } else if isAwaitingCompletionAcknowledgement {
            Button {
                Task {
                    await onAcknowledge()
                }
            } label: {
                content()
                    .background {
                        Rectangle().fill(.clear)
                    }
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Acknowledge timer alarm")
            .accessibilityValue(accessibilityValue)
            .accessibilityHint(
                isAwaitingRepeatCycleAcknowledgement
                    ? "Double-tap to dismiss the alarm while the next cycle continues. Touch and hold to clear the alarm and stop repeating."
                    : "Double-tap or touch and hold to dismiss the alarm and return to the configured duration."
            )
            .accessibilityAction(named: isAwaitingRepeatCycleAcknowledgement ? "Stop Repeating Timer" : "Clear Timer Alarm") {
                Task {
                    await onCancelAlarm()
                }
            }
            .highPriorityGesture(
                LongPressGesture(minimumDuration: 0.75)
                    .onEnded { _ in
                        Task {
                            await onCancelAlarm()
                        }
                    }
            )
        } else {
            content()
        }
    }
}
