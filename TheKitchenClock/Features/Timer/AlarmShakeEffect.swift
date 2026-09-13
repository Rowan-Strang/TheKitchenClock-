import SwiftUI

struct AlarmShakeEffect: ViewModifier {
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    func body(content: Content) -> some View {
        if isActive {
            if accessibilityReduceMotion {
                content
                    .phaseAnimator([0.92, 1]) { content, opacity in
                        content.opacity(opacity)
                    } animation: { _ in
                        .easeInOut(duration: 0.6)
                    }
            } else {
                content
                    .phaseAnimator([-12, 12]) { content, horizontalOffset in
                        content.offset(x: horizontalOffset)
                    } animation: { _ in
                        .linear(duration: 0.07)
                    }
            }
        } else {
            content
        }
    }
}
