import SwiftUI

struct RepeatStartButton: View {
    let title: String
    let hint: String
    let onStart: () -> Void
    let onToggleRepeatAndStart: () -> Void

    var body: some View {
        Button(title, action: onStart)
            .frame(maxWidth: .infinity, minHeight: 128)
            .buttonStyle(.borderedProminent)
            .accessibilityHint(hint)
            .accessibilityAction(named: "Toggle repeat and start") {
                onToggleRepeatAndStart()
            }
            .highPriorityGesture(
                LongPressGesture(minimumDuration: 0.75)
                    .onEnded { _ in
                        onToggleRepeatAndStart()
                    }
            )
    }
}
