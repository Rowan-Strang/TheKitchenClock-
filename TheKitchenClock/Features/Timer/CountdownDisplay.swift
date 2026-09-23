import SwiftUI

struct CountdownDisplay: View {
    let text: String
    let fontScale: CGFloat
    let accessibilityLabel: String
    let startFeedbackTrigger: Int

    private enum StartFeedbackPhase: CaseIterable {
        case resting
        case lifted
        case landing
        case settled

        var scale: CGFloat {
            switch self {
            case .resting, .settled:
                1
            case .lifted:
                1.13
            case .landing:
                0.98
            }
        }

        var verticalOffset: CGFloat {
            switch self {
            case .resting, .settled:
                0
            case .lifted:
                -10
            case .landing:
                2
            }
        }

        var reducedMotionOpacity: CGFloat {
            switch self {
            case .resting, .settled:
                1
            case .lifted:
                0.7
            case .landing:
                0.9
            }
        }
    }

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    init(
        text: String,
        fontScale: CGFloat = 4,
        accessibilityLabel: String? = nil,
        startFeedbackTrigger: Int = 0
    ) {
        self.text = text
        self.fontScale = fontScale
        self.accessibilityLabel = accessibilityLabel ?? "\(text) remaining"
        self.startFeedbackTrigger = startFeedbackTrigger
    }

    var body: some View {
        Text(text)
            .font(.system(.largeTitle, design: .rounded).scaled(by: fontScale))
            .monospacedDigit()
            .bold()
            .lineLimit(1)
            .minimumScaleFactor(0.55)
            .accessibilityLabel(accessibilityLabel)
            .phaseAnimator(StartFeedbackPhase.allCases, trigger: startFeedbackTrigger) { content, phase in
                if accessibilityReduceMotion {
                    content.opacity(phase.reducedMotionOpacity)
                } else {
                    content
                        .scaleEffect(phase.scale)
                        .offset(y: phase.verticalOffset)
                }
            } animation: { _ in
                if accessibilityReduceMotion {
                    .easeInOut(duration: 0.2)
                } else {
                    .spring(duration: 0.45, bounce: 0.4)
                }
            }
    }
}

#Preview {
    CountdownDisplay(text: "00:30")
        .padding()
}
