import SwiftUI

struct CountdownDisplay: View {
    let text: String
    let fontScale: CGFloat
    let accessibilityLabel: String

    init(
        text: String,
        fontScale: CGFloat = 4,
        accessibilityLabel: String? = nil
    ) {
        self.text = text
        self.fontScale = fontScale
        self.accessibilityLabel = accessibilityLabel ?? "\(text) remaining"
    }

    var body: some View {
        Text(text)
            .font(.system(.largeTitle, design: .rounded).scaled(by: fontScale))
            .monospacedDigit()
            .bold()
            .lineLimit(1)
            .minimumScaleFactor(0.55)
            .accessibilityLabel(accessibilityLabel)
    }
}

#Preview {
    CountdownDisplay(text: "00:30")
        .padding()
}
