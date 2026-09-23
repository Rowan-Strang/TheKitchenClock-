import SwiftUI

struct TimerLiveActivityCountdown: View {
    let state: TimerLiveActivityAttributes.ContentState
    let font: Font

    var body: some View {
        Group {
            if state.isFinished {
                Text("00:00")
            } else {
                Text(
                    timerInterval: state.startDate...state.deadline,
                    countsDown: true,
                    showsHours: true
                )
            }
        }
        .font(font.monospacedDigit())
        .foregroundStyle(.white)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}
