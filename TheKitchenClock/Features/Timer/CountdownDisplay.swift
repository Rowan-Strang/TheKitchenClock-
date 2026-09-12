import SwiftUI

struct CountdownDisplay: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(.largeTitle, design: .rounded).scaled(by: 4))
            .monospacedDigit()
            .bold()
            .lineLimit(1)
            .minimumScaleFactor(0.55)
            .accessibilityLabel("\(text) remaining")
    }
}

#Preview {
    CountdownDisplay(text: "00:30")
        .padding()
}
