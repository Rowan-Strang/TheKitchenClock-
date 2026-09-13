import SwiftUI

struct RepeatCycleAcknowledgement: View {
    let onAcknowledge: () -> Void

    var body: some View {
        VStack {
            Text("Cycle Finished")
                .font(.title2)
                .bold()

            Text("The next cycle is already running.")
                .foregroundStyle(.secondary)

            Label("Repeat On", systemImage: "repeat")
                .font(.callout)
                .foregroundStyle(.secondary)

            Button("Continue", systemImage: "arrow.forward.circle.fill", action: onAcknowledge)
                .frame(maxWidth: .infinity, minHeight: 128)
                .buttonStyle(.borderedProminent)
                .padding(.top)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }
}
