import SwiftUI

struct RepeatCycleAcknowledgement: View {
    let onAcknowledge: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            Button("Done", action: onAcknowledge)
                .font(.title)
                .bold()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .buttonStyle(.borderedProminent)
                .containerRelativeFrame(.vertical, count: 2, span: 1, spacing: 0)
        }
        .frame(maxWidth: .infinity)
        .containerRelativeFrame(.vertical, count: 2, span: 2, spacing: 0)
        .accessibilityElement(children: .contain)
    }
}
