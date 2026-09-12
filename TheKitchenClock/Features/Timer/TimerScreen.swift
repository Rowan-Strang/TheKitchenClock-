import SwiftUI

struct TimerScreen: View {
    @State private var viewModel = TimerViewModel()

    var body: some View {
        VStack {
            Spacer(minLength: 0)

            VStack {
                Text(viewModel.state.title)
                    .font(.headline)
                    .foregroundStyle(.secondary)

                CountdownDisplay(text: viewModel.displayText)
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: 0)

            Button(action: {}) {
                Text("Start")
                    .frame(maxWidth: .infinity, minHeight: 128)
            }
                .buttonStyle(.borderedProminent)
                .accessibilityHint("Starting a timer will be added in the next milestone.")
        }
        .padding()
    }
}

#Preview("iPhone") {
    TimerScreen()
}

#Preview("iPad", traits: .fixedLayout(width: 1_024, height: 768)) {
    TimerScreen()
}
