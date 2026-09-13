import SwiftUI

struct TimerSurfaceButton<Content: View>: View {
    let isReady: Bool
    let isAwaitingCompletionAcknowledgement: Bool
    let accessibilityValue: String
    let onStart: () -> Void
    let onEnableRepeatAndStart: () -> Void
    let onAcknowledge: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        if isReady {
            Button(action: onStart) {
                content()
                    .background {
                        Rectangle().fill(.clear)
                    }
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Start timer")
            .accessibilityValue(accessibilityValue)
            .accessibilityHint("Double-tap to start. Use the Start Repeating Timer action to enable repeat and start.")
            .accessibilityAction(named: "Start Repeating Timer") {
                onEnableRepeatAndStart()
            }
            .highPriorityGesture(
                LongPressGesture(minimumDuration: 0.75)
                    .onEnded { _ in
                        onEnableRepeatAndStart()
                    }
            )
        } else if isAwaitingCompletionAcknowledgement {
            Button(action: onAcknowledge) {
                content()
                    .background {
                        Rectangle().fill(.clear)
                    }
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Acknowledge timer alarm")
            .accessibilityValue(accessibilityValue)
            .accessibilityHint("Double-tap to dismiss the alarm and return to the configured duration.")
        } else {
            content()
        }
    }
}
